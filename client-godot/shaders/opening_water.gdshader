shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D depth_tex : hint_depth_texture, filter_linear, repeat_disable;
uniform vec3 shallow_color : source_color = vec3(0.05, 0.72, 0.70);
uniform vec3 deep_color : source_color = vec3(0.015, 0.12, 0.38);
uniform vec3 sun_dir = vec3(0.42, 0.48, 0.28);
uniform vec4 ship_a = vec4(0.0);
uniform vec4 ship_b = vec4(0.0);
uniform float storm : hint_range(0.0, 1.0) = 0.25;

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

float wake_band(vec2 p, vec4 ship) {
	vec2 fwd = ship.zw;
	float fl = length(fwd);
	if (fl < 0.001) {
		return 0.0;
	}
	fwd /= fl;
	vec2 side = vec2(-fwd.y, fwd.x);
	vec2 rel = p - ship.xy;
	float along = dot(rel, fwd);
	float across = abs(dot(rel, side));
	float trail = smoothstep(2.5, -22.0, along) * smoothstep(7.5, 1.1, across);
	float bow = smoothstep(6.0, 0.4, length(rel)) * smoothstep(3.5, 0.2, across);
	return clamp(trail * 0.85 + bow, 0.0, 1.0);
}

void vertex() {
	vec2 xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec3 normal = vec3(0.0, 1.0, 0.0);
	vec3 offset = gerstner(xz, vec2(1.0, 0.22), 0.22, 22.0, 1.05, normal);
	offset += gerstner(xz, vec2(0.15, 1.0), 0.18, 11.0, 1.35, normal);
	offset += gerstner(xz, vec2(-0.55, 0.45), 0.14, 6.0, 1.6, normal);
	VERTEX += offset;
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
	float depth_fade = clamp(dist / 85.0, 0.08, 1.0);
	vec3 water = mix(shallow_color, deep_color, depth_fade);
	water = mix(water, water * vec3(0.78, 0.84, 0.9), storm * 0.25);
	float shore = 0.0;
	if (thickness > 0.08 && thickness < 1.35) {
		shore = smoothstep(1.2, 0.2, thickness) * 0.55;
	}
	float crest = smoothstep(0.35, 1.05, v_crest) * 0.22;
	float wake = wake_band(v_world.xz, ship_a) + wake_band(v_world.xz, ship_b);
	float foam = clamp(shore * 0.9 + crest + wake * 0.75, 0.0, 1.0);
	ALBEDO = mix(water, vec3(0.82, 0.96, 0.95), foam);
	ROUGHNESS = mix(0.05, 0.42, foam);
	METALLIC = 0.0;
	SPECULAR = 0.55;
	vec3 n = normalize(NORMAL);
	vec3 sun = normalize(sun_dir);
	vec3 view_dir = normalize(VIEW);
	float glint = pow(clamp(dot(n, normalize(view_dir + sun)), 0.0, 1.0), mix(140.0, 50.0, storm));
	EMISSION = vec3(1.0, 0.9, 0.62) * glint * clamp(n.y, 0.0, 1.0) * mix(0.28, 0.08, storm);
	ALPHA = 0.97;
}
