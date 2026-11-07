extends SceneTree

# Regression: the playable vertical slice rendered the player on a flat scaffold plane. It must mount the
# coastal bay (atmosphere, terrain, ocean, dressing) as its visual world, keep the server x/y -> world x/z
# mapping unchanged, and stand the player and resource markers on the rendered terrain height.

const Scene = preload("res://gameplay/vertical_slice.tscn")
const ShoreBaker = preload("res://scripts/coastal_shore_heightfield.gd")
const MESH_TOLERANCE := 0.4
var failures := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error("coastal world regression failed: " + label)

func run() -> void:
	var world = Scene.instantiate()
	root.add_child(world)
	await process_frame
	var coastal := world.get_node_or_null("CoastalWorld") as Node3D
	check(coastal != null, "coastal world is mounted without an authenticated handoff")
	if coastal == null:
		quit(1)
		return
	for path in ["CoastalAtmosphere", "WarmSun", "IrregularCoastalTerrain", "ShallowToDeepWater", "TropicalBayDressing"]:
		check(coastal.get_node_or_null(path) != null, "coastal world provides %s" % path)
	var scaffold := world.get_node_or_null("ScaffoldGround") as MeshInstance3D
	check(scaffold != null and not scaffold.visible, "flat scaffold ground is hidden")
	check((world.get_node("Camera") as Camera3D).current, "the slice's follow camera stays current")
	check(world.get_node_or_null("Interface/TouchControls") != null, "touch controls stay mounted")
	# Owner rendering review on #279: the gameplay mount forced every
	# DirectionalLight3D's shadows off, overriding the bay's quality tier. In the
	# mounted gameplay world the S23-class default must keep WarmSun shadows,
	# and an explicit lower tier must still be able to turn them off.
	var sun := coastal.get_node("WarmSun") as DirectionalLight3D
	var default_quality := OS.get_environment("IOM_VISUAL_QUALITY").to_lower()
	if default_quality in ["", "high"]:
		check(sun.shadow_enabled, "mounted gameplay keeps WarmSun shadows at the default high tier")
	coastal.apply_visual_quality(0)
	check(not sun.shadow_enabled, "an explicit low tier still disables WarmSun shadows in gameplay")
	coastal.apply_visual_quality(2)
	check(sun.shadow_enabled, "the high tier restores WarmSun shadows in gameplay")
	var terrain := coastal.get_node("IrregularCoastalTerrain") as MeshInstance3D
	var player := world.get_node("ServerPlayerRepresentation") as Node3D
	# Beach, cliff top and open water in chunk (0, 0), then a far chunk the bay is relocated to.
	var heights := {}
	for server in [Vector2(16, 12), Vector2(16, 27), Vector2(16, 3), Vector2(100.5, -40.0)]:
		world._on_player_state({"x": server.x, "y": server.y})
		await process_frame
		check(is_equal_approx(player.position.x, server.x) and is_equal_approx(player.position.z, server.y),
			"server (%s) maps to world x/z unchanged, got %s" % [server, player.position])
		var terrain_y: float = coastal.terrain_height_at(server.x, server.y)
		var water_y: float = coastal.water_level()
		var feet: float = player.position.y - world.PLAYER_HALF_HEIGHT
		check(is_equal_approx(feet, maxf(terrain_y, water_y - world.WADE_DEPTH)),
			"player feet follow terrain/water at %s: feet %.3f terrain %.3f water %.3f" % [server, feet, terrain_y, water_y])
		# Independent of the height equation: sample the rendered terrain mesh where the bay now sits.
		var baked: Dictionary = ShoreBaker.bake(terrain, 96, 72)
		check(not baked.has("error"), "terrain mesh bakes at %s" % [server])
		if not baked.has("error"):
			var mesh_y := ShoreBaker.sample_height(baked, server)
			check(absf(mesh_y - terrain_y) <= MESH_TOLERANCE,
				"terrain query matches the rendered mesh at %s: mesh %.3f query %.3f" % [server, mesh_y, terrain_y])
			var bound: Vector2 = (coastal.get_node("ShallowToDeepWater") as MeshInstance3D).material_override.get_shader_parameter("shore_origin_xz")
			check(bound.is_equal_approx(baked["origin"]), "ocean shoreline map follows the relocated bay, got %s want %s" % [bound, baked["origin"]])
		heights[server] = feet
		print("server %s -> world %s (terrain %.2f, water %.2f)" % [server, player.position, terrain_y, water_y])
	check(heights[Vector2(16, 27)] - heights[Vector2(16, 12)] > 2.0,
		"cliff top stands clearly above the beach: %.2f vs %.2f" % [heights[Vector2(16, 27)], heights[Vector2(16, 12)]])
	check(heights[Vector2(16, 3)] < heights[Vector2(16, 12)], "open water position wades below the beach")
	# Resource markers rest on the surface at their server position.
	world._on_player_state({"x": 16.0, "y": 12.0})
	world._on_world_chunk("", {"x": 0, "y": 0, "resources": [
		{"id": "wood:a", "type": "wood", "x": 10.0, "y": 22.0},
		{"id": "stone:b", "type": "stone", "x": 20.0, "y": 4.0},
	]})
	for entry in [["wood:a", Vector2(10, 22)], ["stone:b", Vector2(20, 4)]]:
		var marker: Node3D = world._markers[entry[0]]
		var surface: float = maxf(coastal.terrain_height_at(entry[1].x, entry[1].y), coastal.water_level())
		check(is_equal_approx(marker.position.y, surface + world.MARKER_RADIUS)
			and is_equal_approx(marker.position.x, entry[1].x) and is_equal_approx(marker.position.z, entry[1].y),
			"marker %s rests on the surface at its server position, got %s surface %.3f" % [entry[0], marker.position, surface])
	# A tap on the player's feet resolves to the terrain point under them, not to the y = 0 plane.
	var camera := world.get_node("Camera") as Camera3D
	var feet_point: Vector3 = player.position - Vector3(0, world.PLAYER_HALF_HEIGHT, 0)
	var hit = world._ground_point(camera.unproject_position(feet_point))
	check(hit is Vector3 and Vector2(hit.x - feet_point.x, hit.z - feet_point.z).length() < 0.3,
		"tap ray hits the terrain under the player, got %s want %s" % [hit, feet_point])
	# Composition at the default follow camera, at the fixture position the
	# gameplay evidence capture uses (render_vertical_slice_gameplay.gd): the
	# player's feet and head are inside the view and the avatar is tall enough
	# to read (the old 37 m camera drew it ~15 px tall at 720p). Ship framing
	# depends on where the player stands inside the chunk, so it is judged from
	# the real-render evidence frames, not asserted here.
	# Same 1280x720 landscape frame as the capture (headless defaults to a square window).
	root.size = Vector2i(1280, 720)
	world._enter_gameplay_hud()
	world._on_player_state({"x": 10.0, "y": 11.0})
	for _i in 3:
		await process_frame
	world._follow_camera()
	var feet_now: Vector3 = player.position - Vector3(0, world.PLAYER_HALF_HEIGHT, 0)
	var head_now: Vector3 = feet_now + Vector3(0, 1.8, 0)
	check(camera.is_position_in_frustum(feet_now) and camera.is_position_in_frustum(head_now), "the player is fully inside the gameplay view")
	var screen_height := root.get_visible_rect().size.y
	var avatar_px := absf(camera.unproject_position(feet_now).y - camera.unproject_position(head_now).y) * 720.0 / screen_height
	check(avatar_px >= 28.0, "avatar is at least 28 px tall at 720p, got %.1f" % avatar_px)
	world.queue_free()
	await process_frame
	if failures > 0:
		quit(1)
		return
	print("vertical slice coastal world regression: PASS")
	quit(0)
