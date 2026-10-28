extends SceneTree

# Renders the boot and world screens to PNG for visual review. Needs a display (run under xvfb-run).
# Output: the directory given by the IOM_SHOT_DIR environment variable.

const WorldScene = preload("res://scenes/world.tscn")

func _init() -> void:
	call_deferred("run")

func _save(name: String) -> void:
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	var dir := OS.get_environment("IOM_SHOT_DIR")
	var path := dir.path_join(name)
	var err := image.save_png(path)
	print("SHOT %s err=%s size=%sx%s" % [path, err, image.get_width(), image.get_height()])

func run() -> void:
	root.size = Vector2i(1280, 720)
	var boot: Node = load("res://scenes/boot.tscn").instantiate()
	root.add_child(boot)
	await _save("boot_login.png")
	boot.get_node("Panel/Margin/Content/ModeRow/RegisterMode").button_pressed = true
	boot.call("_set_mode", "register")
	await _save("boot_register.png")
	boot.get_node("Panel").visible = false  # mirrors boot._enter_world
	var world: IslesWorldScreen = WorldScene.instantiate()
	root.add_child(world)
	world.size = Vector2(1280.0, 720.0)
	var stick: IslesTouchJoystick = world.get_node("Joystick")
	stick._offset = Vector2(stick.size.x * 0.3, -stick.size.y * 0.1)
	stick.queue_redraw()
	await _save("world_joystick.png")
	quit(0)
