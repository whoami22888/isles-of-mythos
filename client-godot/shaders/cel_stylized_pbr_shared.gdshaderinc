// Shared cel-stylized PBR implementation.
// The desktop entrypoint uses the per-light path below. The mobile entrypoint
// defines IOM_CEL_MOBILE_VERTEX_RAMP and uses the fragment albedo ramp because
// Godot's Force Vertex Shading skips light() on mobile.
uniform sampler2D albedo_texture : source_color, hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap, repeat_enable;

uniform vec4 base_color : source_color = vec4(1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.05;
uniform float roughness : hint_range(0.02, 1.0) = 0.6;
uniform float specular_amount : hint_range(0.0, 1.0) = 0.5;

uniform bool use_albedo_texture = false;
uniform bool use_normal_texture = false;
uniform bool use_roughness_texture = false;
uniform bool use_triplanar = false;
uniform float triplanar_scale : hint_range(0.01, 10.0) = 1.0;
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 4.0;

uniform float toon_ramp_smoothness : hint_range(0.01, 0.2) = 0.05;
uniform vec4 toon_shadow_tint : source_color = vec4(0.48, 0.54, 0.66, 1.0);
uniform vec4 toon_mid_tint : source_color = vec4(0.88, 0.86, 0.76, 1.0);
uniform vec4 toon_highlight_tint : source_color = vec4(1.0, 0.98, 0.90, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.9, 0.7, 1.0);
uniform float rim_thickness : hint_range(0.0, 1.0) = 0.35;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.2;
uniform float rim_tint : hint_range(0.0, 1.0) = 0.35;

#ifdef IOM_CEL_MOBILE_VERTEX_RAMP
// World-space direction from the shaded surface toward the primary key light.
// Keep this uniform synchronized with the scene's key DirectionalLight3D.
uniform vec3 mobile_key_light_direction = vec3(0.35, 0.82, 0.45);
uniform vec3 mobile_key_light_color = vec3(1.0);
uniform float mobile_ramp_strength : hint_range(0.0, 1.0) = 1.0;
#endif

varying vec3 triplanar_world_position;
varying vec3 triplanar_world_normal;
varying float vertex_rim_factor;

void vertex() {
    triplanar_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    triplanar_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);

    vec3 world_view_delta = CAMERA_POSITION_WORLD - triplanar_world_position;
    vec3 world_view = world_view_delta / max(length(world_view_delta), 0.0001);
    float vertex_n_dot_v = clamp(dot(triplanar_world_normal, world_view), 0.0, 1.0);
    float rim_width = max(rim_thickness, 0.001);
    vertex_rim_factor = smoothstep(1.0 - rim_width, 1.0, 1.0 - vertex_n_dot_v);
}

vec3 projection_weights(vec3 n) {
    vec3 weights = pow(abs(normalize(n)), vec3(triplanar_sharpness));
    return weights / max(weights.x + weights.y + weights.z, 0.0001);
}

vec3 projection_face_signs(vec3 n) {
    return mix(vec3(-1.0), vec3(1.0), step(vec3(0.0), normalize(n)));
}

// Keep the signed UV bitangents identical for albedo, normal and roughness
// projections. This prevents opposite faces from mirroring texture detail
// relative to the reconstructed tangent-space normal map.
vec4 sample_triplanar(sampler2D tex, vec3 p, vec3 n) {
    vec3 w = projection_weights(n);
    vec3 face = projection_face_signs(n);
    vec3 uvw = p * triplanar_scale;
    vec2 uv_x = vec2(uvw.y, uvw.z * face.x);
    vec2 uv_y = vec2(uvw.x, -uvw.z * face.y);
    vec2 uv_z = vec2(uvw.x, uvw.y * face.z);
    return texture(tex, uv_x) * w.x
         + texture(tex, uv_y) * w.y
         + texture(tex, uv_z) * w.z;
}

