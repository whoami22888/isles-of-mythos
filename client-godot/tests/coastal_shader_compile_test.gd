extends SceneTree
## Render the actual coastal slice once with the selected Mobile renderer so
## affected terrain, ocean and ship-effect shaders pass through Godot's GPU
## compiler rather than only being parsed as resources.

const SCENE_PATH := "res://scenes/realistic_coastal_fx_slice.tscn"


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		push_error("Coastal shader compile fixture failed to load")
		quit(1)
		return
	var scene := packed.instantiate() as Node3D
	root.add_child(scene)
	for _frame in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var shader_surfaces := 0
	var pending: Array[Node] = [scene]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D:
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.mesh != null:
				for surface in range(mesh_instance.mesh.get_surface_count()):
					var material := mesh_instance.get_active_material(surface) as ShaderMaterial
					if material != null and material.shader != null and not material.shader.code.is_empty():
						shader_surfaces += 1
		for child in node.get_children():
			pending.append(child)
	var image := root.get_viewport().get_texture().get_image()
	var rendered := image != null and not image.is_empty()
	scene.free()
	await process_frame
	if shader_surfaces < 2 or not rendered:
		push_error("Expected compiled coastal terrain/ocean shaders and a rendered Mobile frame (surfaces=%d, rendered=%s)" % [shader_surfaces, rendered])
		quit(1)
		return
	print("Coastal Mobile shader compile/render: %d shader surfaces rendered" % shader_surfaces)
	quit(0)
