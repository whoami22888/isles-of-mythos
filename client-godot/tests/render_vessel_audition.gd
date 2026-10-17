extends SceneTree
## INTERNAL NON-PRODUCTION in-engine 10-second shot. Owner-video parity is
## independently judged from actual frames; generated proxies never count as
## approved premium game art or a functioning ship-control/physics feature.

const SHIP_PATH := "res://assets/world_audition/ship/dutch_ship_medium_1k.gltf"
const CAPTURE_FRAMES := 240
const OUTPUT_FPS := 24

var _stage: Node3D
var _rig: Node3D
var _ship: Node3D
var _camera: Camera3D
var _sea_material: ShaderMaterial
var _fabric_material: ShaderMaterial
var _out_dir: String
var _ship_axis := Vector2(1.0, 0.0)
var _waterline := -2.0


func _initialize() -> void:
	call_deferred("_run")


func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)


func _mesh_bounds(node: Node, minmax: Dictionary) -> void:
	if node is MeshInstance3D:
		var piece := node as MeshInstance3D
		if piece.mesh != null:
			var box: AABB = piece.mesh.get_aabb()
			for corner in range(8):
				var p: Vector3 = piece.to_global(box.get_endpoint(corner))
				minmax["min"] = minmax["min"].min(p)
				minmax["max"] = minmax["max"].max(p)
				minmax["count"] += 1
	for child in node.get_children():
		_mesh_bounds(child, minmax)


func _all_rendered_meshes_visible() -> bool:
	var frame_size: Vector2 = root.get_viewport().get_visible_rect().size
	var margin := frame_size * Vector2(0.035, 0.07)
	var pending: Array[Node] = [_rig]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D:
			var piece := node as MeshInstance3D
			if piece.mesh != null:
				var box: AABB = piece.mesh.get_aabb()
				for i in range(8):
					var p := piece.to_global(box.get_endpoint(i))
					if _camera.is_position_behind(p):
						return false
					var projected := _camera.unproject_position(p)
					if not projected.is_finite():
						return false
					if (projected.x < margin.x or projected.y < margin.y
								or projected.x > frame_size.x - margin.x
								or projected.y > frame_size.y - margin.y):
							return false
		for child in node.get_children():
			pending.append(child)
	return true


func _setup_ocean() -> void:
	# Real subdivided wave geometry and moving PBR/fresnel response, not a
	# background color plane or flat painted 'ocean' still.
	var ocean := MeshInstance3D.new()
	ocean.name = "MovingWaveOceanInternalAudition"
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	plane.subdivide_width = 180
	plane.subdivide_depth = 180
	ocean.mesh = plane
	ocean.position.y = _waterline
	_sea_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;
