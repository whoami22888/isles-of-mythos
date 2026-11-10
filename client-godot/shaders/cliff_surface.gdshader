shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Triplanar cliff rock with grass only on upward ledges and crests.
// Used by the back-ridge proxies, not the sandy beach landmass.
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_rough : filter_linear_mipmap, repeat_enable;
uniform vec4 rock_tint : source_color = vec4(0.38, 0.30, 0.22, 1.0);
uniform vec4 grass_tint : source_color = vec4(0.40, 0.58, 0.26, 1.0);
uniform float rock_scale = 0.10;
uniform float grass_scale = 0.15;
uniform float ledge_start = 0.58;
uniform float ledge_full = 0.84;
uniform float sea_level = -0.35;

varying vec3 world_pos;
varying vec3 world_nor;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nor = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 triplanar_albedo(sampler2D tex, vec3 p, vec3 n, float scale) {
	vec3 w = abs(n);
	w = w / (w.x + w.y + w.z + 1e-5);
	vec3 x = texture(tex, p.zy * scale).rgb;
	vec3 y = texture(tex, p.xz * scale).rgb;
	vec3 z = texture(tex, p.xy * scale).rgb;
	return x * w.x + y * w.y + z * w.z;
}

vec3 triplanar_normal(sampler2D tex, vec3 p, vec3 n, float scale) {
	vec3 w = abs(n);
	w = w / (w.x + w.y + w.z + 1e-5);
	vec3 x = texture(tex, p.zy * scale).rgb;
	vec3 y = texture(tex, p.xz * scale).rgb;
	vec3 z = texture(tex, p.xy * scale).rgb;
	return x * w.x + y * w.y + z * w.z;
}

float triplanar_scalar(sampler2D tex, vec3 p, vec3 n, float scale) {
	vec3 w = abs(n);
	w = w / (w.x + w.y + w.z + 1e-5);
	float x = texture(tex, p.zy * scale).r;
	float y = texture(tex, p.xz * scale).r;
	float z = texture(tex, p.xy * scale).r;
	return x * w.x + y * w.y + z * w.z;
}

void fragment() {
	vec3 n = normalize(world_nor);
	float grass_w = smoothstep(ledge_start, ledge_full, clamp(n.y, 0.0, 1.0));
	float wet = 1.0 - smoothstep(sea_level + 0.05, sea_level + 1.6, world_pos.y);
	vec3 rock = triplanar_albedo(rock_albedo, world_pos, n, rock_scale) * rock_tint.rgb;
	rock *= mix(1.0, 0.52, wet);
	vec3 grass = texture(grass_albedo, world_pos.xz * grass_scale).rgb * grass_tint.rgb;
	ALBEDO = mix(rock, grass, grass_w);
	float rock_r = triplanar_scalar(rock_rough, world_pos, n, rock_scale);
	float grass_r = texture(grass_rough, world_pos.xz * grass_scale).r;
	ROUGHNESS = clamp(mix(mix(rock_r, 0.42, wet * 0.5), grass_r, grass_w), 0.40, 0.98);
	METALLIC = 0.0;
	SPECULAR = mix(0.22, 0.08, grass_w);
	vec3 n_rock = triplanar_normal(rock_normal, world_pos, n, rock_scale);
	vec3 n_grass = texture(grass_normal, world_pos.xz * grass_scale).rgb;
	NORMAL_MAP = mix(n_rock, n_grass, grass_w);
	NORMAL_MAP_DEPTH = mix(0.90, 0.50, grass_w);
}
