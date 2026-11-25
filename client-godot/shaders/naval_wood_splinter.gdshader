shader_type spatial;
render_mode unshaded, shadows_disabled, ambient_light_disabled, depth_draw_opaque, cull_disabled;

uniform vec4 splinter_color : source_color = vec4(0.45, 0.28, 0.14, 1.0);

void fragment() {
	ALBEDO = splinter_color.rgb * mix(0.75, 1.15, UV.y);
	ALPHA = splinter_color.a;
}
