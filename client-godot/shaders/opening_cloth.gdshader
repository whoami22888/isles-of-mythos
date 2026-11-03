shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform float sway = 0.22;

void vertex() {
	float along = clamp(VERTEX.x / 1.15, 0.0, 1.0);
	VERTEX.y += sin(TIME * 2.1 + VERTEX.x * 3.2) * sway * along;
	VERTEX.z += cos(TIME * 1.6 + VERTEX.x * 2.6) * sway * 0.55 * along;
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * tint.rgb;
	ROUGHNESS = 0.72;
	METALLIC = 0.0;
}
