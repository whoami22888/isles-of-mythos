// Shared analytic displacement contract for the opaque ocean and its foam ribbons.
// Keep the constants and phase equations identical to ocean_surface.gdshader.
vec3 coastal_ocean_wave_displacement(
    vec2 world_xz,
    float ocean_time,
    float wave_speed,
    float wave_amplitude,
    float wave_frequency,
    float wave_steepness_a,
    float wave_steepness_b,
    float swell_scale,
    vec2 wave_direction_a,
    vec2 wave_direction_b
) {
    vec2 direction_a = length(wave_direction_a) > 0.001
        ? normalize(wave_direction_a) : vec2(1.0, 0.0);
    vec2 direction_b = length(wave_direction_b) > 0.001
        ? normalize(wave_direction_b) : vec2(0.0, 1.0);
    float wave_k_a = max(wave_frequency, 0.05);
    float wave_k_b = wave_k_a * 1.55;
    float safe_wave_speed = max(wave_speed, 0.0);
    float wave_phase_a = dot(world_xz, direction_a) * wave_k_a - ocean_time * safe_wave_speed;
    float wave_phase_b = dot(world_xz, direction_b) * wave_k_b
        - ocean_time * safe_wave_speed * sqrt(wave_k_b / wave_k_a);
    float amplitude = max(wave_amplitude, 0.0);
    float amplitude_a = amplitude * 0.65;
    float amplitude_b = amplitude * 0.35;
    float horizontal_a = amplitude_a * clamp(wave_steepness_a, 0.0, 1.0);
    float horizontal_b = amplitude_b * clamp(wave_steepness_b, 0.0, 1.0);
    float sin_a = sin(wave_phase_a);
    float cos_a = cos(wave_phase_a);
    float sin_b = sin(wave_phase_b);
    float cos_b = cos(wave_phase_b);
    vec2 horizontal_displacement = direction_a * horizontal_a * cos_a
        + direction_b * horizontal_b * cos_b;
    float vertical_displacement = amplitude_a * sin_a + amplitude_b * sin_b;

    // Legacy fine swell retained by the production ocean shader.
    float a = dot(world_xz, vec2(0.84, 0.54)) * 0.55 - ocean_time * 0.90;
    float b = dot(world_xz, vec2(-0.43, 0.90)) * 1.16 - ocean_time * 1.35;
    float c = dot(world_xz, vec2(0.95, -0.31)) * 2.25 - ocean_time * 1.90;
    float legacy_displacement = (
        sin(a) * 0.090 + sin(b) * 0.044 + sin(c) * 0.015
    ) * swell_scale;

    return vec3(
        horizontal_displacement.x,
        vertical_displacement + legacy_displacement,
        horizontal_displacement.y
    );
}

float coastal_ocean_wave_envelope(vec2 world_xz, vec2 near_patch_half_extent) {
    float fade_x = 1.0 - smoothstep(
        near_patch_half_extent.x - 18.0,
        near_patch_half_extent.x - 1.0,
        abs(world_xz.x)
    );
    float fade_z = 1.0 - smoothstep(
        near_patch_half_extent.y - 18.0,
        near_patch_half_extent.y - 1.0,
        abs(world_xz.y)
    );
    return fade_x * fade_z;
}
