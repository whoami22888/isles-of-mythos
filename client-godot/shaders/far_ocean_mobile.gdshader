shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Cheap distant water behind the terrain-aware near patch. Four vertices,
// animated lit micro-normals, and NO terrain texture lookups or wave mesh work.
// Same deep-water palette as the near shader at its faded mesh boundary.
uniform vec4 far_deep_color : source_color = vec4(0.009, 0.07, 0.15, 1.0);
varying vec2 ocean_world_xz;

void vertex() {
    ocean_world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
    float wave_a = sin(dot(ocean_world_xz, vec2(2.05, 1.24)) - TIME * 1.15);
    float wave_b = cos(dot(ocean_world_xz, vec2(-1.37, 2.76)) + TIME * 1.62);
    NORMAL_MAP = normalize(vec3(
        (wave_a * 0.09 + wave_b * 0.055),
        (wave_a * -0.06 + wave_b * 0.09),
        1.0
    ));
    ALBEDO = far_deep_color.rgb + vec3((wave_a + wave_b) * 0.002);
    ROUGHNESS = 0.23;
    SPECULAR = 0.78;
    METALLIC = 0.0;
}
