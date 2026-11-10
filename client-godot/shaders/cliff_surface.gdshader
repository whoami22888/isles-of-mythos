shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Grey-brown weathered cliff with grass on ledges and moss drips on the face.
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_rough : filter_linear_mipmap, repeat_enable;
uniform vec4 rock_tint : source_color = vec4(0.84, 0.78, 0.70, 1.0);
uniform vec4 grass_tint : source_color = vec4(0.38, 0.56, 0.26, 1.0);
uniform float rock_scale = 0.10;
uniform float grass_scale = 0.15;
uniform float ledge_start = 0.48;
uniform float ledge_full = 0.80;
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

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 grade_weathered_rock(vec3 rock) {
	float luma = dot(rock, vec3(0.30, 0.55, 0.15));
	vec3 grey = vec3(luma);
	vec3 warm = mix(grey, rock, 0.42) * vec3(1.10, 1.04, 0.94) + vec3(0.12, 0.10, 0.08);
	float hi = smoothstep(0.35, 0.78, luma);
	warm = mix(warm, warm * vec3(1.14, 1.08, 0.96), hi * 0.35);
	return warm;
}

float vertical_cracks(vec3 p) {
	// Warped, infrequent veins — not a regular vertical barcode.
	float wx = p.x + 0.55 * sin(p.z * 0.62) + 0.28 * sin(p.y * 1.15 + p.z * 0.3);
	float vein = pow(abs(sin(wx * 1.15 + hash21(floor(p.xz * 1.7)) * 6.0)), 12.0);
	float fine = pow(abs(sin(wx * 3.3 + p.z * 0.5)), 16.0) * 0.4;
	float mottling = 0.15 * hash21(floor(p.xz * 4.3 + p.y * 0.7));
	return clamp(vein * 0.55 + fine + mottling, 0.0, 0.7);
}

void fragment() {
	vec3 n = normalize(world_nor);
	float grass_w = smoothstep(ledge_start, ledge_full, clamp(n.y, 0.0, 1.0));
	// Extra moss on mid ledges so the wall is broken up.
	grass_w = clamp(grass_w + smoothstep(0.28, 0.60, n.y) * 0.34, 0.0, 1.0);
	float wet = 1.0 - smoothstep(sea_level + 0.05, sea_level + 1.6, world_pos.y);
	vec3 rock_a = triplanar_albedo(rock_albedo, world_pos, n, rock_scale);
	vec3 rock_b = triplanar_albedo(rock_albedo, world_pos.zyx * 0.83 + vec3(2.4, 0.0, 1.1), n.zyx, rock_scale * 0.62);
	vec3 rock = grade_weathered_rock(mix(rock_a, rock_b, 0.48) * rock_tint.rgb);
	float cracks = vertical_cracks(world_pos);
	rock *= (1.0 - cracks * 0.40);
	rock *= mix(1.0, 0.58, wet);
	float face = 1.0 - smoothstep(0.28, 0.82, clamp(n.y, 0.0, 1.0));
	float drip = face * pow(hash21(vec2(world_pos.x * 1.8, floor(world_pos.z * 2.0))), 2.8);
	rock = mix(rock, vec3(0.20, 0.30, 0.14), drip * 0.38);
	vec3 grass = texture(grass_albedo, world_pos.xz * grass_scale).rgb * grass_tint.rgb;
	ALBEDO = mix(rock, grass, grass_w);
	float rock_r = triplanar_scalar(rock_rough, world_pos, n, rock_scale);
	float grass_r = texture(grass_rough, world_pos.xz * grass_scale).r;
	ROUGHNESS = clamp(mix(mix(mix(rock_r, 0.78, cracks), 0.45, wet * 0.5), grass_r, grass_w), 0.40, 0.98);
	METALLIC = 0.0;
	SPECULAR = mix(0.18, 0.08, grass_w);
	vec3 n_rock = triplanar_normal(rock_normal, world_pos, n, rock_scale);
	vec3 n_grass = texture(grass_normal, world_pos.xz * grass_scale).rgb;
	NORMAL_MAP = mix(n_rock, n_grass, grass_w);
	NORMAL_MAP_DEPTH = mix(0.90, 0.50, grass_w);
}
