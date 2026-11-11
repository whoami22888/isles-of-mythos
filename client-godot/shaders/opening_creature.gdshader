shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D orm_tex : hint_roughness_g, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool has_orm = false;
uniform bool has_normal = false;
uniform float desat = 0.5;
uniform vec3 tint = vec3(0.80, 0.86, 0.80);
uniform float dark = 0.72;
uniform float rough_lo = 0.34;
uniform float rough_hi = 0.62;
uniform float wet_height = 0.0;
void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(l), desat) * tint * dark;
	ALBEDO = c;
	float r = has_orm ? texture(orm_tex, UV).g : 0.5;
	ROUGHNESS = mix(rough_lo, rough_hi, r);
	METALLIC = 0.0;
	SPECULAR = 0.42;
	if (has_normal) { NORMAL_MAP = texture(normal_tex, UV).rgb; }
}
