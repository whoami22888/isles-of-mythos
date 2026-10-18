shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Animated 3-scale swell with analytic vertex normals. This material is opaque
// on purpose: it retains early depth writes and mobile forward rendering.
// Surface quality must still be checked against actual Godot footage.
uniform vec4 water_shallow : source_color = vec4(0.024, 0.235, 0.315, 1.0);
uniform vec4 water_deep : source_color = vec4(0.009, 0.07, 0.15, 1.0);
uniform vec4 foam_tint : source_color = vec4(0.76, 0.91, 0.91, 1.0);
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
    VERTEX.y += (0.18 + displacement) * envelope;
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
    float shallow_factor = coverage * (1.0 - smoothstep(0.05, 4.2, depth_m));
    float contact = coverage * smoothstep(0.01, 0.055, depth_m)
                    * (1.0 - smoothstep(0.09, 0.74, depth_m));

    // Two counter-moving normal frequencies animate highlights on the water.
    // No screen-space reflection pass or full-screen postprocess is required.
    float micro_a = sin(dot(p, vec2(3.1, 1.55)) - ocean_time * 2.35);
    float micro_b = cos(dot(p, vec2(-1.92, 3.38)) + ocean_time * 1.68);
    NORMAL_MAP = normalize(vec3(
        (micro_a * 0.12 + micro_b * 0.055) * ripple_detail,
        (micro_a * -0.085 + micro_b * 0.11) * ripple_detail,
        1.0
    ));

    // Break up the coastal foam so it moves without straight bright strips.
    float foam_pattern = sin(p.x * 2.0 + ocean_time * 1.2)
                       * cos(p.y * 2.8 - ocean_time * 0.85);
    foam_pattern += sin(p.x * 4.2 - p.y * 3.4 + ocean_time * 1.75) * 0.35;
    float foam_motion = smoothstep(-0.30, 0.65, foam_pattern + swell_crest * 3.0);
    // Shallow breakwater and wave crests only, no detached foam rectangles.
    float crest_foam = smoothstep(0.085, 0.14, swell_crest)
        * (0.12 + 0.12 * shallow_factor);
    float foam = clamp((contact * foam_motion + crest_foam)
        * foam_amount, 0.0, 0.68);

    vec3 sea = mix(water_deep.rgb, water_shallow.rgb, shallow_factor);
    // Sparse moving luminance detail rather than the prior full-width stripes.
    sea += vec3((micro_a + micro_b) * 0.006 * ripple_detail);
    // View-angle response increases bright grazing reflections without
    // injecting a hard-white unshaded highlight or a mobile screen pass.
    float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
    float fresnel = pow(1.0 - facing, 5.0);
    sea = mix(sea, vec3(0.15, 0.35, 0.45), fresnel * 0.36);
    ALBEDO = mix(sea, foam_tint.rgb, foam);
    ROUGHNESS = mix(0.155, 0.68, foam);
    METALLIC = 0.0;
    SPECULAR = 0.86;
}
