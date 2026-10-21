// Shared terrain-sampled shoreline contract, NOT an independent ocean material.
// Include from the ocean owner's shader; bind once after the coast mesh exists.
// World-space X/Z must match the terrain mesh used by the heightfield baker.
// A missing/unbound heightmap MUST NOT be treated as verified shoreline evidence.

uniform sampler2D shore_heightmap : filter_linear, repeat_disable;
uniform vec2 shore_origin_xz = vec2(0.0);
uniform vec2 shore_extent_xz = vec2(1.0);
uniform vec2 shore_texture_size = vec2(2.0);

// Returns 0 outside the baked mesh so foam cannot appear along invented shore.
float shore_terrain_coverage(vec2 world_xz) {
    vec2 uv = (world_xz - shore_origin_xz) / max(shore_extent_xz, vec2(0.00001));
    // Keep the heightfield authoritative while feathering only its outer
    // sampling border. A hard step at the baked mesh edge produced a visible
    // rectangular colour seam in the ocean; the feather is bounded to the
    // final 3.5% of the actual terrain extent and cannot invent foam outside
    // the mesh because contact still requires the sampled shoreline height.
    float edge_x = smoothstep(0.0, 0.035, uv.x) * (1.0 - smoothstep(0.965, 1.0, uv.x));
    float edge_y = smoothstep(0.0, 0.035, uv.y) * (1.0 - smoothstep(0.965, 1.0, uv.y));
    return edge_x * edge_y;
}

// Samples ACTUAL mesh elevations (red 32-bit float channel). Correct texel
// centre mapping is necessary to prevent half-pixel foam/contact offsets.
float shore_terrain_height(vec2 world_xz) {
    vec2 normalised = (world_xz - shore_origin_xz) / max(shore_extent_xz, vec2(0.00001));
    vec2 tex_size = max(shore_texture_size, vec2(2.0));
    vec2 uv = (normalised * (tex_size - vec2(1.0)) + vec2(0.5)) / tex_size;
    vec2 half_texel = vec2(0.5) / tex_size;
    return texture(shore_heightmap, clamp(uv, half_texel, vec2(1.0) - half_texel)).r;
}

// Ocean integration example in fragment() (ship wakes remain a separate effect):
// float floor_y = shore_terrain_height(surface_world.xz);
// float coverage = shore_terrain_coverage(surface_world.xz);
// float contact = coverage * (1.0 - smoothstep(0.025, 0.24, abs(sea_level - floor_y)));
// Open water beyond coverage must use the independent deep-ocean shelf; do
// NOT clamp its height to the nearest island texel to invent contact foam.
