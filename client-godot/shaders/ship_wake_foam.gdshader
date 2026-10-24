shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// An independently animated, physically lit foam ribbon.
// World-anchored wake history follows vessel motion; this shader only adds
// sub-surface swell tracking and small-scale foam breakup. No gameplay state.
uniform vec4 foam_color : source_color = vec4(0.86, 0.95, 0.91, 1.0);
uniform vec4 subsurface_color : source_color = vec4(0.19, 0.56, 0.61, 1.0);
uniform float foam_density : hint_range(0.0, 1.0) = 0.83;
uniform float swell_scale : hint_range(0.0, 1.5) = 1.0;

float wave_height(vec2 p) {
    float a = dot(p, vec2(0.84, 0.54)) * 0.55 - TIME * 0.90;
    float b = dot(p, vec2(-0.43, 0.90)) * 1.16 - TIME * 1.35;
    float c = dot(p, vec2(0.95, -0.31)) * 2.25 - TIME * 1.90;
    return (sin(a) * 0.090 + sin(b) * 0.044 + sin(c) * 0.015) * swell_scale;
}

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
    VERTEX.y += wave_height(p.xz);
}

void fragment() {
    // Both strip edges fade continuously; no hard rectangles or flat white bars.
    float bank = pow(max(0.0, sin(UV.x * 3.14159265)), 0.8);
    float flow = UV.y * 17.0 - TIME * 1.25;
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
