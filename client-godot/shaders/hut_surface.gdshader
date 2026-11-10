shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Vertex colour alpha selects wood (1) vs thatch (0). Triplanar, no UVs needed
// on the procedural hut boxes. Colour.rgb tints the sampled CC0 textures.
uniform sampler2D wood_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D wood_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wood_rough : filter_linear_mipmap, repeat_enable;
uniform sampler2D thatch_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D thatch_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D thatch_rough : filter_linear_mipmap, repeat_enable;
uniform vec4 wood_tint : source_color = vec4(1.05, 0.95, 0.82, 1.0);
uniform vec4 thatch_tint : source_color = vec4(1.35, 1.08, 0.62, 1.0);
uniform float wood_scale = 0.85;
uniform float thatch_scale = 0.70;

varying vec3 world_pos;
varying vec3 world_nor;
varying vec4 vert_color;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nor = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vert_color = COLOR;
}

vec3 triplanar_albedo(sampler2D tex, vec3 p, vec3 n, float scale) {
	vec3 b = abs(n);
	b = pow(b, vec3(4.0));
	b /= (b.x + b.y + b.z + 1e-5);
	return texture(tex, p.zy * scale).rgb * b.x
		+ texture(tex, p.xz * scale).rgb * b.y
		+ texture(tex, p.xy * scale).rgb * b.z;
}

vec3 triplanar_n(sampler2D tex, vec3 p, vec3 n, float scale) {
	vec3 b = abs(n);
	b = pow(b, vec3(4.0));
	b /= (b.x + b.y + b.z + 1e-5);
	return texture(tex, p.zy * scale).rgb * b.x
		+ texture(tex, p.xz * scale).rgb * b.y
		+ texture(tex, p.xy * scale).rgb * b.z;
}

float triplanar_r(sampler2D tex, vec3 p, vec3 n, float scale) {
	vec3 b = abs(n);
	b = pow(b, vec3(4.0));
	b /= (b.x + b.y + b.z + 1e-5);
	return texture(tex, p.zy * scale).r * b.x
		+ texture(tex, p.xz * scale).r * b.y
		+ texture(tex, p.xy * scale).r * b.z;
}

void fragment() {
	float wood_w = clamp(vert_color.a, 0.0, 1.0);
	vec3 wood = triplanar_albedo(wood_albedo, world_pos, world_nor, wood_scale) * wood_tint.rgb;
	vec3 thatch = triplanar_albedo(thatch_albedo, world_pos, world_nor, thatch_scale) * thatch_tint.rgb;
	vec3 albedo = mix(thatch, wood, wood_w);
	// Keep a hint of the authored vertex colour so posts stay darker than walls.
	albedo *= mix(vec3(1.0), vert_color.rgb * 1.55, 0.35 * wood_w + 0.15);
	ALBEDO = albedo;
	float wr = triplanar_r(wood_rough, world_pos, world_nor, wood_scale);
	float tr = triplanar_r(thatch_rough, world_pos, world_nor, thatch_scale);
	ROUGHNESS = mix(clamp(tr, 0.72, 0.98), clamp(wr, 0.55, 0.92), wood_w);
	METALLIC = 0.0;
	SPECULAR = 0.12;
	vec3 nmap = mix(
		triplanar_n(thatch_normal, world_pos, world_nor, thatch_scale),
		triplanar_n(wood_normal, world_pos, world_nor, wood_scale),
		wood_w
	);
	NORMAL_MAP = nmap;
	NORMAL_MAP_DEPTH = mix(1.1, 0.7, wood_w);
}
