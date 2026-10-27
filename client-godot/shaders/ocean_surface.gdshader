shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Terrain-aware tropical ocean for the Godot 4.7.2 Mobile renderer.
// Opaque on purpose: keeps early depth writes and avoids a screen-texture
// pass on mobile. Shallow-water transparency is approximated from the real
// sampled seabed height (shore heightfield) instead of a refraction pass.
// Visual quality must still be judged against actual Godot footage.
uniform vec4 water_shallow : source_color = vec4(0.07, 0.60, 0.58, 1.0);
uniform vec4 water_mid : source_color = vec4(0.015, 0.30, 0.42, 1.0);
uniform vec4 water_deep : source_color = vec4(0.006, 0.075, 0.19, 1.0);
uniform vec4 seabed_sand : source_color = vec4(0.80, 0.72, 0.55, 1.0);
uniform vec4 foam_tint : source_color = vec4(0.93, 0.97, 0.97, 1.0);
uniform vec4 sky_reflection : source_color = vec4(0.30, 0.50, 0.68, 1.0);
uniform float swell_scale : hint_range(0.0, 1.5) = 1.0;
uniform float ripple_detail : hint_range(0.0, 1.0) = 0.9;
uniform float foam_amount : hint_range(0.0, 1.0) = 0.7;
// Shorebreak bands travel up the sampled depth gradient toward the beach.
uniform float shorebreak_speed : hint_range(0.0, 4.0) = 1.15;
uniform float shorebreak_spacing : hint_range(0.5, 12.0) = 4.2;
// The capture harness sets this to the exact frame time. Ordinary gameplay
// continues to use Godot TIME when deterministic_capture is disabled.
uniform bool deterministic_capture = false;
uniform float capture_time_seconds = 0.0;

const float SEA_LEVEL = -0.35;
varying vec3 surface_world;
varying float swell_crest;

// Imported from the exact indexed PBR terrain mesh by PR #173's baker.
// Binds once at scene load. Unbound height data must never invent foam.
#include "res://shaders/coastal_shore_sampler.gdshaderinc"
uniform bool shoremap_bound = false;
uniform vec2 near_patch_half_extent = vec2(92.0, 70.0);

// Hash-based value noise with analytic derivatives (no texture fetch, no
// external asset). Aperiodic, so the surface cannot tile into a visible grid.
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec3 noised(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    vec2 du = 6.0 * f * (1.0 - f);
    float a = hash12(i);
    float b = hash12(i + vec2(1.0, 0.0));
    float c = hash12(i + vec2(0.0, 1.0));
    float d = hash12(i + vec2(1.0, 1.0));
    float k1 = b - a;
    float k2 = c - a;
    float k4 = a - b - c + d;
    return vec3(a + k1 * u.x + k2 * u.y + k4 * u.x * u.y,
                du * vec2(k1 + k4 * u.y, k2 + k4 * u.x));
}

// Four rotated, independently drifting octaves. Returns height in x and
// world-space slope in yz, used for the per-pixel ripple normal.
vec3 ripple_field(vec2 p, float t) {
    const mat2 rot = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
    vec3 sum = vec3(0.0);
    float amp = 0.5;
    float freq = 0.55;
    vec2 drift = vec2(0.34, 0.21);
    mat2 basis = mat2(1.0);
    for (int i = 0; i < 4; i++) {
        vec3 n = noised(basis * p * freq + drift * t * (1.0 + float(i) * 0.6));
        sum.x += n.x * amp;
        sum.yz += (transpose(basis) * n.yz) * amp * freq;
        amp *= 0.52;
        freq *= 2.07;
        basis = rot * basis;
        drift = rot * drift * -1.1;
    }
    return sum;
}

// Directional Gerstner-style swell: summed height and analytic slope.
void add_wave(vec2 xz, vec2 dir, float wavelength, float amplitude, float speed,
              float t, inout float height, inout vec2 slope) {
    float k = 6.28318 / wavelength;
    float phase = dot(xz, normalize(dir)) * k - t * speed * k;
    height += sin(phase) * amplitude;
    slope += normalize(dir) * cos(phase) * amplitude * k;
}

void vertex() {
    float ocean_time = deterministic_capture ? capture_time_seconds : TIME;
    vec2 xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
    float height = 0.0;
    vec2 slope = vec2(0.0);
    // Non-harmonic wavelengths and spread directions avoid a repeating
    // interference lattice across the cove.
    add_wave(xz, vec2(0.84, 0.54), 13.7, 0.085, 1.9, ocean_time, height, slope);
    add_wave(xz, vec2(-0.31, 0.95), 8.9, 0.050, 1.6, ocean_time, height, slope);
    add_wave(xz, vec2(0.97, -0.24), 5.3, 0.026, 1.25, ocean_time, height, slope);
    add_wave(xz, vec2(0.21, 0.98), 3.1, 0.013, 1.0, ocean_time, height, slope);
    add_wave(xz, vec2(-0.72, 0.69), 2.3, 0.008, 0.85, ocean_time, height, slope);
    // Shoaling: swell height grows slightly over the shelf, then collapses in
    // the swash zone so water never rises through dry sand.
    float coverage = shore_terrain_coverage(xz) * float(shoremap_bound);
    float signed_depth = SEA_LEVEL - shore_terrain_height(xz);
    float depth_m = max(signed_depth, 0.0);
    // Swell grows slightly over the shelf, then decays to nothing at the
    // waterline so water never rises in a sheet over the shallow beach.
    float shoal = mix(1.0, smoothstep(0.0, 1.4, depth_m)
        * (1.0 + 0.25 * smoothstep(0.4, 1.4, depth_m) * (1.0 - smoothstep(1.6, 6.0, depth_m))), coverage);
    float fade_x = 1.0 - smoothstep(near_patch_half_extent.x - 18.0,
        near_patch_half_extent.x - 1.0, abs(xz.x));
    float fade_z = 1.0 - smoothstep(near_patch_half_extent.y - 18.0,
        near_patch_half_extent.y - 1.0, abs(xz.y));
    float envelope = fade_x * fade_z * swell_scale * shoal;
    // Keep the far ocean at SEA_LEVEL: the mesh is positioned 0.18m below it.
    // Fade only the animated displacement, never the base offset.
    // Over dry land hold the opaque surface a few centimetres under sea
    // level so the terrain occludes it; no steep draped sheet across the
    // 4 m ocean triangles.
    float land = coverage * smoothstep(0.0, 0.05, -signed_depth);
    VERTEX.y += 0.18 + height * envelope - land * 0.06;
    NORMAL = normalize(vec3(-slope.x * envelope, 1.0, -slope.y * envelope));
    surface_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    swell_crest = height * envelope;
}

