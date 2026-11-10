shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// CC0 PBR sand / grass / rock, blended by world height and slope.
// Sand and grass sample the XZ plane (the shelf is mostly flat).
// Rock uses triplanar mapping so cliff faces do not stretch.
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D grass_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_rough : filter_linear_mipmap, repeat_enable;

uniform vec4 sand_tint : source_color = vec4(0.86, 0.80, 0.70, 1.0);
uniform vec4 grass_tint : source_color = vec4(0.50, 0.72, 0.38, 1.0);
uniform vec4 rock_tint : source_color = vec4(0.62, 0.60, 0.58, 1.0);
uniform float sea_level = -0.35;
uniform float sand_scale = 0.22;
uniform float grass_scale = 0.16;
uniform float rock_scale = 0.11;
uniform float rock_bias = 0.0;
uniform float distant_cool = 0.0;

varying vec3 world_pos;
varying vec3 world_nor;
varying float sand_weight;
varying float rock_weight;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nor = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float slope = 1.0 - clamp(world_nor.y, 0.0, 1.0);
	float height = world_pos.y - sea_level;
	// Wide sandy beach, then a soft climb into grass. Steep faces go to rock.
	float beach = (1.0 - smoothstep(0.12, 2.25, height)) * (1.0 - smoothstep(0.16, 0.48, slope));
	sand_weight = clamp(beach, 0.0, 1.0);
	rock_weight = clamp(smoothstep(0.28, 0.68, slope) * (1.0 - sand_weight * 0.65) + rock_bias, 0.0, 1.0);
}

vec3 triplanar_albedo(sampler2D tex, vec3 p, vec3 n, float scale) {
	vec3 b = abs(n);
	b = pow(b, vec3(4.0));
	b /= (b.x + b.y + b.z + 1e-5);
	vec3 x = texture(tex, p.zy * scale).rgb;
	vec3 y = texture(tex, p.xz * scale).rgb;
	vec3 z = texture(tex, p.xy * scale).rgb;
	return x * b.x + y * b.y + z * b.z;
}

vec3 triplanar_normal(sampler2D tex, vec3 p, vec3 n, float scale) {
	vec3 b = abs(n);
	b = pow(b, vec3(4.0));
	b /= (b.x + b.y + b.z + 1e-5);
	vec3 x = texture(tex, p.zy * scale).rgb;
	vec3 y = texture(tex, p.xz * scale).rgb;
	vec3 z = texture(tex, p.xy * scale).rgb;
	return x * b.x + y * b.y + z * b.z;
}

float triplanar_scalar(sampler2D tex, vec3 p, vec3 n, float scale) {
	vec3 b = abs(n);
	b = pow(b, vec3(4.0));
	b /= (b.x + b.y + b.z + 1e-5);
	float x = texture(tex, p.zy * scale).r;
	float y = texture(tex, p.xz * scale).r;
	float z = texture(tex, p.xy * scale).r;
	return x * b.x + y * b.y + z * b.z;
}

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 grade_weathered_rock(vec3 rock) {
	float luma = dot(rock, vec3(0.30, 0.55, 0.15));
	vec3 grey = vec3(luma);
	vec3 cool = mix(grey, rock, 0.20) * vec3(0.96, 0.94, 0.90) + vec3(0.05, 0.05, 0.045);
	float hi = smoothstep(0.45, 0.80, luma);
	cool = mix(cool, cool * vec3(1.08, 1.03, 0.94), hi * 0.22);
	cool = mix(cool, cool * vec3(0.82, 0.86, 0.94), clamp(distant_cool, 0.0, 1.0) * 0.50);
	return cool;
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
	vec2 sand_uv = world_pos.xz * sand_scale;
	vec2 grass_uv = world_pos.xz * grass_scale;
	vec3 sand = texture(sand_albedo, sand_uv).rgb * sand_tint.rgb;
	sand = min(sand, vec3(0.70, 0.66, 0.58));
	vec3 grass = texture(grass_albedo, grass_uv).rgb * grass_tint.rgb;
	// Inland ground is a darker, patchier undergrowth, not a golf-course lawn.
	float height = world_pos.y - sea_level;
	float inland = smoothstep(1.6, 4.8, height) * (1.0 - sand_weight);
	float patch = 0.5 + 0.5 * sin(world_pos.x * 0.95 + 1.3) * cos(world_pos.z * 0.72);
	grass = mix(grass, grass * vec3(0.52, 0.68, 0.40), inland * (0.40 + 0.40 * patch));
	vec3 rock_a = triplanar_albedo(rock_albedo, world_pos, world_nor, rock_scale);
	vec3 rock_b = triplanar_albedo(rock_albedo, world_pos.zyx * 0.83 + vec3(2.4, 0.0, 1.1), world_nor.zyx, rock_scale * 0.62);
	vec3 rock = grade_weathered_rock(mix(rock_a, rock_b, 0.48) * rock_tint.rgb);
	float cracks = vertical_cracks(world_pos);
	rock *= (1.0 - cracks * 0.28);
	// Soft moss drips on the upper wall so the face is not a clean stripe.
	float face = 1.0 - smoothstep(0.28, 0.82, clamp(world_nor.y, 0.0, 1.0));
	float drip = face * pow(hash21(vec2(world_pos.x * 1.8, floor(world_pos.z * 2.0))), 3.2);
	drip *= smoothstep(2.0, 6.0, height);
	rock = mix(rock, vec3(0.20, 0.30, 0.14), drip * 0.32);
	vec3 albedo = mix(grass, sand, sand_weight);
	albedo = mix(albedo, rock, rock_weight);
	float luma = dot(albedo, vec3(0.30, 0.55, 0.15));
	ALBEDO = mix(vec3(luma), albedo, 0.88);

	float sand_r = max(texture(sand_rough, sand_uv).r, 0.86);
	float grass_r = texture(grass_rough, grass_uv).r;
	float rock_r = triplanar_scalar(rock_rough, world_pos, world_nor, rock_scale);
	float rough = mix(grass_r, sand_r, sand_weight);
	ROUGHNESS = clamp(mix(rough, mix(rock_r, 0.78, cracks), rock_weight), 0.45, 0.98);
	METALLIC = 0.0;
	SPECULAR = mix(0.12, 0.06, sand_weight);

	vec3 n_sand = mix(vec3(0.5, 0.5, 1.0), texture(sand_normal, sand_uv).rgb, 0.12);
	vec3 n_grass = texture(grass_normal, grass_uv).rgb;
	vec3 n_rock = triplanar_normal(rock_normal, world_pos, world_nor, rock_scale);
	vec3 nmap = mix(n_grass, n_sand, sand_weight);
	nmap = mix(nmap, n_rock, rock_weight);
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = mix(0.28, 0.80, rock_weight);
}
