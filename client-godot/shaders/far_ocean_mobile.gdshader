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
    // Match near-ocean ripples and grazing-angle radiance EXACTLY at the
    // mesh seam. The preceding hard teal/dark split came from a missing
    // Fresnel term in the lighter far material, not from wave geometry.
    float wave_a = sin(dot(ocean_world_xz, vec2(3.1, 1.55)) - TIME * 2.35);
    float wave_b = cos(dot(ocean_world_xz, vec2(-1.92, 3.38)) + TIME * 1.68);
    NORMAL_MAP = normalize(vec3(
        (wave_a * 0.12 + wave_b * 0.055) * 0.9,
        (wave_a * -0.085 + wave_b * 0.11) * 0.9,
        1.0
    ));
    float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
    float fresnel = pow(1.0 - facing, 5.0);
    vec3 sea = far_deep_color.rgb + vec3((wave_a + wave_b) * 0.006 * 0.9);
    ALBEDO = mix(sea, vec3(0.15, 0.35, 0.45), fresnel * 0.36);
    ROUGHNESS = 0.155;
    SPECULAR = 0.78;
    METALLIC = 0.0;
}
