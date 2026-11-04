shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Stylised sand / grass / rock on the sculpted coast. One albedo sample.
// Slope and height pick the tint; the CC0 coast texture only breaks up the
// flat colour. Vertex normals from the heightfield carry the cliff light.
uniform sampler2D detail_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 sand_color : source_color = vec4(0.89, 0.76, 0.48, 1.0);
uniform vec4 grass_color : source_color = vec4(0.24, 0.52, 0.18, 1.0);
uniform vec4 rock_color : source_color = vec4(0.48, 0.42, 0.36, 1.0);
uniform float sea_level = -0.35;

varying float sand_weight;
varying float rock_weight;

void vertex() {
	vec3 world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float height = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y - sea_level;
	float beach = (1.0 - smoothstep(0.05, 1.7, height)) * (1.0 - smoothstep(0.18, 0.48, slope));
	sand_weight = clamp(beach, 0.0, 1.0);
	rock_weight = clamp(smoothstep(0.22, 0.58, slope) * (1.0 - sand_weight), 0.0, 1.0);
}

void fragment() {
	vec3 detail = texture(detail_albedo, UV).rgb;
	float grain = dot(detail, vec3(0.30, 0.55, 0.15));
	vec3 tint = mix(grass_color.rgb, sand_color.rgb, sand_weight);
	tint = mix(tint, rock_color.rgb, rock_weight);
	ALBEDO = tint * (0.62 + 0.55 * grain);
	ROUGHNESS = mix(0.92, 0.78, sand_weight);
	METALLIC = 0.0;
	SPECULAR = 0.18;
}