void fragment() {
    float ocean_time = deterministic_capture ? capture_time_seconds : TIME;
    vec2 p = surface_world.xz;
    float coverage = shore_terrain_coverage(p) * float(shoremap_bound);
    float floor_y = shore_terrain_height(p);
    // Open ocean outside the baked mesh footprint is genuinely deep.
    float depth_m = mix(40.0, max(SEA_LEVEL - floor_y, 0.0), coverage);

    // Aperiodic multi-octave ripple normal, strongest offshore, calmer in
    // the shallows where bottom friction damps capillary waves.
    vec3 ripples = ripple_field(p * 0.9, ocean_time);
    float ripple_strength = ripple_detail * mix(0.24, 0.12, coverage * (1.0 - smoothstep(0.2, 2.5, depth_m)));
    // NORMAL_MAP is an encoded tangent-space value in Godot (0..1), not a
    // signed normal. Encode after normalizing so mobile lighting stays valid.
    NORMAL_MAP = normalize(vec3(-ripples.y * ripple_strength,
                                -ripples.z * ripple_strength, 1.0)) * 0.5 + 0.5;

    // Depth colour: Beer-Lambert style absorption over the sampled seabed.
    // Very shallow water shows the sand floor; mid depths turn turquoise and
    // teal; the open sea becomes deep navy.
    float sand_visibility = exp(-depth_m * 1.7);
    float turquoise = exp(-depth_m * 0.30);
    float teal = exp(-depth_m * 0.085);
    vec3 sea = mix(water_deep.rgb, water_mid.rgb, teal);
    sea = mix(sea, water_shallow.rgb, turquoise);
    // Cheap caustic shimmer over visible sand, bounded to the shallows.
    float caustic_a = noised(p * 1.7 + vec2(ocean_time * 0.31, ocean_time * 0.17)).x;
    float caustic_b = noised(p * 2.3 - vec2(ocean_time * 0.23, -ocean_time * 0.29)).x;
    float caustic = pow(1.0 - abs(caustic_a - caustic_b), 6.0);
    vec3 floor_colour = seabed_sand.rgb * 0.82 * (0.82 + 0.38 * caustic);
    sea = mix(sea, floor_colour, sand_visibility * 0.78 * coverage);

    // Shorebreak: bands of constant phase move toward decreasing depth, so
    // breakers roll in and dissolve on the actual beach contour.
    float along_shore = noised(p * vec2(0.23, 0.31)).x;
    float band_phase = depth_m * (6.28318 / shorebreak_spacing) * 3.0
        + ocean_time * shorebreak_speed * 2.0 + along_shore * 2.4;
    float band = pow(max(sin(band_phase), 0.0), 7.0);
    float surf_zone = coverage * smoothstep(0.02, 0.18, depth_m)
        * (1.0 - smoothstep(0.9, 2.2, depth_m));
    float lace = noised(p * 3.2 + ripples.yz * 0.8 + vec2(0.0, ocean_time * 0.4)).x;
    float break_foam = band * surf_zone * smoothstep(0.30, 0.62, lace + band * 0.35);
    // Swash foam hugs the real waterline and breathes with the incoming sets.
    float swash_pulse = 0.55 + 0.45 * sin(ocean_time * shorebreak_speed * 0.9 + along_shore * 5.0);
    float contact = coverage * (1.0 - smoothstep(0.01, 0.05 + 0.07 * swash_pulse, depth_m));
    float contact_foam = contact * smoothstep(0.38, 0.70, lace + 0.12 * swash_pulse);
    // Sparse whitecaps on the highest offshore crests only.
    float crest_foam = smoothstep(0.11, 0.16, swell_crest) * smoothstep(0.55, 0.85, lace) * 0.35;
    float foam = clamp((break_foam * 0.9 + contact_foam + crest_foam) * foam_amount * 1.2, 0.0, 0.85);

    // Schlick fresnel with water's physical F0 (~0.02). The previous 0.86
    // specular mirrored the whole sky and flattened every depth colour.
    float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
    float fresnel = 0.02 + 0.98 * pow(1.0 - facing, 5.0);
    sea = mix(sea, sky_reflection.rgb, clamp(fresnel * 0.6, 0.0, 0.42));
    ALBEDO = mix(sea, foam_tint.rgb, foam);
    ROUGHNESS = mix(0.06, 0.72, foam);
    METALLIC = 0.0;
    SPECULAR = mix(0.25, 0.5, foam);
}
