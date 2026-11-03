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
	VERTEX += offset * 0.85;
	v_crest = offset.y;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize(normal);
}

void fragment() {
	float surface = max(-VERTEX.z, 0.001);
	float raw_depth = texture(depth_tex, SCREEN_UV).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	scene_view.xyz /= scene_view.w;
	float behind = max(-scene_view.z, 0.001);
	float thickness = behind - surface;
	float dist = length(v_world - CAMERA_POSITION_WORLD);
	float depth_fade = clamp(dist / 70.0, 0.0, 1.0);
	vec3 water = mix(shallow_color, deep_color, depth_fade);
	float shore = 0.0;
	if (thickness > 0.02 && thickness < 3.2) {
		shore = smoothstep(2.4, 0.15, thickness);
		water = mix(water, vec3(0.95, 0.86, 0.58), shore * 0.55);
	}
	float crest = smoothstep(0.28, 0.85, v_crest) * 0.18;
	float foam = clamp(shore * 0.85 + crest, 0.0, 1.0);
	ALBEDO = mix(water, vec3(0.93, 0.98, 0.96), foam);
	ROUGHNESS = mix(0.04, 0.38, foam);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	vec3 n = normalize(NORMAL);
	vec3 sun = normalize(sun_dir);
	vec3 view_dir = normalize(VIEW);
	float glint = pow(clamp(dot(n, normalize(view_dir + sun)), 0.0, 1.0), 90.0);
	EMISSION = vec3(1.0, 0.92, 0.7) * glint * clamp(n.y, 0.0, 1.0) * 0.18;
	ALPHA = mix(0.94, 0.45, shore);
}
