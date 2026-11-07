shader_type canvas_item;

void fragment() {
	vec2 p = UV - vec2(0.5);
	p.x *= 1.55;
	float d = length(p);
	float vignette = smoothstep(0.16, 0.23, d);
	COLOR = vec4(0.02, 0.025, 0.03, vignette * 0.94);
}
