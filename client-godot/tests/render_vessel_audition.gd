extends SceneTree
## Internal NON-PRODUCTION candidate only, never an accepted gameplay render.
## Real Godot 4.7.2 frames, never synthetic still animation.

const SHIP_PATH := "res://assets/world_audition/ship/dutch_ship_medium_1k.gltf"
const CAPTURE_FRAMES := 30
var _stage: Node3D
var _ship: Node3D
var _camera: Camera3D
var _out_dir: String

func _initialize() -> void:
	call_deferred("_run")

func _fail(reason: String) -> void:
	push_error(reason)
	quit(1)

func _mesh_bounds(node: Node, minmax: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null:
			var aabb := mesh_node.mesh.get_aabb()
			for i in range(8):
				var p := mesh_node.to_global(aabb.get_endpoint(i))
				minmax["min"] = minmax["min"].min(p)
				minmax["max"] = minmax["max"].max(p)
				minmax["count"] = minmax["count"] + 1
	for child in node.get_children():
		_mesh_bounds(child, minmax)

func _run() -> void:
	_out_dir = OS.get_environment("IOM_AUDITION_FRAMES")
	if _out_dir.is_empty() or not _out_dir.is_absolute_path():
		_fail("IOM_AUDITION_FRAMES must be an absolute CI artifacts path")
		return
	if DirAccess.make_dir_recursive_absolute(_out_dir) != OK:
		_fail("Cannot create immutable evidence staging directory")
		return
	var asset: Resource = load(SHIP_PATH)
	if not asset is PackedScene:
		_fail("Genuine imported ship model unavailable: " + SHIP_PATH)
		return
	_stage = Node3D.new()
	_stage.name = "PremiumShipAuditionIsolation"
	root.add_child(_stage)
	_ship = (asset as PackedScene).instantiate() as Node3D
	if _ship == null:
		_fail("Imported ship is not a Node3D scene")
		return
	_ship.name = "ImportedOriginalPolyHavenVessel"
	_stage.add_child(_ship)
	var base_bounds := {"min": Vector3(INF, INF, INF),
		"max": Vector3(-INF, -INF, -INF), "count": 0}
	_mesh_bounds(_ship, base_bounds)
	if base_bounds["count"] < 8:
		_fail("Empty imported ship geometry")
		return
	var extent: Vector3 = base_bounds["max"] - base_bounds["min"]
	var longest: float = maxf(extent.x, maxf(extent.y, extent.z))
	if not is_finite(longest) or longest <= 0.1:
		_fail("Invalid real model bounds")
		return
	var target_size := 22.0
	var factor := clampf(target_size / longest, 0.001, 50.0)
	_ship.scale = Vector3.ONE * factor
	_ship.position = -(base_bounds["min"] + base_bounds["max"]) * 0.5 * factor

	var env_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var backdrop := ProceduralSkyMaterial.new()
	backdrop.sky_top_color = Color("#285071")
	backdrop.sky_horizon_color = Color("#93b7b6")
	backdrop.ground_horizon_color = Color("#718794")
	backdrop.ground_bottom_color = Color("#1c2b38")
	sky.sky_material = backdrop
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = environment
	_stage.add_child(env_node)
	var key := DirectionalLight3D.new()
	key.name = "AuditionKeyOnly"
	key.light_color = Color("#fff4e1")
	key.light_energy = 1.2
	key.rotation_degrees = Vector3(-42.0, -20.0, 0.0)
	key.shadow_enabled = true
	_stage.add_child(key)

	_camera = Camera3D.new()
	_camera.name = "InternalCinematicCamera"
	_camera.fov = 42.0
	_stage.add_child(_camera)
	_camera.current = true
	for warmup in range(3):
		await process_frame
	await RenderingServer.frame_post_draw

	var distance := maxf(24.0, target_size * 1.65)
	for frame in range(CAPTURE_FRAMES):
		var t: float = float(frame) / float(CAPTURE_FRAMES - 1)
		var orbit := -0.37 + t * 0.88
		_ship.rotation_degrees = Vector3(sin(t * TAU * 0.90) * 0.85,
			sin(t * TAU * 0.48) * 1.3, sin(t * TAU * 0.8) * 1.1)
		_ship.position.y = sin(t * TAU * 1.25) * 0.06
		_camera.position = Vector3(sin(orbit) * distance,
			maxf(5.5, target_size * 0.21) + t * 2.2,
			cos(orbit) * distance)
		_camera.look_at(Vector3.ZERO, Vector3.UP)
		await process_frame
		await RenderingServer.frame_post_draw
		var capture: Image = root.get_viewport().get_texture().get_image()
		if capture == null or capture.is_empty() or capture.get_width() < 640:
			_fail("No valid engine-rendered pixel data on frame %d" % frame)
			return
		var path := "%s/frame_%03d.png" % [_out_dir, frame]
		if capture.save_png(path) != OK:
			_fail("Cannot save true Godot engine frame " + path)
			return
		if frame == int(CAPTURE_FRAMES / 2):
			if capture.save_png(_out_dir.path_join("candidate_still.png")) != OK:
				_fail("Cannot save actual Godot still")
				return
	print("INTERNAL_GODOT_CAPTURE: %d frames; real source model; visual quality NOT VERIFIED" % CAPTURE_FRAMES)
	_stage.queue_free()
	quit(0)
