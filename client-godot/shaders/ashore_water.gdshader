shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Lagoon water for the washed-ashore island. Same Gerstner approach as
// opening_water.gdshader, with a shallower shore so the sand reads through.
uniform sampler2D depth_tex : hint_depth_texture, filter_linear, repeat_disable;
uniform vec3 shallow_color : source_color = vec3(0.20, 0.88, 0.78);
uniform vec3 deep_color : source_color = vec3(0.02, 0.15, 0.42);
uniform vec3 sun_dir = vec3(0.35, 0.62, 0.28);

varying vec3 v_world;
varying float v_crest;

vec3 gerstner(vec2 xz, vec2 dir, float steep, float wavelength, float speed, inout vec3 normal) {
	float k = TAU / wavelength;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(dir);
	float f = k * (dot(d, xz) - c * speed * TIME);
	float a = steep / k;
	float s = sin(f);
	float co = cos(f);
	normal.x -= d.x * steep * co;
	normal.z -= d.y * steep * co;
	normal.y -= steep * s;
	return vec3(d.x * a * co, a * s, d.y * a * co);
}

void vertex() {
	vec2 xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec3 normal = vec3(0.0, 1.0, 0.0);
	vec3 offset = gerstner(xz, vec2(1.0, 0.18), 0.16, 18.0, 0.85, normal);
	offset += gerstner(xz, vec2(0.12, 1.0), 0.12, 9.0, 1.15, normal);
	offset += gerstner(xz, vec2(-0.62, 0.4), 0.08, 5.0, 1.35, normal);
	VERTEX += offset * 0.38;
	v_crest = offset.y;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize(normal);
}

float h2(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453); }
float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), u.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), u.x), u.y);
}

void fragment() {
	float surface = max(-VERTEX.z, 0.001);
	float raw_depth = texture(depth_tex, SCREEN_UV).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	scene_view.xyz /= scene_view.w;
	float behind = max(-scene_view.z, 0.001);
	float thickness = clamp(behind - surface, 0.0, 60.0);
	// Turquoise over sand, fading to sapphire as the bottom drops away.
	float d = smoothstep(0.2, 7.5, thickness);
	vec3 lagoon = mix(shallow_color * 1.08, vec3(0.04, 0.55, 0.72), smoothstep(0.0, 0.45, d));
	vec3 water = mix(lagoon, deep_color, smoothstep(0.35, 1.0, d));
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	water = mix(water, vec3(0.18, 0.45, 0.72), smoothstep(90.0, 220.0, dist) * 0.5);
	// Caustic shimmer in the shallows.
	float c = n2(v_world.xz * 0.9 + vec2(TIME * 0.35, TIME * 0.2)) * n2(v_world.xz * 1.3 - vec2(TIME * 0.25, 0.0));
	water += vec3(0.25, 0.32, 0.28) * smoothstep(0.18, 0.5, c) * (1.0 - d) * 0.6;
	// Broken white shore foam that pulses with the swell.
	float band = 0.55 + 0.35 * sin(TIME * 1.4 + v_world.x * 0.15);
	float shore = (thickness > 0.0) ? smoothstep(band, 0.0, thickness) : 0.0;
	float breakup = n2(v_world.xz * 2.6 + TIME * 0.5);
	float foam = clamp(shore * smoothstep(0.25, 0.65, breakup + shore * 0.5), 0.0, 1.0);
	float crest = smoothstep(0.32, 0.9, v_crest) * 0.22 * d;
	foam = clamp(foam + crest, 0.0, 1.0);
	ALBEDO = mix(water, vec3(0.96, 0.99, 1.0), foam);
	ROUGHNESS = mix(0.05, 0.5, foam);
	METALLIC = 0.0;
	SPECULAR = 0.6;
	vec3 n = normalize(NORMAL);
	vec3 sun = normalize(sun_dir);
	vec3 view_dir = normalize(VIEW);
	float glint = pow(clamp(dot(n, normalize(view_dir + sun)), 0.0, 1.0), 120.0);
	EMISSION = vec3(1.0, 0.9, 0.68) * glint * 0.35;
	ALPHA = mix(0.97, 0.55, (1.0 - smoothstep(0.0, 1.2, thickness)) * (1.0 - foam));
}
