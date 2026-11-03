extends SceneTree
## Headless-friendly capture of the opening battle. Not a CI gate.
## IOM_OPENING_POSE=deck|broadside|leviathan
## IOM_OPENING_SHOT=/absolute/path.png

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var pose := OS.get_environment("IOM_OPENING_POSE")
	if pose.is_empty():
		pose = "deck"
	var output := OS.get_environment("IOM_OPENING_SHOT")
	if output.is_empty():
		output = "user://opening-battle.png"
	var packed = load("res://gameplay/opening_battle.tscn")
	if packed == null:
		push_error("Opening battle scene failed to load")
		quit(1)
		return
	var battle = packed.instantiate()
	root.add_child(battle)
	current_scene = battle
	for _i in 24:
		await process_frame
		await RenderingServer.frame_post_draw
	if battle.has_method("capture_pose"):
		battle.capture_pose(pose)
	for _i in 8:
		await process_frame
		await RenderingServer.frame_post_draw
	var image: Image = root.get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Opening capture produced an empty image")
		quit(1)
		return
	var error := image.save_png(output)
	if error != OK:
		push_error("Opening capture could not be saved")
		quit(1)
		return
	print("Opening capture wrote %s (%dx%d)" % [output, image.get_width(), image.get_height()])
	quit(0)
