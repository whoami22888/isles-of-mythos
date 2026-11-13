extends SceneTree
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var scene = load("res://gameplay/ashore/washed_ashore.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.skip_cinematic()
	var p: Node3D = scene._player
	p.position = Vector3(-10, 0, 4.5)
	p.position.y = scene._ground_y(-10, 4.5)
	var why := {}
	for i in 200:
		var a := randf() * TAU
		var d := randf_range(3.5, 9.0)
		var q: Vector3 = p.global_position + Vector3(cos(a), 0, sin(a)) * d
		q.y = scene._ground_y(q.x, q.z)
		var r := "ok"
		if q.y < scene._water_y + 0.4: r = "water"
		elif q.y - p.global_position.y > 2.0: r = "high"
		elif scene._slope_at(q.x, q.z, 0.6) > 0.5: r = "slope"
		else:
			for node in scene._nodes:
				if scene._flat((node.get("root") as Node3D).global_position, q) < 1.8:
					r = "node"
					break
		why[r] = why.get(r, 0) + 1
	print("WHY ", why, " py ", p.global_position)
	quit(0)
