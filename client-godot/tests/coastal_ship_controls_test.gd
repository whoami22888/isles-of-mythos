extends SceneTree
## Regression for player-facing start, skip and reduced-motion controls on
## the real coastal preview scene.

const SCENE_PATH := "res://scenes/realistic_coastal_fx_slice.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("Coastal ship controls fixture failed to load")
		quit(1)
		return
	var scene := packed.instantiate() as Node3D
	root.add_child(scene)
	await process_frame
	await process_frame
	var vessel := scene.get_node_or_null("HarbourShipFocalPoint") as Node3D
	var controller := scene.get_node_or_null("CoastalShipEffects")
	if vessel == null or controller == null or not controller.components_ready():
		push_error("Coastal ship controls require the real vessel and movement controller")
		scene.free()
		quit(1)
		return
	var anchor := vessel.position
	scene.play_cinematic()
	if not scene._cinematic_active or not scene.cinematic_camera.current:
		push_error("Starting the reveal must select the cinematic camera")
		scene.free()
		quit(1)
		return
	Input.action_press("ui_cancel")
	scene._process(1.0 / 60.0)
	Input.action_release("ui_cancel")
	if scene._cinematic_active or not scene.gameplay_camera.current:
		push_error("Cancel input must skip the reveal and restore gameplay view")
		scene.free()
		quit(1)
		return
	controller.start_visual_demo()
	controller.advance_visual_demo(0.25)
	var moved := vessel.position.distance_to(anchor) > 0.1
	controller.stop_visual_demo()
	var restored := vessel.position.distance_to(anchor) < 0.001
	scene.play_cinematic(true)
	var reduced_motion := not scene._cinematic_active and scene.gameplay_camera.current
	scene.free()
	await process_frame
	if not moved or not restored or not reduced_motion:
		push_error("Ship movement, skip restore and reduced-motion route must all pass")
		quit(1)
		return
	print("Coastal ship controls: movement, cancel skip and reduced motion pass")
	quit(0)
