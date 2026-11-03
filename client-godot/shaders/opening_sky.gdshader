shader_type sky;

uniform float storm : hint_range(0.0, 1.0) = 0.25;
uniform vec3 sun_direction = vec3(0.48, 0.34, 0.32);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	vec3 sun = normalize(sun_direction);
	float up = clamp(dir.y, -0.05, 1.0);
	vec3 zenith = mix(vec3(0.16, 0.48, 0.95), vec3(0.07, 0.16, 0.34), storm);
	vec3 horizon = mix(vec3(1.0, 0.72, 0.42), vec3(0.62, 0.72, 0.82), storm);
	vec3 col = mix(horizon, zenith, smoothstep(-0.02, 0.28, up));
	vec2 cloud_uv = dir.xz / max(dir.y, 0.12);
	float n = noise(cloud_uv * 1.4 + vec2(TIME * 0.012, 0.0));
	n += 0.45 * noise(cloud_uv * 3.1 + vec2(TIME * 0.018, 1.7));
	n *= 0.7;
	float cover = mix(0.68, 0.5, storm);
	float clouds = smoothstep(cover, cover + 0.22, n) * smoothstep(0.02, 0.2, dir.y);
	vec3 cloud_col = mix(vec3(1.0, 0.96, 0.9), vec3(0.78, 0.82, 0.88), storm);
	col = mix(col, cloud_col, clamp(clouds, 0.0, 0.72));
	float glow = pow(max(dot(dir, sun), 0.0), 7.0);
	float disk = pow(max(dot(dir, sun), 0.0), 1600.0);
	col += vec3(1.0, 0.72, 0.36) * glow * mix(0.9, 0.22, storm);
	col += vec3(1.0, 0.96, 0.82) * disk;
	COLOR = col;
}
