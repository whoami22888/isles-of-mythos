shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Stylised tropical water for the compatibility renderer. Shalllows are
// translucent over the real sand mesh; mid and deep water stay opaque.
// Colour is driven by the baked shore heightfield, never a flat #00BFFF slab.
uniform vec4 water_shallow : source_color = vec4(0.60, 0.82, 0.74, 1.0);
uniform vec4 water_mid : source_color = vec4(0.10, 0.32, 0.34, 1.0);
uniform vec4 water_deep : source_color = vec4(0.04, 0.12, 0.22, 1.0);
uniform vec4 foam_tint : source_color = vec4(0.90, 0.93, 0.90, 1.0);
uniform sampler2D water_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 sun_dir = vec3(0.35, 0.75, 0.55);
uniform vec2 vessel_xz = vec2(1.0, -5.8);
uniform vec2 vessel_forward = vec2(0.309, -0.951);
uniform float wake_strength : hint_range(0.0, 1.0) = 0.8;
uniform float swell_scale : hint_range(0.0, 1.5) = 1.0;
uniform float ripple_detail : hint_range(0.0, 1.0) = 0.9;
uniform float foam_amount : hint_range(0.0, 1.0) = 0.7;
uniform bool deterministic_capture = false;
uniform float capture_time_seconds = 0.0;

const float SEA_LEVEL = -0.35;
varying vec3 surface_world;
varying float swell_crest;

#include "res://shaders/coastal_shore_sampler.gdshaderinc"
uniform bool shoremap_bound = false;
uniform vec2 near_patch_half_extent = vec2(92.0, 70.0);

void vertex() {
	float ocean_time = deterministic_capture ? capture_time_seconds : TIME;
	vec2 xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	float a = dot(xz, vec2(0.84, 0.54)) * 0.55 - ocean_time * 0.90;
	float b = dot(xz, vec2(-0.43, 0.90)) * 1.16 - ocean_time * 1.35;
	float c = dot(xz, vec2(0.95, -0.31)) * 2.25 - ocean_time * 1.90;
	float displacement = (sin(a) * 0.090 + sin(b) * 0.044 + sin(c) * 0.015) * swell_scale;
	float dx = (cos(a) * 0.090 * 0.55 * 0.84
			  + cos(b) * 0.044 * 1.16 * -0.43
			  + cos(c) * 0.015 * 2.25 * 0.95) * swell_scale;
	float dz = (cos(a) * 0.090 * 0.55 * 0.54
			  + cos(b) * 0.044 * 1.16 * 0.90
			  + cos(c) * 0.015 * 2.25 * -0.31) * swell_scale;
	float fade_x = 1.0 - smoothstep(near_patch_half_extent.x - 18.0,
		near_patch_half_extent.x - 1.0, abs(xz.x));
	float fade_z = 1.0 - smoothstep(near_patch_half_extent.y - 18.0,
		near_patch_half_extent.y - 1.0, abs(xz.y));
	float envelope = fade_x * fade_z;
	VERTEX.y += 0.18 + displacement * envelope;
	NORMAL = normalize(vec3(-dx * envelope, 1.0, -dz * envelope));
	surface_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	swell_crest = displacement * envelope;
}

