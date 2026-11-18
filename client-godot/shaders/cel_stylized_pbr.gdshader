shader_type spatial;
// Per-pixel variant: custom three-stop ramp and per-light rim/specular run in light().
render_mode depth_draw_opaque, diffuse_toon, specular_toon;

#include "res://shaders/cel_stylized_pbr_shared.gdshaderinc"
