shader_type spatial;
render_mode depth_draw_opaque, specular_schlick_ggx, diffuse_burley;

// Optional stylized lighting variant. Production art acceptance is separate.
uniform vec4 base_color : source_color = vec4(1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.05;
uniform float roughness : hint_range(0.02, 1.0) = 0.6;
uniform bool use_albedo_texture = false;
uniform bool use_normal_texture = false;
uniform bool use_roughness_texture = false;
uniform bool use_triplanar = false;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float triplanar_scale : hint_range(0.01, 10.0) = 1.0;
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 4.0;
uniform float toon_ramp_smoothness : hint_range(0.01, 0.2) = 0.05;
uniform vec4 rim_color : source_color = vec4(1.0, 0.9, 0.7, 1.0);
uniform float rim_thickness : hint_range(0.0, 1.0) = 0.35;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.2;

varying vec3 local_position;
varying vec3 local_normal;

void vertex() {
    local_position = VERTEX;
    local_normal = NORMAL;
}

vec3 projection_weights(vec3 n) {
    vec3 weights = pow(abs(normalize(n)), vec3(triplanar_sharpness));
    return weights / max(weights.x + weights.y + weights.z, 0.0001);
}

vec4 sample_triplanar(sampler2D tex, vec3 p, vec3 n) {
    vec3 w = projection_weights(n);
    vec3 uvw = p * triplanar_scale;
    return texture(tex, uvw.yz) * w.x
         + texture(tex, uvw.xz) * w.y
         + texture(tex, uvw.xy) * w.z;
}

void fragment() {
    vec4 albedo_sample = vec4(1.0);
    if (use_albedo_texture) {
        albedo_sample = use_triplanar
            ? sample_triplanar(albedo_texture, local_position, local_normal)
            : texture(albedo_texture, UV);
    }
    ALBEDO = base_color.rgb * albedo_sample.rgb;
    ALPHA = base_color.a * albedo_sample.a;
    METALLIC = metallic;
    ROUGHNESS = roughness;
    if (use_roughness_texture) {
        ROUGHNESS *= use_triplanar
            ? sample_triplanar(roughness_texture, local_position, local_normal).r
            : texture(roughness_texture, UV).r;
    }
    if (use_normal_texture) {
        // A tangent-space normal requires UV tangent data. Triplanar meshes without
        // tangents use their geometric normal rather than an invalid tangent basis.
        if (!use_triplanar) {
            NORMAL_MAP = texture(normal_texture, UV).rgb;
            NORMAL_MAP_DEPTH = 1.0;
        }
    }
}

void light() {
    float ndotl = max(dot(NORMAL, LIGHT), 0.0);
    float s = toon_ramp_smoothness;
    float band = (smoothstep(0.0, s, ndotl)
                + smoothstep(0.4, 0.4 + s, ndotl)
                + smoothstep(0.75, 0.75 + s, ndotl)) / 3.0;
    float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
    float rim = smoothstep(1.0 - rim_thickness, 1.0, 1.0 - ndotv) * ndotl;
    DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * band * ATTENUATION;
    DIFFUSE_LIGHT += rim_color.rgb * rim * rim_strength * LIGHT_COLOR * ATTENUATION;
    // Keep physically based specular rather than replacing the entire response
    // with unlit toon shading.
    SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION
        * pow(max(dot(reflect(-LIGHT, NORMAL), VIEW), 0.0), mix(8.0, 128.0, 1.0 - ROUGHNESS))
        * (0.04 + METALLIC * 0.96);
}
