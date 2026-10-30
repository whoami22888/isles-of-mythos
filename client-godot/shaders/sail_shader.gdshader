shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// The imported ship's RGBA atlas supplies sail cutout opacity.
// Keep texture alpha-scissored; do not turn the cloth into blended glass.
uniform sampler2D base_sail_tex : source_color, filter_linear_mipmap;
uniform sampler2D order_cross_emblem : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 base_tint : source_color = vec4(1.0);
uniform vec4 cross_color : source_color = vec4(0.8, 0.1, 0.1, 1.0);
uniform float alpha_scissor_threshold : hint_range(0.01, 0.99) = 0.5;

// Preserve admitted ship material maps instead of replacing them with flat art.
uniform float sail_roughness : hint_range(0.0, 1.0) = 0.85;
uniform float sail_metallic : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D sail_normal_tex : hint_normal, filter_linear_mipmap;
uniform bool has_normal_map = false;
uniform float sail_normal_depth : hint_range(0.0, 2.0) = 1.0;
uniform sampler2D sail_roughness_tex : hint_default_white, filter_linear_mipmap;
uniform bool has_roughness_map = false;
uniform int roughness_channel = 1;
uniform sampler2D sail_metallic_tex : hint_default_white, filter_linear_mipmap;
uniform bool has_metallic_map = false;
uniform int metallic_channel = 2;
uniform sampler2D sail_ao_tex : hint_default_white, filter_linear_mipmap;
uniform bool has_ao_map = false;
uniform int ao_channel = 0;

float channel_value(vec4 texel, int channel) {
    if (channel == 1) { return texel.g; }
    if (channel == 2) { return texel.b; }
    if (channel == 3) { return texel.a; }
    if (channel == 4) { return dot(texel.rgb, vec3(0.2126, 0.7152, 0.0722)); }
    return texel.r;
}

void fragment() {
    vec4 base_col = texture(base_sail_tex, UV) * base_tint;
    // UV2 is derived per connected sail panel, not from the authored UV0
    // texture atlas. Inset the emblem so all four arms remain readable.
    // Furled components use sentinel (-1,-1), which samples a clear edge.
    vec2 emblem_uv = (UV2 - vec2(0.5)) * 1.25 + vec2(0.5);
    float emblem_coverage = texture(order_cross_emblem, emblem_uv).a * cross_color.a;
    ALBEDO = mix(base_col.rgb, cross_color.rgb, emblem_coverage);
    ALPHA = base_col.a;
    ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;

    ROUGHNESS = sail_roughness;
    METALLIC = sail_metallic;
    if (has_normal_map) {
        NORMAL_MAP = texture(sail_normal_tex, UV).rgb;
        NORMAL_MAP_DEPTH = sail_normal_depth;
    }
    if (has_roughness_map) {
        ROUGHNESS *= channel_value(texture(sail_roughness_tex, UV), roughness_channel);
    }
    if (has_metallic_map) {
        METALLIC *= channel_value(texture(sail_metallic_tex, UV), metallic_channel);
    }
    if (has_ao_map) {
        AO = channel_value(texture(sail_ao_tex, UV), ao_channel);
    }
}
