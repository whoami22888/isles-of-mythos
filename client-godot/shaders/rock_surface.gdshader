shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Darker, warmer rocks with a wet band near the waterline and moss on tops.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rough_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 rock_tint : source_color = vec4(0.58, 0.48, 0.38, 1.0);
uniform vec4 moss_tint : source_color = vec4(0.30, 0.42, 0.20, 1.0);
uniform float sea_level = -0.35;

varying vec3 world_pos;
varying vec3 world_nor;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nor = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 rock = texture(albedo_tex, UV).rgb * rock_tint.rgb;
	vec3 moss = texture(moss_tex, world_pos.xz * 0.45).rgb * moss_tint.rgb;
	float up = smoothstep(0.38, 0.84, world_nor.y);
	float wet = 1.0 - smoothstep(sea_level + 0.02, sea_level + 0.90, world_pos.y);
	rock *= mix(1.0, 0.42, wet);
	ALBEDO = mix(rock, moss, up * mix(0.35, 0.62, 1.0 - wet));
	float rough = texture(rough_tex, UV).g;
	ROUGHNESS = mix(mix(clamp(rough, 0.45, 0.92), 0.38, wet * 0.7), 0.78, up * 0.3);
	METALLIC = 0.0;
	SPECULAR = mix(0.18, 0.32, wet);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 0.85;
}
