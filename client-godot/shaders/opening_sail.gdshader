shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, depth_draw_opaque;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap;
uniform float sway_amount = 0.22;
uniform float sway_start = 5.0;

void vertex() {
	float height = clamp((VERTEX.y - sway_start) / 11.0, 0.0, 1.0);
	float sway = sin(TIME * 1.25 + VERTEX.x * 0.28 + VERTEX.z * 0.2) * sway_amount * height;
	VERTEX.z += sway;
	VERTEX.x += cos(TIME * 0.9 + VERTEX.y * 0.35) * sway_amount * 0.28 * height;
}

void fragment() {
	vec4 alb = texture(albedo_tex, UV);
	ALPHA = alb.a;
	ALPHA_SCISSOR_THRESHOLD = 0.35;
	vec3 arm = texture(arm_tex, UV).rgb;
	ALBEDO = alb.rgb;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	ROUGHNESS = clamp(arm.g, 0.32, 0.92);
	METALLIC = 0.0;
	AO = mix(1.0, arm.r, 0.85);
}
