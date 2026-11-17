shader_type spatial;
render_mode cull_back, diffuse_toon, specular_toon;

// Prompt 005 optional material scaffold.
// This shader is not assigned to production scenes and is NOT premium visual
// acceptance. Capture and compare on the Galaxy S23 Ultra before any use.
// The custom three-stop light ramp requires per-pixel lighting; Godot's mobile
// force-vertex-shading setting may skip light(), in which case the renderer's
// built-in toon fallback applies. Do not change the project renderer to enable it.

uniform vec4 base_color : source_color = vec4(0.72, 0.68, 0.58, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float roughness : hint_range(0.04, 1.0) = 0.82;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.5;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_texture : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_albedo_texture = false;
uniform bool use_normal_texture = false;
uniform bool use_roughness_texture = false;

uniform float triplanar_scale : hint_range(0.05, 32.0, 0.05) = 1.0;
uniform float triplanar_blend_sharpness : hint_range(1.0, 16.0, 0.5) = 4.0;

uniform vec4 toon_shadow_tint : source_color = vec4(0.48, 0.54, 0.66, 1.0);
uniform vec4 toon_mid_tint : source_color = vec4(0.88, 0.86, 0.76, 1.0);
uniform vec4 toon_highlight_tint : source_color = vec4(1.0, 0.98, 0.90, 1.0);
uniform float toon_mid_threshold : hint_range(0.05, 0.95) = 0.34;
uniform float toon_high_threshold : hint_range(0.10, 1.0) = 0.72;
uniform float toon_softness : hint_range(0.001, 0.15) = 0.025;

uniform float rim_strength : hint_range(0.0, 1.0) = 0.18;
uniform float rim_tint : hint_range(0.0, 1.0) = 0.35;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
    vec3 weights = pow(abs(world_normal), vec3(max(triplanar_blend_sharpness, 1.0)));
    weights /= max(weights.x + weights.y + weights.z, 0.0001);

    float projection_scale = max(triplanar_scale, 0.001);
    vec2 uv_x = world_position.zy * projection_scale;
    vec2 uv_y = world_position.xz * projection_scale;
    vec2 uv_z = world_position.xy * projection_scale;

    if (use_albedo_texture) {
        vec3 albedo_x = texture(albedo_texture, uv_x).rgb;
        vec3 albedo_y = texture(albedo_texture, uv_y).rgb;
        vec3 albedo_z = texture(albedo_texture, uv_z).rgb;
        vec3 triplanar_albedo = albedo_x * weights.x
            + albedo_y * weights.y
            + albedo_z * weights.z;
        ALBEDO = base_color.rgb * triplanar_albedo;
    } else {
        ALBEDO = base_color.rgb;
    }

    if (use_normal_texture) {
        vec3 sampled_x = texture(normal_texture, uv_x).xyz * 2.0 - 1.0;
        vec3 sampled_y = texture(normal_texture, uv_y).xyz * 2.0 - 1.0;
        vec3 sampled_z = texture(normal_texture, uv_z).xyz * 2.0 - 1.0;

        float sign_x = world_normal.x < 0.0 ? -1.0 : 1.0;
        float sign_y = world_normal.y < 0.0 ? -1.0 : 1.0;
        float sign_z = world_normal.z < 0.0 ? -1.0 : 1.0;

        vec3 normal_x_world = vec3(
            sampled_x.z * sign_x, sampled_x.y, sampled_x.x * sign_x
        );
        vec3 normal_y_world = vec3(
            sampled_y.x * sign_y, sampled_y.z, sampled_y.y * sign_y
        );
        vec3 normal_z_world = vec3(
            sampled_z.x * sign_z, sampled_z.y, sampled_z.z * sign_z
        );
        vec3 blended_world_normal = normalize(
            normal_x_world * weights.x
            + normal_y_world * weights.y
            + normal_z_world * weights.z
        );
        NORMAL = normalize((VIEW_MATRIX * vec4(blended_world_normal, 0.0)).xyz);
    }

    float mapped_roughness = roughness;
    if (use_roughness_texture) {
        float rough_x = texture(roughness_texture, uv_x).r;
        float rough_y = texture(roughness_texture, uv_y).r;
        float rough_z = texture(roughness_texture, uv_z).r;
        float triplanar_roughness = rough_x * weights.x
            + rough_y * weights.y
            + rough_z * weights.z;
        mapped_roughness *= triplanar_roughness;
    }

    METALLIC = metallic;
    ROUGHNESS = clamp(mapped_roughness, 0.04, 1.0);
    SPECULAR = specular_amount;
    RIM = rim_strength;
    RIM_TINT = rim_tint;
}

void light() {
    float mid_threshold = clamp(toon_mid_threshold, 0.01, 0.98);
    float high_threshold = max(toon_high_threshold, mid_threshold + 0.01);
    float softness = max(toon_softness, 0.001);
    float n_dot_l = max(dot(NORMAL, LIGHT), 0.0);

    float mid_band = smoothstep(
        mid_threshold - softness, mid_threshold + softness, n_dot_l
    );
    float high_band = smoothstep(
        high_threshold - softness, high_threshold + softness, n_dot_l
    );
    vec3 ramp = mix(toon_shadow_tint.rgb, toon_mid_tint.rgb, mid_band);
    ramp = mix(ramp, toon_highlight_tint.rgb, high_band);

    // Three-stop diffuse ramp, with a restrained Schlick-like specular lobe.
    DIFFUSE_LIGHT += ALBEDO * ramp * LIGHT_COLOR * ATTENUATION / PI;

    vec3 half_vector = normalize(LIGHT + VIEW);
    float n_dot_h = max(dot(NORMAL, half_vector), 0.0);
    float surface_roughness = clamp(ROUGHNESS, 0.04, 1.0);
    float specular_power = mix(128.0, 4.0, surface_roughness);
    float specular_lobe = pow(n_dot_h, specular_power)
        * (1.0 - surface_roughness) * specular_amount * SPECULAR_AMOUNT;
    vec3 f0 = mix(vec3(0.04) * specular_amount, ALBEDO, METALLIC);
    SPECULAR_LIGHT += f0 * LIGHT_COLOR * ATTENUATION * specular_lobe;
}
