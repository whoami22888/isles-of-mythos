shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

#include "res://shaders/coastal_ocean_wave.gdshaderinc"

// An independently animated, physically lit foam ribbon.
// World-anchored wake history follows vessel motion; this shader only adds
// sub-surface swell tracking and small-scale foam breakup. No gameplay state.
uniform vec4 foam_color : source_color = vec4(0.86, 0.95, 0.91, 1.0);
uniform vec4 subsurface_color : source_color = vec4(0.19, 0.56, 0.61, 1.0);
uniform float foam_density : hint_range(0.0, 1.0) = 0.83;
uniform float swell_scale : hint_range(0.0, 1.5) = 0.65;
uniform float wave_speed = 1.45;
uniform float wave_amplitude = 0.65;
uniform float wave_frequency = 0.18;
uniform vec2 wave_direction_a = vec2(0.84, 0.54);
uniform vec2 wave_direction_b = vec2(-0.43, 0.90);
uniform float wave_steepness_a = 0.68;
uniform float wave_steepness_b = 0.52;
uniform vec2 near_patch_half_extent = vec2(92.0, 70.0);
uniform bool deterministic_capture = false;
uniform float capture_time_seconds = 0.0;

float hash21(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float smooth_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 w = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash21(i), hash21(i + vec2(1.0, 0.0)), w.x),
        mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), w.x),
        w.y
    );
}

void vertex() {
    vec3 p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float ocean_time = deterministic_capture ? capture_time_seconds : TIME;
    float envelope = coastal_ocean_wave_envelope(p.xz, near_patch_half_extent);
    vec3 displacement = coastal_ocean_wave_displacement(
        p.xz,
        ocean_time,
        wave_speed,
        wave_amplitude,
        wave_frequency,
        wave_steepness_a,
        wave_steepness_b,
        swell_scale,
        wave_direction_a,
        wave_direction_b
    );
    VERTEX += transpose(MODEL_NORMAL_MATRIX) * displacement * envelope;
}

void fragment() {
    float ocean_time = deterministic_capture ? capture_time_seconds : TIME;
    // Both strip edges fade continuously; no hard rectangles or flat white bars.
    float bank = pow(max(0.0, sin(UV.x * 3.14159265)), 0.8);
    float flow = UV.y * 17.0 - ocean_time * 1.25;
    vec2 sample_uv = vec2(UV.x * 5.0 + flow * 0.12, flow);
    float broad = smooth_noise(sample_uv * vec2(2.2, 1.3));
    float detail = smooth_noise(sample_uv * vec2(7.0, 3.8));
    float bubbles = smoothstep(0.34, 0.82, broad * 0.63 + detail * 0.37);
    float fractured = smoothstep(0.24, 0.72, broad + detail * 0.26);
    float mask = mix(fractured, bubbles, 0.55) * bank * COLOR.a * foam_density;
    ALBEDO = mix(subsurface_color.rgb, foam_color.rgb, clamp(bubbles * 1.3, 0.0, 1.0));
    ROUGHNESS = mix(0.32, 0.75, bubbles);
    SPECULAR = 0.45;
    METALLIC = 0.0;
    ALPHA = clamp(mask, 0.0, 0.80);
}