// Reorient each tangent-space projection into world space. Blend only the
// perturbation from each projection's flat normal so oblique flat surfaces
// retain their original world-space geometric normal instead of snapping to an axis.
vec3 sample_triplanar_normal(vec3 p, vec3 world_geometric_normal) {
    vec3 n = normalize(world_geometric_normal);
    vec3 w = projection_weights(n);
    vec3 uvw = p * triplanar_scale;
    vec3 face = projection_face_signs(n);
    vec2 uv_x = vec2(uvw.y, uvw.z * face.x);
    vec2 uv_y = vec2(uvw.x, -uvw.z * face.y);
    vec2 uv_z = vec2(uvw.x, uvw.y * face.z);
    vec3 nx = texture(normal_texture, uv_x).xyz * 2.0 - 1.0;
    vec3 ny = texture(normal_texture, uv_y).xyz * 2.0 - 1.0;
    vec3 nz = texture(normal_texture, uv_z).xyz * 2.0 - 1.0;
    // Preserve each projection's UV tangent-frame handedness on both face signs.
    // U stays fixed; the face sign flips the bitangent so normal maps do not mirror.
    vec3 tx = vec3(nx.z * face.x, nx.x, nx.y * face.x);
    vec3 ty = vec3(ny.x, ny.z * face.y, -ny.y * face.y);
    vec3 tz = vec3(nz.x, nz.y * face.z, nz.z * face.z);
    vec3 flat_x = vec3(face.x, 0.0, 0.0);
    vec3 flat_y = vec3(0.0, face.y, 0.0);
    vec3 flat_z = vec3(0.0, 0.0, face.z);
    vec3 perturbation = (tx - flat_x) * w.x
                      + (ty - flat_y) * w.y
                      + (tz - flat_z) * w.z;
    return normalize(n + perturbation);
}

void fragment() {
    vec4 albedo_sample = vec4(1.0);
    if (use_albedo_texture) {
        albedo_sample = use_triplanar
            ? sample_triplanar(albedo_texture, triplanar_world_position, triplanar_world_normal)
            : texture(albedo_texture, UV);
    }
    ALBEDO = base_color.rgb * albedo_sample.rgb;
    METALLIC = metallic;
    ROUGHNESS = roughness;
    SPECULAR = specular_amount;

    // Retain the sampled UV normal for the mobile custom ramp. Godot's
    // NORMAL_MAP output is consumed later by built-in shading; it does not
    // rewrite NORMAL before this fragment-space ramp is evaluated.
    vec3 mobile_uv_tangent_normal = vec3(0.0, 0.0, 1.0);

    if (use_roughness_texture) {
        ROUGHNESS *= use_triplanar
            ? sample_triplanar(roughness_texture, triplanar_world_position, triplanar_world_normal).r
            : texture(roughness_texture, UV).r;
    }

    if (use_normal_texture) {
        if (use_triplanar) {
            vec3 world_normal = sample_triplanar_normal(triplanar_world_position, triplanar_world_normal);
            NORMAL = normalize(mat3(VIEW_MATRIX) * world_normal);
        } else {
            vec3 uv_normal_sample = texture(normal_texture, UV).rgb;
            NORMAL_MAP = uv_normal_sample;
            NORMAL_MAP_DEPTH = 1.0;
            vec3 decoded_uv_normal = uv_normal_sample * 2.0 - 1.0;
            float decoded_uv_normal_length = length(decoded_uv_normal);
            mobile_uv_tangent_normal = decoded_uv_normal_length > 0.0001
                ? decoded_uv_normal / decoded_uv_normal_length
                : vec3(0.0, 0.0, 1.0);
        }
    }

#ifdef IOM_CEL_MOBILE_VERTEX_RAMP
    // This material variant explicitly uses vertex_lighting, so light() is
    // skipped even in desktop CI. Recreate the same three palette bands in
    // fragment() and tint ALBEDO before Godot applies its vertex-based PBR light.
    vec3 mobile_view_normal = normalize(NORMAL);
    if (use_normal_texture && !use_triplanar) {
        float tangent_length = length(TANGENT);
        float bitangent_length = length(BINORMAL);
        if (tangent_length > 0.0001 && bitangent_length > 0.0001) {
            vec3 tangent = TANGENT / tangent_length;
            vec3 bitangent = BINORMAL / bitangent_length;
            mobile_view_normal = normalize(
                tangent * mobile_uv_tangent_normal.x
                + bitangent * mobile_uv_tangent_normal.y
                + mobile_view_normal * mobile_uv_tangent_normal.z
            );
        }
    }
    vec3 mobile_world_normal = normalize(mat3(INV_VIEW_MATRIX) * mobile_view_normal);
    vec3 mobile_light_direction = normalize(mobile_key_light_direction);
    float mobile_n_dot_l = max(dot(mobile_world_normal, mobile_light_direction), 0.0);
    float mobile_softness = max(toon_ramp_smoothness, 0.001);
    float mobile_mid_band = smoothstep(
        0.4 - mobile_softness,
        0.4 + mobile_softness,
        mobile_n_dot_l
    );
    float mobile_high_band = smoothstep(
        0.75 - mobile_softness,
        0.75 + mobile_softness,
        mobile_n_dot_l
    );
    vec3 mobile_ramp = mix(toon_shadow_tint.rgb, toon_mid_tint.rgb, mobile_mid_band);
    mobile_ramp = mix(mobile_ramp, toon_highlight_tint.rgb, mobile_high_band);
    vec3 mobile_tint = mobile_ramp * mobile_key_light_color;
    ALBEDO *= mix(vec3(1.0), mobile_tint, clamp(mobile_ramp_strength, 0.0, 1.0));

    // Built-in rim fallback is mobile-only; desktop already adds its rim in light().
    RIM = clamp(vertex_rim_factor, 0.0, 1.0) * rim_strength;
    RIM_TINT = rim_tint;
#endif
}

