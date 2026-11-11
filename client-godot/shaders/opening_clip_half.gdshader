shader_type spatial;
render_mode cull_disabled, shadows_disabled;
// Presentation-only clip for the intro ship-snap. Does not change the galleon source.
uniform vec3 clip_origin = vec3(0.0);
uniform vec3 clip_normal = vec3(1.0, 0.0, 0.0);
uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform vec3 albedo_tint : source_color = vec3(0.18, 0.12, 0.08);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (dot(world_pos - clip_origin, normalize(clip_normal)) < 0.0) {
		discard;
	}
	vec4 tex = texture(albedo_tex, UV);
	ALBEDO = tex.rgb * albedo_tint;
	ROUGHNESS = 0.82;
	METALLIC = 0.0;
}
