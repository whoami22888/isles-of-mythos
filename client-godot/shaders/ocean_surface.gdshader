shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Animated 3-scale swell with analytic vertex normals. This material is opaque
// on purpose: it retains early depth writes and mobile forward rendering.
// Surface quality must still be checked against actual Godot footage.
uniform vec4 water_shallow : source_color = vec4(0.035, 0.34, 0.44, 1.0);
uniform vec4 water_deep : source_color = vec4(0.009, 0.07, 0.15, 1.0);
uniform vec4 foam_tint : source_color = vec4(0.76, 0.91, 0.91, 1.0);
uniform float swell_scale : hint_range(0.0, 1.5) = 1.0;
uniform float ripple_detail : hint_range(0.0, 1.0) = 0.9;
uniform float foam_amount : hint_range(0.0, 1.0) = 0.7;

#include "res://shaders/coastal_shore_sampler.gdshaderinc"

const float SEA_LEVEL = -0.35;
varying vec3 surface_world;
varying float swell_crest;

void vertex() {
    vec2 xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
    float a = dot(xz, vec2(0.84, 0.54)) * 0.55 - TIME * 0.90;
    float b = dot(xz, vec2(-0.43, 0.90)) * 1.16 - TIME * 1.35;
    float c = dot(xz, vec2(0.95, -0.31)) * 2.25 - TIME * 1.90;
    float displacement = (sin(a) * 0.090 + sin(b) * 0.044 + sin(c) * 0.015) * swell_scale;
    float dx = (cos(a) * 0.090 * 0.55 * 0.84
              + cos(b) * 0.044 * 1.16 * -0.43
              + cos(c) * 0.015 * 2.25 * 0.95) * swell_scale;
    float dz = (cos(a) * 0.090 * 0.55 * 0.54
              + cos(b) * 0.044 * 1.16 * 0.90
              + cos(c) * 0.015 * 2.25 * -0.31) * swell_scale;
    VERTEX.y += displacement;
    NORMAL = normalize(vec3(-dx, 1.0, -dz));
    surface_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    swell_crest = displacement;
}

void fragment() {
    vec2 p = surface_world.xz;
    float coverage = shore_terrain_coverage(p);
    float floor_y = shore_terrain_height(p);
    // Open water outside the mesh is deep; never extend edge texels as shore.
    float depth_m = mix(8.5, max(0.0, SEA_LEVEL - floor_y), coverage);
    float shallow_factor = 1.0 - smoothstep(0.15, 8.5, depth_m);
    float contact = coverage *
        (1.0 - smoothstep(0.025, 0.24, abs(SEA_LEVEL - floor_y)));

    // Two counter-moving normal frequencies animate highlights on the water.
    // No screen-space reflection pass or full-screen postprocess is required.
    float micro_a = sin(dot(p, vec2(3.1, 1.55)) - TIME * 2.35);
    float micro_b = cos(dot(p, vec2(-1.92, 3.38)) + TIME * 1.68);
    NORMAL_MAP = normalize(vec3(
        (micro_a * 0.12 + micro_b * 0.055) * ripple_detail,
        (micro_a * -0.085 + micro_b * 0.11) * ripple_detail,
        1.0
    ));

    // Break up the coastal foam so it moves without straight bright strips.
    float foam_pattern = sin(p.x * 2.0 + TIME * 1.2)
                       * cos(p.y * 2.8 - TIME * 0.85);
    foam_pattern += sin(p.x * 4.2 - p.y * 3.4 + TIME * 1.75) * 0.35;
    float foam_motion = smoothstep(-0.30, 0.65, foam_pattern + swell_crest * 3.0);
    float foam = clamp(contact * foam_motion * foam_amount, 0.0, 0.85);

    vec3 sea = mix(water_deep.rgb, water_shallow.rgb, shallow_factor);
    // Sparse moving luminance detail rather than the prior full-width stripes.
    sea += vec3((micro_a + micro_b) * 0.006 * ripple_detail);
    ALBEDO = mix(sea, foam_tint.rgb, foam);
    ROUGHNESS = mix(0.155, 0.68, foam);
    METALLIC = 0.0;
    SPECULAR = 0.86;
}