void light() {
    float n_dot_l = dot(NORMAL, LIGHT);
    // Godot's light() processor forbids return; gate every direct-light term.
    if (n_dot_l > 0.0) {
        float n_dot_v = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
        float softness = max(toon_ramp_smoothness, 0.001);
        float mid_band = smoothstep(0.4 - softness, 0.4 + softness, n_dot_l);
        float high_band = smoothstep(0.75 - softness, 0.75 + softness, n_dot_l);
        vec3 ramp = mix(toon_shadow_tint.rgb, toon_mid_tint.rgb, mid_band);
        ramp = mix(ramp, toon_highlight_tint.rgb, high_band);
        DIFFUSE_LIGHT += ALBEDO * ramp * LIGHT_COLOR * ATTENUATION / PI;

        float rim_width = max(rim_thickness, 0.001);
        float fragment_rim = smoothstep(1.0 - rim_width, 1.0, 1.0 - n_dot_v)
            * smoothstep(0.0, 0.15, n_dot_l);
        float vertex_rim = clamp(vertex_rim_factor, 0.0, 1.0)
            * smoothstep(0.0, 0.15, n_dot_l);
        float rim_intensity = max(fragment_rim, vertex_rim * 0.5) * rim_strength;
        DIFFUSE_LIGHT += rim_color.rgb * rim_intensity * LIGHT_COLOR * ATTENUATION;

        float surface_roughness = clamp(ROUGHNESS, 0.04, 1.0);
        float specular_power = mix(128.0, 4.0, surface_roughness);
        // SPECULAR_AMOUNT already reflects the fragment SPECULAR output; apply it once.
        float specular_lobe = pow(max(dot(reflect(-LIGHT, NORMAL), VIEW), 0.0), specular_power)
            * (1.0 - surface_roughness) * SPECULAR_AMOUNT;
        vec3 f0 = mix(vec3(0.04), ALBEDO, METALLIC);
        SPECULAR_LIGHT += f0 * LIGHT_COLOR * ATTENUATION * specular_lobe;
    }
}
