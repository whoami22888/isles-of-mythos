shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float uv_scale = 14.0;
uniform vec3 tint : source_color = vec3(1.0);

void fragment() {
	vec2 uv = UV * uv_scale;
	ALBEDO = texture(albedo_tex, uv).rgb * tint;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	ROUGHNESS = clamp(texture(rough_tex, uv).r, 0.45, 1.0);
	METALLIC = 0.0;
}
