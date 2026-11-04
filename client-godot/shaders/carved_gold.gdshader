shader_type canvas_item;

// Per-glyph gold-to-brown stone. UV.y runs down each letter, so the cap
// catches light and the foot sits in the carved shadow.
uniform vec4 gold : source_color = vec4(0.99, 0.86, 0.46, 1.0);
uniform vec4 clay : source_color = vec4(0.52, 0.30, 0.10, 1.0);
uniform vec4 deep : source_color = vec4(0.20, 0.09, 0.03, 1.0);

float hash(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float y = clamp(UV.y, 0.0, 1.0);
	vec3 col = mix(gold.rgb, clay.rgb, smoothstep(0.04, 0.5, y));
	col = mix(col, deep.rgb, smoothstep(0.58, 1.0, y));
	float grain = hash(floor(UV * vec2(240.0, 36.0)));
	col *= 0.84 + 0.22 * grain;
	col += vec3(0.30, 0.20, 0.06) * smoothstep(0.18, 0.0, y);
	COLOR = vec4(col, tex.a);
}
