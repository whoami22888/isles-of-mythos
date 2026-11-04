shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap, repeat_enable;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void fragment() {
	vec2 uv = UV * vec2(2.2, 3.4);
	float n = noise(uv * 4.0 + vec2(TIME * 0.05, 0.0));
	n += 0.5 * noise(uv * 9.0 - vec2(0.0, TIME * 0.08));
	float crack = smoothstep(0.62, 0.78, n);
	vec3 rock = texture(rock_tex, uv).rgb * vec3(0.45, 0.32, 0.26);
	ALBEDO = mix(rock, vec3(0.08, 0.02, 0.01), crack);
	NORMAL_MAP = texture(rock_normal, uv).rgb;
	ROUGHNESS = mix(0.86, 0.35, crack);
	METALLIC = 0.0;
	EMISSION = vec3(1.0, 0.32, 0.04) * crack * 2.4 + vec3(0.35, 0.05, 0.0) * smoothstep(0.5, 0.7, n);
}