uniform float water_phase = 0.0;
uniform vec2 ship_axis = vec2(1.0, 0.0);
uniform vec2 ship_origin = vec2(0.0, 0.0);
varying vec3 water_world;
void vertex() {
    float wx = VERTEX.x;
    float wz = VERTEX.z;
    float a = wx * 0.29 + water_phase * 1.2;
    float b = wz * 0.38 - water_phase * 0.91;
    float c = (wx + wz) * 0.19 + water_phase * 0.76;
    VERTEX.y += sin(a) * 0.24 + sin(b) * 0.13 + sin(c) * 0.09;
    NORMAL = normalize(vec3(-0.0696 * cos(a) - 0.0171 * cos(c), 1.0,
                             -0.0494 * cos(b) - 0.0171 * cos(c)));
    water_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    vec2 q = water_world.xz - ship_origin;
    float along = dot(q, ship_axis);
    float sideways = abs(dot(q, vec2(-ship_axis.y, ship_axis.x)));
    float r = length(q);
    float crest = sin(q.x * 1.23 + q.y * 0.91 + water_phase * 3.1)
                * sin(q.y * 1.7 - water_phase * 2.2);
    float fine = sin(q.x * 3.1 + water_phase * 2.7) * sin(q.y * 2.8 - water_phase);
    float deep = smoothstep(22.0, 95.0, r);
    vec3 color_shallow = vec3(0.022, 0.43, 0.44);
    vec3 color_deep = vec3(0.018, 0.12, 0.22);
    vec3 water = mix(color_shallow, color_deep, deep);
    water += vec3(0.03, 0.065, 0.074) * max(crest, 0.0);
    // Animated turbulent hull contact and an elongated trailing wake.
    float contact = (1.0 - smoothstep(1.2, 5.9, r)) * (0.45 + 0.55 * crest);
    float trail = (1.0 - smoothstep(-28.0, 1.0, along))
                * exp(-sideways * 0.48) * (0.55 + 0.45 * fine);
    float foam = clamp(contact * 0.6 + trail * 0.58 +
                       smoothstep(0.82, 0.99, crest) * 0.14, 0.0, 0.9);
    ALBEDO = mix(water, vec3(0.84, 0.94, 0.92), foam);
    METALLIC = 0.0;
    ROUGHNESS = mix(0.18, 0.55, foam);
    SPECULAR = 0.9;
}
"""
	_sea_material.shader = shader
	_sea_material.set_shader_parameter("ship_axis", _ship_axis)
	ocean.material_override = _sea_material
	_stage.add_child(ocean)


func _canvas_vertex(surface: SurfaceTool, pos: Vector3, uv: Vector2) -> void:
	surface.set_uv(uv)
	surface.add_vertex(pos)


func _setup_canvas_sails(ship_width: float, mast_top: float, lower: float) -> void:
	# Authored unfurled fabric on the genuine licensed PBR ship. This is an
	# experimental, animated mesh and does NOT claim original source rigging.
	var color_path := "res://assets/world_audition/ship/textures/dutch_ship_medium_sails_diff_1k.jpg"
	var normal_path := "res://assets/world_audition/ship/textures/dutch_ship_medium_sails_nor_gl_1k.jpg"
	var albedo_tex := load(color_path) as Texture2D
	var normal_tex := load(normal_path) as Texture2D
	if albedo_tex == null or normal_tex == null:
		_fail("PBR fabric albedo/normal source textures unavailable")
		return
	_fabric_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;
uniform sampler2D fabric_albedo : source_color, filter_linear_mipmap;
uniform sampler2D fabric_normal : hint_normal, filter_linear_mipmap;
uniform float fabric_phase = 0.0;
void vertex() {
    // Anchored border with wind-driven billow towards the full canvas center.
    float edge = sin(UV.x * 3.14159) * sin(UV.y * 3.14159);
    VERTEX.z += edge * (0.36 + sin(fabric_phase + UV.x * 5.2 - UV.y * 2.7) * 0.19);
}
void fragment() {
    vec3 scanned_fabric = texture(fabric_albedo, UV).rgb;
    float weave = 0.025 * sin(UV.x * 330.0) * sin(UV.y * 278.0);
    vec3 canvas = mix(vec3(0.91, 0.83, 0.70), scanned_fabric, 0.22) + weave;
    float bar_x = 1.0 - smoothstep(0.055, 0.082, abs(UV.x - 0.5));
    float bar_y = 1.0 - smoothstep(0.060, 0.092, abs(UV.y - 0.49));
    float emblem = max(bar_x * smoothstep(0.18, 0.27, UV.y) *
                       (1.0 - smoothstep(0.76, 0.84, UV.y)),
                       bar_y * smoothstep(0.25, 0.33, UV.x) *
                       (1.0 - smoothstep(0.67, 0.75, UV.x)));
    ALBEDO = mix(canvas, vec3(0.49, 0.065, 0.073), emblem * 0.91);
    ROUGHNESS = 0.81;
    METALLIC = 0.0;
    NORMAL_MAP = texture(fabric_normal, UV).rgb;
    NORMAL_MAP_DEPTH = 0.22;
}
"""
	_fabric_material.shader = shader
	_fabric_material.set_shader_parameter("fabric_albedo", albedo_tex)
	_fabric_material.set_shader_parameter("fabric_normal", normal_tex)
	var width := clampf(ship_width * 0.31, 2.8, 7.2)
	var height := clampf((mast_top - lower) * 0.42, 3.0, 7.0)
	var sail_bottom := lower + (mast_top - lower) * 0.41
	for mast in range(2):
		var canvas := MeshInstance3D.new()
		canvas.name = "AnimatedPBRCanvas_%d" % mast
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j in range(16):
			for i in range(24):
				var a := Vector2(float(i) / 24.0, float(j) / 16.0)
				var b := Vector2(float(i + 1) / 24.0, float(j) / 16.0)
				var c := Vector2(float(i) / 24.0, float(j + 1) / 16.0)
				var d := Vector2(float(i + 1) / 24.0, float(j + 1) / 16.0)
				_canvas_vertex(surface, Vector3((a.x - 0.5) * width, a.y * height, 0.0), a)
				_canvas_vertex(surface, Vector3((b.x - 0.5) * width, b.y * height, 0.0), b)
				_canvas_vertex(surface, Vector3((c.x - 0.5) * width, c.y * height, 0.0), c)
				_canvas_vertex(surface, Vector3((b.x - 0.5) * width, b.y * height, 0.0), b)
				_canvas_vertex(surface, Vector3((d.x - 0.5) * width, d.y * height, 0.0), d)
				_canvas_vertex(surface, Vector3((c.x - 0.5) * width, c.y * height, 0.0), c)
		surface.generate_normals()
		canvas.mesh = surface.commit()
		canvas.material_override = _fabric_material
		canvas.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if absf(_ship_axis.x) > 0.5:
			canvas.position = Vector3((-0.19 + float(mast) * 0.38) * ship_width,
				sail_bottom + float(mast) * 0.32, 0.0)
		else:
			canvas.position = Vector3(0.0, sail_bottom + float(mast) * 0.32,
				(-0.19 + float(mast) * 0.38) * ship_width)
			canvas.rotation.y = PI * 0.5
		_rig.add_child(canvas)


