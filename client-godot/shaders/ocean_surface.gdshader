shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Animated 3-scale swell with analytic vertex normals. This material is opaque
// on purpose: it retains early depth writes and mobile forward rendering.
// Surface quality must still be checked against actual Godot footage.
uniform vec4 water_shallow : source_color = vec4(0.10, 0.78, 0.72, 1.0);
uniform vec4 water_deep : source_color = vec4(0.015, 0.14, 0.38, 1.0);
uniform vec4 foam_tint : source_color = vec4(0.95, 0.98, 0.96, 1.0);
// Still-frame bow foam and stern trail. The moving ribbon in ShipWakeEffect
// remains the animated history; this term keeps a wake when the vessel is idle.
uniform vec2 vessel_xz = vec2(1.0, -5.8);
uniform vec2 vessel_forward = vec2(0.309, -0.951);
uniform float wake_strength : hint_range(0.0, 1.0) = 0.8;
uniform float swell_scale : hint_range(0.0, 1.5) = 1.0;
uniform float ripple_detail : hint_range(0.0, 1.0) = 0.9;
uniform float foam_amount : hint_range(0.0, 1.0) = 0.7;
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
    // One contiguous ocean mesh; fade geometric swells outside near camera
    // distances without changing material colour, alpha or draw surface.
    // Distant water retains its animated per-pixel normal detail.
    float fade_x = 1.0 - smoothstep(near_patch_half_extent.x - 18.0,
        near_patch_half_extent.x - 1.0, abs(xz.x));
    float fade_z = 1.0 - smoothstep(near_patch_half_extent.y - 18.0,
        near_patch_half_extent.y - 1.0, abs(xz.y));
    float envelope = fade_x * fade_z;
    // Keep the far ocean at SEA_LEVEL: the mesh is positioned 0.18m below it.
    // Fading the base offset created a visible rectangular height shelf at the
    // near-patch boundary. Fade only the animated displacement.
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
    // NO replicated terrain height equation and NO rectangular contact mask.
    // Open ocean is genuinely deep outside the source mesh footprint.
    // Wide turquoise shelf, then a real falloff into deep blue. Crest foam is
    // intentionally not added here: it turned every swell peak into a white tile.
    float depth_factor = 1.0 - smoothstep(0.15, 6.5, depth_m);
    float seabed_variation = 0.86 + 0.14 * sin(dot(p, vec2(0.045, 0.03)));
    float shallow_factor = coverage * depth_factor * seabed_variation;
    float contact = coverage * smoothstep(0.02, 0.12, depth_m)
                    * (1.0 - smoothstep(0.16, 0.55, depth_m));

    // Gentle micro normals. High-frequency normals plus a shiny roughness
    // produced a repeating diamond lattice under the mobile specular model.
    float micro_a = sin(dot(p, vec2(1.15, 0.72)) - ocean_time * 1.4);
    float micro_b = cos(dot(p, vec2(-0.66, 1.05)) + ocean_time * 1.05);
    // NORMAL_MAP is an encoded tangent-space value in Godot (0..1), not a
    // signed normal. Encode the analytic wave normal after normalizing so
    // mobile lighting does not invert or blacken the water response.
    NORMAL_MAP = normalize(vec3(
        (micro_a * 0.07 + micro_b * 0.04) * ripple_detail,
        (micro_a * -0.05 + micro_b * 0.06) * ripple_detail,
        1.0
    )) * 0.5 + 0.5;

    float foam_pattern = sin(p.x * 1.6 + ocean_time * 1.2)
                       * cos(p.y * 2.1 - ocean_time * 0.85);
    foam_pattern += sin(p.x * 3.4 - p.y * 2.6 + ocean_time * 1.5) * 0.35;
    float foam_motion = smoothstep(-0.15, 0.72, foam_pattern);
    float shore_foam = contact * foam_motion * foam_amount;

    vec2 fwd = vessel_forward;
    float fwd_len = length(fwd);
    fwd = fwd_len > 0.001 ? fwd / fwd_len : vec2(0.0, -1.0);
    vec2 side = vec2(-fwd.y, fwd.x);
    vec2 rel = p - vessel_xz;
    float along = dot(rel, -fwd);
    float across = abs(dot(rel, side));
    float wake_band = smoothstep(0.6, 2.2, along) * (1.0 - smoothstep(9.0, 28.0, along));
    float half_w = 1.15 + along * 0.16;
    float lane = 1.0 - smoothstep(half_w * 0.28, half_w, across);
    float wake_noise = 0.55 + 0.45 * sin(along * 1.35 + across * 3.2 + ocean_time * 1.6);
    float bow = 1.0 - smoothstep(0.35, 3.6, length(rel - fwd * 2.6));
    float wake = (wake_band * lane * wake_noise * 0.55 + bow * 0.35) * wake_strength;
    float foam = clamp(shore_foam + wake, 0.0, 0.82);

    vec3 gulf = mix(water_deep.rgb, water_deep.rgb * vec3(0.72, 0.92, 1.18),
        0.5 + 0.5 * sin(dot(p, vec2(0.02, 0.013))));
    vec3 sea = mix(gulf, water_shallow.rgb, clamp(shallow_factor, 0.0, 1.0));
    sea += vec3((micro_a + micro_b) * 0.012 * ripple_detail);
    float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
    float fresnel = pow(1.0 - facing, 4.0);
    sea = mix(sea, vec3(0.55, 0.78, 0.82), fresnel * 0.22);
    ALBEDO = mix(sea, foam_tint.rgb, foam);
    ROUGHNESS = mix(0.68, 0.86, foam);
    METALLIC = 0.0;
    SPECULAR = mix(0.16, 0.08, foam);
}
