shader_type sky;

// Bright tropical sky: saturated zenith, pale horizon haze, warm sun and
// soft drifting cumulus. `storm` darkens it toward dusk.
uniform float storm : hint_range(0.0, 1.0) = 0.0;
uniform vec3 sun_direction = vec3(0.42, 0.62, 0.28);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += noise(p) * a; p *= 2.03; a *= 0.5; }
	return v;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = clamp(d.y, -0.2, 1.0);
	vec3 zenith = mix(vec3(0.08, 0.32, 0.82), vec3(0.16, 0.12, 0.28), storm);
	vec3 horizon = mix(vec3(0.55, 0.8, 1.0), vec3(0.98, 0.52, 0.3), storm);
	vec3 col = mix(horizon, zenith, pow(clamp(up, 0.0, 1.0), 0.55));
	vec3 s = normalize(sun_direction);
	float sd = max(dot(d, s), 0.0);
	col += vec3(1.0, 0.82, 0.55) * pow(sd, 8.0) * 0.35;
	col += vec3(1.0, 0.95, 0.85) * smoothstep(0.9993, 0.9997, sd) * 4.0;
	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.18) * 1.6 + vec2(TIME * 0.006, 0.0);
		float c = smoothstep(0.52, 0.78, fbm(uv));
		vec3 cloud = mix(vec3(1.0, 0.98, 0.95), vec3(0.98, 0.62, 0.45), storm) * (0.85 + 0.25 * sd);
		col = mix(col, cloud, c * smoothstep(0.0, 0.18, d.y) * 0.9);
	}
	if (d.y < 0.0) {
		col = mix(horizon, vec3(0.05, 0.3, 0.5), clamp(-d.y * 3.0, 0.0, 1.0));
	}
	COLOR = pow(col, vec3(2.2)) * 1.6;
}
