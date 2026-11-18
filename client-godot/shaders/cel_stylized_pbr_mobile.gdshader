shader_type spatial;
// Mobile variant: vertex_lighting deliberately skips light(); the shared include
// enables a matching three-stop fragment albedo ramp for this path.
render_mode depth_draw_opaque, vertex_lighting, diffuse_toon, specular_toon;

#define IOM_CEL_MOBILE_VERTEX_RAMP
#include "res://shaders/cel_stylized_pbr_shared.gdshaderinc"
