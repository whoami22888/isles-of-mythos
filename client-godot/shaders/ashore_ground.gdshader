shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Stylised island ground: wet sand at the waterline, warm dry sand, then
// lush grass inland and rock on steep faces. Texture adds grain only.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float uv_scale = 9.0;
uniform vec3 wet_sand : source_color = vec3(0.74, 0.58, 0.38);
uniform vec3 dry_sand : source_color = vec3(0.92, 0.75, 0.50);
uniform vec3 grass : source_color = vec3(0.26, 0.58, 0.18);
uniform vec3 grass_dark : source_color = vec3(0.13, 0.40, 0.14);
uniform vec3 rock : source_color = vec3(0.45, 0.40, 0.36);
uniform float grass_line = 1.45;

varying vec3 v_world;
varying vec3 v_normal;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 grain = texture(albedo_tex, uv).rgb;
	float lum = dot(grain, vec3(0.333));
	float n = noise(v_world.xz * 0.18) * 0.6 + noise(v_world.xz * 0.9) * 0.4;
	float y = v_world.y + (n - 0.5) * 0.7;
	vec3 col = mix(wet_sand, dry_sand, smoothstep(0.15, 0.75, y));
	vec3 g = mix(grass_dark, grass, n);
	col = mix(col, g, smoothstep(grass_line - 0.2, grass_line + 0.5, y));
	float steep = 1.0 - clamp(v_normal.y, 0.0, 1.0);
	col = mix(col, rock, smoothstep(0.35, 0.6, steep));
	col *= 0.9 + lum * 0.22;
	ALBEDO = col;
	NORMAL_MAP = mix(vec3(0.5, 0.5, 1.0), texture(normal_tex, uv).rgb, 0.5);
	ROUGHNESS = mix(0.55, 0.92, smoothstep(0.1, 0.6, y));
	METALLIC = 0.0;
}
