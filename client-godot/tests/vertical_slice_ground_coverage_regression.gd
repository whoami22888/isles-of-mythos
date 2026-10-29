extends SceneTree

# Regression: the scaffold ground was a fixed 64x64 plane at the origin while the camera and player follow
# the authoritative position, so an account restored away from the origin saw no ground. The ground must keep
# covering the player's whole chunk plus a one-chunk margin wherever the server places the player.

const Scene = preload("res://gameplay/vertical_slice.tscn")
const CHUNK_SIZE := 32.0

func _init() -> void:
	var world = Scene.instantiate()
	root.add_child(world)
	await process_frame
	var ground := _find_ground(world)
	_assert(ground != null, "scaffold ground exists")
	if ground == null:
		quit(1)
		return
	var positions := [
		Vector2(0, 0), Vector2(31.9, 31.9), Vector2(-0.1, -0.1), Vector2(500, -300),
		Vector2(-1000, 5000), Vector2(123456, -98765), Vector2(-32, -32), Vector2(64, 0),
	]
	for p in positions:
		world._on_player_state({"x": p.x, "y": p.y})
		await process_frame
		_assert_covers(ground, p)
	# Walking across chunk boundaries keeps coverage without ever uncovering the player.
	for step in range(0, 200):
		var p := Vector2(float(step) * 1.7 - 60.0, float(step) * -2.3 + 40.0)
		world._on_player_state({"x": p.x, "y": p.y})
		_assert_covers(ground, p)
	world.queue_free()
	await process_frame
	quit(0)

func _find_ground(world: Node) -> MeshInstance3D:
	for child in world.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is PlaneMesh:
			return child
	return null

func _assert_covers(ground: MeshInstance3D, p: Vector2) -> void:
	var plane := ground.mesh as PlaneMesh
	var half := plane.size / 2.0
	var center := Vector2(ground.position.x, ground.position.z)
	var chunk := Vector2(floorf(p.x / CHUNK_SIZE), floorf(p.y / CHUNK_SIZE))
	var chunk_min := chunk * CHUNK_SIZE - Vector2(CHUNK_SIZE, CHUNK_SIZE)
	var chunk_max := (chunk + Vector2.ONE) * CHUNK_SIZE + Vector2(CHUNK_SIZE, CHUNK_SIZE)
	var ok := chunk_min.x >= center.x - half.x and chunk_max.x <= center.x + half.x \
		and chunk_min.y >= center.y - half.y and chunk_max.y <= center.y + half.y
	_assert(ok, "ground covers player chunk + 1-chunk margin at (%s, %s); ground center %s size %s" % [p.x, p.y, center, plane.size])

func _assert(condition: bool, label: String) -> void:
	if not condition:
		push_error("ground coverage regression failed: " + label)
		quit(1)
