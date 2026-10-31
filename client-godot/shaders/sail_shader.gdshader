shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// PBR-preserving high-definition heraldic overlay. The existing mesh UV0,
// source alpha cutout, normal, roughness, metallic and AO are authoritative.
// UV2 is an independent connected-panel projection prepared by the wrapper.
uniform sampler2D base_sail_tex : source_color, filter_linear_mipmap;
uniform sampler2D order_cross_emblem : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 base_tint : source_color = vec4(1.0);
uniform vec4 cross_color : source_color = vec4(0.8, 0.1, 0.1, 1.0);
uniform float alpha_scissor_threshold : hint_range(0.01, 0.99) = 0.5;
uniform bool use_vector_cross = true;
uniform float emblem_scale : hint_range(0.6, 2.0) = 1.25;
uniform float fabric_weave_strength : hint_range(0.0, 0.06) = 0.02;
uniform float dye_roughness_boost : hint_range(0.0, 0.2) = 0.035;
uniform float linen_grade_strength : hint_range(0.0, 1.0) = 0.0;

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

// Exact normalized contour from res://assets/emblems/order_cross_mask.svg.
// Analytic signed-distance coverage eliminates 512px SVG raster jaggedness.
vec2 cross_corner(int i) {
    if (i == 0) { return vec2(200.0, 32.0) / 512.0; }
    if (i == 1) { return vec2(312.0, 32.0) / 512.0; }
    if (i == 2) { return vec2(280.0, 180.0) / 512.0; }
    if (i == 3) { return vec2(480.0, 180.0) / 512.0; }
    if (i == 4) { return vec2(480.0, 292.0) / 512.0; }
    if (i == 5) { return vec2(280.0, 260.0) / 512.0; }
    if (i == 6) { return vec2(312.0, 480.0) / 512.0; }
    if (i == 7) { return vec2(200.0, 480.0) / 512.0; }
    if (i == 8) { return vec2(232.0, 260.0) / 512.0; }
    if (i == 9) { return vec2(32.0, 292.0) / 512.0; }
    if (i == 10) { return vec2(32.0, 180.0) / 512.0; }
    return vec2(232.0, 180.0) / 512.0;
}

float cross_sdf(vec2 uv) {
    float distance_to_edge = 8.0;
    bool inside = false;
    for (int i = 0; i < 12; i++) {
        vec2 a = cross_corner(i);
        vec2 b = cross_corner((i + 1) % 12);
        vec2 edge = b - a;
        float t = clamp(dot(uv - a, edge) / max(dot(edge, edge), 0.000001), 0.0, 1.0);
        distance_to_edge = min(distance_to_edge, length(uv - (a + edge * t)));
        if ((a.y > uv.y) != (b.y > uv.y)) {
            float intersection = a.x + (uv.y - a.y) * edge.x / (b.y - a.y);
            if (uv.x < intersection) {
                inside = !inside;
            }
        }
    }
    return inside ? -distance_to_edge : distance_to_edge;
}

float channel_value(vec4 texel, int channel) {
    if (channel == 1) { return texel.g; }
    if (channel == 2) { return texel.b; }
    if (channel == 3) { return texel.a; }
    if (channel == 4) { return dot(texel.rgb, vec3(0.2126, 0.7152, 0.0722)); }
    return texel.r;
}

void fragment() {
    vec4 source_col = texture(base_sail_tex, UV) * base_tint;
    vec2 emblem_uv = (UV2 - vec2(0.5)) * emblem_scale + vec2(0.5);
    float coverage = 0.0;
    if (UV2.x >= 0.0 && UV2.y >= 0.0 && UV2.x <= 1.0 && UV2.y <= 1.0) {
        if (use_vector_cross) {
            float sdf = cross_sdf(emblem_uv);
            float aa = max(fwidth(sdf), 0.00025);
            coverage = 1.0 - smoothstep(-aa, aa, sdf);
        } else {
            coverage = texture(order_cross_emblem, emblem_uv).a;
        }
    }
    coverage *= cross_color.a;
    // Optional linen look-dev on source PBR diffuse: adjust the cloth dye
    // without flattening the authored normal/roughness/AO or alpha atlas.
    // Default is 0: existing admitted ship material is unchanged.
    float textile_luma = dot(source_col.rgb, vec3(0.2126, 0.7152, 0.0722));
    float textile_shade = 0.78 + 0.22 * smoothstep(0.05, 0.9, textile_luma);
    vec3 graded_linen = vec3(0.91, 0.84, 0.71) * textile_shade;
    vec3 cloth_color = mix(source_col.rgb, graded_linen, linen_grade_strength);
    // Dyed fabric retains diffuse weave/age variation below the heraldry.
    vec3 pigment = mix(cross_color.rgb, cross_color.rgb * cloth_color, 0.15);
    ALBEDO = mix(cloth_color, pigment, coverage);
    ALPHA = source_col.a;
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
    // Subtle physically plausible fabric micro-roughness, mip/derivative faded
    // when threads become smaller than a screen pixel (avoids distant shimmer).
    vec2 thread_uv = UV * 1024.0;
    float footprint = max(length(dFdx(thread_uv)), length(dFdy(thread_uv)));
    float weave_visibility = 1.0 - smoothstep(0.35, 1.0, footprint);
    float weave = sin(thread_uv.x * 6.283185) * sin(thread_uv.y * 6.283185);
    ROUGHNESS = clamp(ROUGHNESS + coverage * dye_roughness_boost +
        weave * weave_visibility * fabric_weave_strength, 0.0, 1.0);
}
