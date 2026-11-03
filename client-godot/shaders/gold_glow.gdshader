shader_type canvas_item;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float falloff = smoothstep(1.0, 0.12, length(p));
	COLOR = vec4(1.0, 0.74, 0.28, falloff * falloff * 0.78);
}
