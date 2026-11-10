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

uniform vec4 sand_tint : source_color = vec4(1.12, 1.00, 0.82, 1.0);
uniform vec4 grass_tint : source_color = vec4(0.62, 0.86, 0.48, 1.0);
uniform vec4 rock_tint : source_color = vec4(0.90, 0.88, 0.84, 1.0);
uniform float sea_level = -0.35;
uniform float sand_scale = 0.22;
uniform float grass_scale = 0.16;
uniform float rock_scale = 0.11;

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
	rock_weight = clamp(smoothstep(0.26, 0.62, slope) * (1.0 - sand_weight * 0.65), 0.0, 1.0);
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

void fragment() {
	vec2 sand_uv = world_pos.xz * sand_scale;
	vec2 grass_uv = world_pos.xz * grass_scale;
	vec3 sand = texture(sand_albedo, sand_uv).rgb * sand_tint.rgb;
	vec3 grass = texture(grass_albedo, grass_uv).rgb * grass_tint.rgb;
	vec3 rock = triplanar_albedo(rock_albedo, world_pos, world_nor, rock_scale) * rock_tint.rgb;
	vec3 albedo = mix(grass, sand, sand_weight);
	albedo = mix(albedo, rock, rock_weight);
	// Pull saturation down so the shelf reads as a real island, not a toy.
	float luma = dot(albedo, vec3(0.30, 0.55, 0.15));
	ALBEDO = mix(vec3(luma), albedo, 0.86);

	float sand_r = texture(sand_rough, sand_uv).r;
	float grass_r = texture(grass_rough, grass_uv).r;
	float rock_r = triplanar_scalar(rock_rough, world_pos, world_nor, rock_scale);
	float rough = mix(grass_r, sand_r, sand_weight);
	ROUGHNESS = clamp(mix(rough, rock_r, rock_weight), 0.45, 0.98);
	METALLIC = 0.0;
	SPECULAR = mix(0.16, 0.22, sand_weight);

	vec3 n_sand = texture(sand_normal, sand_uv).rgb;
	vec3 n_grass = texture(grass_normal, grass_uv).rgb;
	vec3 n_rock = triplanar_normal(rock_normal, world_pos, world_nor, rock_scale);
	vec3 nmap = mix(n_grass, n_sand, sand_weight);
	nmap = mix(nmap, n_rock, rock_weight);
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = mix(0.55, 0.85, rock_weight);
}
