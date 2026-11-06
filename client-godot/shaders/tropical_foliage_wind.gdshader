shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Bounded, local-space movement: roots stay planted and MultiMesh batching survives.
// First-party vertex-colour foliage, no additional textures or draw calls.
uniform float canopy_height : hint_range(0.1, 5.0) = 3.4;
uniform float wind_strength : hint_range(0.0, 0.2) = 0.12;
uniform float wind_rate : hint_range(0.1, 4.0) = 1.3;
// -1: actual gameplay time. >=0: exact fixed-step in-engine capture time.
// Avoid process-local TIME discontinuities across independent capture workers.
uniform float capture_time_seconds = -1.0;

void vertex() {
    float height_factor = smoothstep(0.0, canopy_height, max(VERTEX.y, 0.0));
    float bend = height_factor * height_factor;
    float seed = dot(MODEL_MATRIX[3].xz, vec2(0.39, 0.61));
    float phase = seed + dot(VERTEX.xz, vec2(0.41, 0.23));
    float animation_time = capture_time_seconds >= 0.0 ? capture_time_seconds : TIME;
    float broad = sin(animation_time * wind_rate + phase);
    float gust = sin(animation_time * wind_rate * 0.47 + phase * 0.67);
    VERTEX.xz += vec2(0.83, 0.56) * (broad * 0.75 + gust * 0.25) * wind_strength * bend;
}

void fragment() {
    ALBEDO = COLOR.rgb;
    METALLIC = 0.0;
    ROUGHNESS = 0.86;
    SPECULAR = 0.3;
}
