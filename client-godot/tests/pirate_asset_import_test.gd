extends SceneTree
## Godot 4.7.2 import smoke test for the admitted GLTF payloads.

func _init() -> void:
	for path in [
		"res://assets/pirate-kit/Ship_Small.gltf",
		"res://assets/pirate-kit/Characters_Skeleton.gltf",
		"res://assets/pirate-kit/Characters_Shark.gltf",
	]:
		var packed := load(path) as PackedScene
		if packed == null:
			push_error("Godot could not import admitted asset: %s" % path)
			quit(1)
			return
		var instance := packed.instantiate()
		if instance == null:
			push_error("Godot could not instantiate admitted asset: %s" % path)
			quit(1)
			return
		instance.free()
	print("PASS Godot imported all admitted GLTF pirate assets")
	quit(0)
