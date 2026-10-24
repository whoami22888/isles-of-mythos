shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// A bounded mobile GPU spray material: shaped droplets rather than flat
// white rectangles. COLOR.a is supplied by the particle's lifetime curve.
uniform vec4 spray_core : source_color = vec4(0.88, 0.97, 0.94, 1.0);
uniform vec4 spray_edge : source_color = vec4(0.26, 0.64, 0.68, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.83;

void fragment() {
    vec2 p = UV * 2.0 - 1.0;
    float radial = length(vec2(p.x * 1.9, p.y));
    float droplet = 1.0 - smoothstep(0.46, 1.0, radial);
    float filament = 1.0 - smoothstep(0.10, 0.62, abs(p.x));
    float breakup = 0.82 + 0.18 * sin(p.y * 12.0 + p.x * 7.5);
    float mask = max(0.0, droplet * filament * breakup);
    ALBEDO = mix(spray_edge.rgb, spray_core.rgb, clamp(mask * 1.4, 0.0, 1.0));
    ALPHA = clamp(mask * opacity * COLOR.a, 0.0, 0.88);
}
