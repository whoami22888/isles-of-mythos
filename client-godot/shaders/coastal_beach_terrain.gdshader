shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Coastal terrain layering for the Godot 4.7.2 Mobile renderer.
// Layers are derived from the actual mesh height and slope, never from a
// rectangular mask: wet sand at the waterline, dry sand on the beach shelf,
// exposed rock on steep faces and vegetated soil on high, flat ground.
// Uses only the admitted Poly Haven coast_sand_rocks_02 PBR maps (CC0).
uniform sampler2D rock_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_roughness : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D rock_ao : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 dry_sand : source_color = vec4(0.74, 0.64, 0.47, 1.0);
uniform vec4 wet_sand : source_color = vec4(0.46, 0.39, 0.29, 1.0);
uniform vec4 rock_tint : source_color = vec4(0.78, 0.70, 0.60, 1.0);
uniform vec4 grass_tint : source_color = vec4(0.27, 0.36, 0.15, 1.0);
uniform float sea_level = -0.35;
// Height above sea level where the swash keeps sand saturated.
uniform float wet_band = 0.42;
// Height above sea level where the dry beach gives way to vegetated soil.
uniform float vegetation_start = 2.6;
uniform float texture_scale = 0.14;

varying vec3 world_pos;
varying vec3 world_normal;

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
               mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
    vec2 uv = world_pos.xz * texture_scale;
    float h = world_pos.y - sea_level;
    // 0 on flat ground, 1 on near-vertical faces.
    float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
    float breakup = value_noise(world_pos.xz * 0.45) * 0.6 + value_noise(world_pos.xz * 1.9) * 0.4;

    vec3 rock = texture(rock_albedo, uv).rgb * rock_tint.rgb;
    vec3 rock_n = texture(rock_normal, uv).rgb;
    float rock_r = texture(rock_roughness, uv).r;
    float rock_occ = texture(rock_ao, uv).r;

    // Fine-grained sand: two noise octaves give grain and ripple variation;
    // the rock normal map, sampled at a much finer scale, supplies microrelief.
    float grain = value_noise(world_pos.xz * 9.0) * 0.5 + value_noise(world_pos.xz * 23.0) * 0.5;
    float ripple = sin(world_pos.x * 2.7 + world_pos.z * 1.1 + breakup * 4.0) * 0.5 + 0.5;
    vec3 sand = dry_sand.rgb * (0.90 + 0.10 * grain) * (0.96 + 0.04 * ripple);
    vec3 sand_n = mix(vec3(0.5, 0.5, 1.0), texture(rock_normal, uv * 3.7).rgb, 0.35);

    // Wet sand darkens and turns glossy just above the waterline. The edge is
    // irregular so the swash line follows real geometry without a ruled band.
    float wet = 1.0 - smoothstep(wet_band * (0.55 + 0.6 * breakup), wet_band * 1.6, h);
    vec3 beach = mix(sand, wet_sand.rgb * (0.92 + 0.12 * grain), wet);
    float beach_r = mix(0.93, 0.28, wet);

    // Steep faces become rock; the threshold is noisy so outcrops read
    // naturally rather than as a constant slope cutoff.
    float rockiness = smoothstep(0.22 + 0.10 * breakup, 0.42 + 0.10 * breakup, slope);
    // Rock also emerges under very shallow or submerged terrain edges.
    rockiness = max(rockiness, (1.0 - smoothstep(-0.6, -0.15, h)) * 0.55);
    // Vegetated soil on high, flatter ground; rock still wins on cliffs.
    float vegetation = smoothstep(vegetation_start + breakup * 1.2, vegetation_start + 1.6 + breakup * 1.2, h)
        * (1.0 - smoothstep(0.18, 0.36, slope));
    vegetation *= smoothstep(0.25, 0.65, breakup + value_noise(world_pos.xz * 0.12) * 0.4);
    vec3 soil = mix(rock * vec3(0.62, 0.56, 0.44), grass_tint.rgb * (0.7 + 0.45 * breakup), 0.45 + 0.35 * breakup);

    // Sand belongs to the beach band only; higher ground that is neither
    // vegetated nor steep is weathered earth, not sand.
    float beach_mask = 1.0 - smoothstep(1.3 + breakup * 0.5, 2.2 + breakup * 0.5, h);
    vec3 earth = rock * vec3(0.66, 0.58, 0.46);
    vec3 ground = mix(earth, beach, beach_mask);
    float ground_r = mix(0.9, beach_r, beach_mask);
    vec3 albedo = mix(ground, rock, rockiness);
    albedo = mix(albedo, soil, vegetation);
    float roughness = mix(ground_r, rock_r, rockiness);
    roughness = mix(roughness, 0.92, vegetation);
    vec3 normal_tex = mix(sand_n, rock_n, max(rockiness, vegetation * 0.6));

    ALBEDO = albedo;
    NORMAL_MAP = normal_tex;
    NORMAL_MAP_DEPTH = mix(0.6, 1.0, rockiness);
    ROUGHNESS = roughness;
    AO = mix(1.0, rock_occ, max(rockiness, vegetation * 0.5));
    AO_LIGHT_AFFECT = 0.35;
    METALLIC = 0.0;
    SPECULAR = mix(0.5, 0.42, rockiness);
}
