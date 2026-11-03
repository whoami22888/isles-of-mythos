shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 crest : source_color = vec4(0.88, 0.97, 1.0, 0.9);
uniform vec4 foot : source_color = vec4(0.45, 0.88, 0.90, 0.15);

void vertex() {
	VERTEX.x += sin(TIME * 2.4 + VERTEX.y * 1.7) * 0.12;
}

void fragment() {
	float flow = fract(UV.y * 5.0 - TIME * 0.85);
	float streak = smoothstep(0.0, 0.12, flow) * smoothstep(0.55, 0.18, flow);
	float mist = smoothstep(0.15, 0.0, UV.y);
	vec3 col = mix(foot.rgb, crest.rgb, clamp(UV.y + streak * 0.35, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = mix(foot.a, crest.a, UV.y) * (0.45 + streak) + mist * 0.35;
}
