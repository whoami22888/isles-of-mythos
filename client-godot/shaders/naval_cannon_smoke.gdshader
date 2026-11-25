shader_type spatial;
render_mode unshaded, shadows_disabled, ambient_light_disabled, depth_draw_never, blend_mix, cull_disabled;

uniform vec4 smoke_color : source_color = vec4(0.72, 0.68, 0.62, 0.55);
varying float puff;

void vertex() {
	puff = COLOR.a;
	VERTEX *= mix(0.45, 1.35, COLOR.r);
}

void fragment() {
	vec2 centered = UV * 2.0 - vec2(1.0);
	float falloff = 1.0 - clamp(dot(centered, centered), 0.0, 1.0);
	float alpha = smoke_color.a * falloff * puff;
	if (alpha < 0.02) {
		discard;
	}
	ALBEDO = smoke_color.rgb;
	ALPHA = alpha;
}