func _run() -> void:
	_out_dir = OS.get_environment("IOM_AUDITION_FRAMES")
	if _out_dir.is_empty() or not _out_dir.is_absolute_path():
		_fail("IOM_AUDITION_FRAMES must be an absolute CI artifacts path")
		return
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_fail("Cannot create render evidence staging directory")
		return
	var asset: Resource = load(SHIP_PATH)
	if not asset is PackedScene:
		_fail("Genuine licensed ship model unavailable: " + SHIP_PATH)
		return
	_stage = Node3D.new()
	_stage.name = "NonProductionVesselReferenceAudition"
	root.add_child(_stage)
	_rig = Node3D.new()
	_rig.name = "TrueShipAndFabricMotion"
	_stage.add_child(_rig)
	_ship = (asset as PackedScene).instantiate() as Node3D
	if _ship == null:
		_fail("Imported vessel must be a Node3D scene")
		return
	_ship.name = "ActualPolyHavenPBRHullRigging"
	_rig.add_child(_ship)
	var base := {"min": Vector3(INF, INF, INF),
		"max": Vector3(-INF, -INF, -INF), "count": 0}
	_mesh_bounds(_ship, base)
	if base["count"] < 8:
		_fail("Empty imported PBR ship geometry")
		return
	var raw_extent: Vector3 = base["max"] - base["min"]
	var longest: float = maxf(raw_extent.x, maxf(raw_extent.y, raw_extent.z))
	if not is_finite(longest) or longest <= 0.1:
		_fail("Invalid model bounds")
		return
	var target_size := 26.0
	var factor := clampf(target_size / longest, 0.001, 50.0)
	_ship.scale = Vector3.ONE * factor
	_ship.position = -(base["min"] + base["max"]) * 0.5 * factor
	var ship_extent := raw_extent * factor
	_ship_axis = Vector2.RIGHT if raw_extent.x >= raw_extent.z else Vector2.DOWN
	var lower := -ship_extent.y * 0.5
	var upper := ship_extent.y * 0.5
	_waterline = lower + ship_extent.y * 0.25

	var env := WorldEnvironment.new()
	var color := Environment.new()
	color.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var atmosphere := ProceduralSkyMaterial.new()
	atmosphere.sky_top_color = Color("#4483bf")
	atmosphere.sky_horizon_color = Color("#d2e5eb")
	atmosphere.ground_horizon_color = Color("#9bc3cc")
	atmosphere.ground_bottom_color = Color("#146378")
	sky.sky_material = atmosphere
	color.sky = sky
	color.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	color.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	color.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = color
	_stage.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "NaturalDirectionalSun"
	sun.light_color = Color("#fff1d8")
	sun.light_energy = 1.7
	sun.rotation_degrees = Vector3(-51.0, -22.0, 0.0)
	sun.shadow_enabled = true
	_stage.add_child(sun)
	_setup_ocean()
	_setup_canvas_sails(target_size, upper, lower)
	_camera = Camera3D.new()
	_camera.name = "ContinuousReferenceTrackingCamera"
	_camera.fov = 48.0
	_stage.add_child(_camera)
	_camera.current = true
	for warmup in range(4):
		await process_frame
	await RenderingServer.frame_post_draw

	for frame in range(CAPTURE_FRAMES):
		var seconds := float(frame) / float(OUTPUT_FPS)
		var t := float(frame) / float(CAPTURE_FRAMES - 1)
		var eased := t * t * (3.0 - 2.0 * t)
		_rig.rotation_degrees = Vector3(sin(seconds * 1.55) * 0.55,
			sin(seconds * 0.44) * 1.0, sin(seconds * 1.1) * 0.70)
		_rig.position.y = sin(seconds * 1.75) * 0.13
		_rig.position.x = eased * 0.75
		_sea_material.set_shader_parameter("water_phase", seconds * 1.1)
		_sea_material.set_shader_parameter("ship_origin", Vector2(_rig.position.x, 0.0))
		_fabric_material.set_shader_parameter("fabric_phase", seconds * 1.8)
		var orbit := -0.47 + eased * 0.43
		var framed := false
		for attempt in range(12):
			var distance := 22.0 * (1.0 + float(attempt) * 0.11)
			_camera.position = Vector3(sin(orbit) * distance,
				maxf(3.6, ship_extent.y * 0.29) + t * 0.95,
				cos(orbit) * distance)
			_camera.look_at(Vector3(_rig.position.x, 1.4, 0.0), Vector3.UP)
			await process_frame
			if _all_rendered_meshes_visible():
				framed = true
				break
		if not framed:
			_fail("Cannot frame complete ship geometry (mast/rigging/animated sail clipped) on frame %d" % frame)
			return
		await RenderingServer.frame_post_draw
		var image: Image = root.get_viewport().get_texture().get_image()
		if image == null or image.is_empty() or image.get_width() < 1280:
			_fail("Frame %d missing real Godot pixels" % frame)
			return
		var image_path := "%s/frame_%03d.png" % [_out_dir, frame]
		if image.save_png(image_path) != OK:
			_fail("Failed real renderer frame write " + image_path)
			return
		if frame == 72 or frame == 120 or frame == 192:
			if image.save_png(_out_dir.path_join("candidate_still.png" if frame == 120 else "candidate_%03d.png" % frame)) != OK:
				_fail("Failed cinematic keyframe evidence")
				return
	print("GODOT_REFERENCE_AUDITION: %d frames at %d fps; artist acceptance NOT VERIFIED" % [CAPTURE_FRAMES, OUTPUT_FPS])
	_stage.queue_free()
	quit(0)