void fragment() {
	float ocean_time = deterministic_capture ? capture_time_seconds : TIME;
	vec2 p = surface_world.xz;
	float coverage = shore_terrain_coverage(p) * float(shoremap_bound);
	float floor_y = shore_terrain_height(p);
	float depth_m = max(SEA_LEVEL - floor_y, 0.0);
	float deep_open = 1.0 - coverage;

	// Three irregular ripple scales. Perturb NORMAL in world/view space so
	// mesh tangents cannot re-impose a UV lattice on the compatibility path.
	vec2 uv1 = p * 0.07 + vec2(ocean_time * 0.018, ocean_time * -0.011);
	vec2 uv2 = p * 0.19 + vec2(ocean_time * -0.027, ocean_time * 0.016);
	vec2 uv3 = p * 0.41 + vec2(ocean_time * 0.033, ocean_time * 0.021);
	vec3 n1 = texture(water_normal, uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(water_normal, uv2).rgb * 2.0 - 1.0;
	vec3 n3 = texture(water_normal, uv3).rgb * 2.0 - 1.0;
	vec2 ripple = (n1.xy * 0.50 + n2.xy * 0.32 + n3.xy * 0.18) * ripple_detail * 0.45;
	vec3 n_world = normalize(vec3(ripple.x, 1.0, ripple.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	// Pale turquoise over sand, teal mid-shelf, then a deeper blue offshore.
	vec3 sand = texture(sand_albedo, p * 0.20).rgb * vec3(1.08, 0.98, 0.82);
	float pale_w = coverage * (1.0 - smoothstep(0.05, 2.60, depth_m));
	float teal_w = coverage * smoothstep(1.80, 4.20, depth_m) * (1.0 - smoothstep(7.00, 12.0, depth_m));
	float navy_w = clamp(smoothstep(8.00, 15.0, depth_m) + deep_open, 0.0, 1.0);
	vec3 pale = mix(sand, water_shallow.rgb, 0.62);
	vec3 sea = mix(water_mid.rgb, pale, clamp(pale_w, 0.0, 1.0));
	sea = mix(sea, water_mid.rgb, clamp(teal_w, 0.0, 1.0));
	sea = mix(sea, water_deep.rgb, navy_w);
	float luma = dot(sea, vec3(0.30, 0.55, 0.15));
	sea = mix(vec3(luma), sea, 0.84);

	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - facing, 3.5);
	sea = mix(sea, vec3(0.48, 0.60, 0.66), fresnel * 0.12);

	// Soft shoreline foam band, plus a tighter wet edge.
	float foam_pattern = sin(p.x * 1.6 + ocean_time * 1.2) * cos(p.y * 2.1 - ocean_time * 0.85);
	foam_pattern += sin(p.x * 3.4 - p.y * 2.6 + ocean_time * 1.5) * 0.35;
	float foam_motion = smoothstep(-0.15, 0.72, foam_pattern);
	// Foam only in a thin shoreline band. A wide band turns the whole lagoon
	// into a repeating white checker because the shelf is ~0.5–1 m deep.
	float band = coverage * smoothstep(0.00, 0.10, depth_m) * (1.0 - smoothstep(0.22, 0.55, depth_m));
	float lip = coverage * (1.0 - smoothstep(0.00, 0.16, depth_m)) * smoothstep(-0.03, 0.04, depth_m);
	float shore_foam = (band * foam_motion * 0.90 + lip * 0.80) * foam_amount;

	vec2 fwd = vessel_forward;
	float fwd_len = length(fwd);
	fwd = fwd_len > 0.001 ? fwd / fwd_len : vec2(0.0, -1.0);
	vec2 side = vec2(-fwd.y, fwd.x);
	vec2 rel = p - vessel_xz;
	float along = dot(rel, -fwd);
	float across = abs(dot(rel, side));
	float wake_band = smoothstep(0.4, 2.0, along) * (1.0 - smoothstep(9.0, 28.0, along));
	float half_w = 1.25 + along * 0.18;
	float lane = 1.0 - smoothstep(half_w * 0.28, half_w, across);
	float wake_noise = 0.55 + 0.45 * sin(along * 1.35 + across * 3.2 + ocean_time * 1.6);
	float bow = 1.0 - smoothstep(0.35, 3.8, length(rel - fwd * 2.6));
	float hull = 1.0 - smoothstep(1.4, 3.8, length(rel));
	float wake = (wake_band * lane * wake_noise * 0.65 + bow * 0.55 + hull * 0.28) * wake_strength;
	float foam = clamp(shore_foam + wake, 0.0, 0.92);

	// Tight sun sparkles. Keep the half-vector in world space with sun_dir.
	vec3 ldir = normalize(sun_dir);
	vec3 view_world = normalize((INV_VIEW_MATRIX * vec4(VIEW, 0.0)).xyz);
	vec3 halfv = normalize(ldir + view_world);
	float glint = pow(max(dot(n_world, halfv), 0.0), 180.0) * (1.0 - foam) * 0.40;
	sea += vec3(1.0, 0.95, 0.84) * glint;

	ALBEDO = mix(sea, foam_tint.rgb, foam);
	ROUGHNESS = mix(mix(0.32, 0.50, pale_w), 0.88, foam);
	METALLIC = 0.0;
	SPECULAR = mix(0.42, 0.08, foam);
	// See-through only over the real sand shelf. Deep and open ocean stay solid
	// so the 640 m plane does not composite against the sky as a film of cyan.
	float clear = coverage * (1.0 - smoothstep(0.04, 1.35, depth_m));
	ALPHA = mix(1.0, 0.34, clear * (1.0 - foam));
}
