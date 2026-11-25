shader_type spatial;
render_mode depth_draw_opaque, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float metallic : hint_range(0.0, 1.0) = 0.05;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_albedo_texture = false;
uniform bool use_normal_texture = false;
uniform bool use_roughness_texture = false;
uniform bool use_triplanar = false;
uniform float triplanar_scale : hint_range(0.001, 10.0) = 0.25;

uniform float toon_ramp_smoothness : hint_range(0.01, 0.2) = 0.05;
uniform vec4 rim_color : source_color = vec4(1.0, 0.9, 0.7, 1.0);
uniform float rim_thickness : hint_range(0.0, 1.0) = 0.35;
uniform float rim_strength : hint_range(0.0, 4.0) = 0.8;

varying vec3 world_position;
varying vec3 world_normal;
varying float vertex_rim;

vec4 sample_albedo(vec3 position, vec3 normal, vec2 uv) {
	if (!use_albedo_texture) {
		return base_color;
	}
	if (!use_triplanar) {
		return texture(albedo_texture, uv) * base_color;
	}
	vec3 weights = pow(abs(normal), vec3(4.0));
	weights /= max(weights.x + weights.y + weights.z, 0.0001);
	vec3 p = position * triplanar_scale;
	vec4 x_sample = texture(albedo_texture, p.zy);
	vec4 y_sample = texture(albedo_texture, p.xz);
	vec4 z_sample = texture(albedo_texture, p.xy);
	return (x_sample * weights.x + y_sample * weights.y + z_sample * weights.z) * base_color;
}

float sample_roughness(vec3 position, vec3 normal, vec2 uv) {
	if (!use_roughness_texture) {
		return roughness;
	}
	if (!use_triplanar) {
		return texture(roughness_texture, uv).r * roughness;
	}
	vec3 weights = pow(abs(normal), vec3(4.0));
	weights /= max(weights.x + weights.y + weights.z, 0.0001);
	vec3 p = position * triplanar_scale;
	float x_sample = texture(roughness_texture, p.zy).r;
	float y_sample = texture(roughness_texture, p.xz).r;
	float z_sample = texture(roughness_texture, p.xy).r;
	return clamp((x_sample * weights.x + y_sample * weights.y + z_sample * weights.z) * roughness, 0.0, 1.0);
}

void vertex() {
	vec4 world = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_position = world.xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float view_edge = 1.0 - abs(dot(normalize(world_normal), normalize(CAMERA_POSITION_WORLD - world_position)));
	vertex_rim = smoothstep(1.0 - rim_thickness, 1.0, view_edge);
}

void fragment() {
	vec3 normal = normalize(world_normal);
	vec4 albedo = sample_albedo(world_position, normal, UV);
	ALBEDO = albedo.rgb;
	METALLIC = metallic;
	ROUGHNESS = sample_roughness(world_position, normal, UV);

	if (use_normal_texture) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
	}
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float edge = max(toon_ramp_smoothness, 0.001);
	float ramp = smoothstep(0.0, edge, ndotl) * 0.34
			+ smoothstep(0.42, 0.42 + edge, ndotl) * 0.33
			+ smoothstep(0.78, 0.78 + edge, ndotl) * 0.33;
	vec3 diffuse = ALBEDO * LIGHT_COLOR * ramp * ATTENUATION;

	float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fragment_rim = smoothstep(1.0 - rim_thickness, 1.0, 1.0 - ndotv);
	float combined_rim = max(fragment_rim, vertex_rim * 0.5) * smoothstep(0.0, edge, ndotl);
	vec3 rim = rim_color.rgb * rim_strength * combined_rim * LIGHT_COLOR;

	DIFFUSE_LIGHT += diffuse + rim;
}
