class_name IslesWorldContentDirector
extends Node3D
## Visual-only presentation from authoritative snapshots. No local enemy spawns,
## damage, capture, item drops or economy mutations; missing premium art stays hidden.

const CATALOG_PATH := "res://content/world_population.json"
const MAX_VISIBLE := 20
const MAX_DISTANCE := 160.0
const NEAR_DISTANCE := 35.0

var _catalog: Dictionary = {}
var _slots: Dictionary = {}
var _assets: Dictionary = {}
var _spawned: Dictionary = {}
var _last_plan: Array[Dictionary] = []


func _ready() -> void:
	load_catalog()


func load_catalog() -> bool:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		push_error("World content catalog unavailable")
		return false
	var decoded: Variant = JSON.parse_string(file.get_as_text())
	if not decoded is Dictionary or decoded.get("schema_version") != 1:
		push_error("Invalid world content schema")
		return false
	_catalog = decoded
	_slots.clear()
	_assets.clear()
	for slot in _catalog.get("archetypes", []):
		if slot is Dictionary and slot.has("id") and slot.has("kind"):
			_slots[slot["id"]] = slot
	for asset in _catalog.get("asset_records", []):
		if asset is Dictionary and _admitted(asset):
			_assets[asset["id"]] = asset
	return true


func _admitted(asset: Dictionary) -> bool:
	if asset.get("status") != "approved" or asset.get("visual_review") != "approved":
		return false
	if asset.get("pbr") != true or int(asset.get("lod_levels", 0)) < 2:
		return false
	var digest: String = str(asset.get("sha256", ""))
	if digest.length() != 64 or not digest.is_valid_hex_number():
		return false
	var relative: String = str(asset.get("path", ""))
	if relative.is_empty() or relative.begins_with("/") or relative.contains("..") or relative.contains("\\"):
		return false
	# Full byte-for-byte SHA and legal admission are verified by the Python
	# build-time content pipeline. The runtime refuses missing Godot resources.
	return ResourceLoader.exists("res://assets/world_content/" + relative)


func candidate_count() -> int:
	return (_catalog.get("archetypes", []) as Array).size()


func scenario_count() -> int:
	return (_catalog.get("encounter_shots", []) as Array).size()


func available_visual_count() -> int:
	return _assets.size()


func _position(value: Variant) -> Vector3:
	if not value is Array or value.size() != 3:
		return Vector3(INF, INF, INF)
	for component in value:
		if not (component is float or component is int) or not is_finite(float(component)):
			return Vector3(INF, INF, INF)
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func plan_snapshot(snapshots: Array, camera_position: Vector3) -> Array[Dictionary]:
	## Returns an immutable-use plan sorted by proximity/id, independent of
	## packet order. Admission and distance budgets prevent low-quality fallback.
	var options: Array[Dictionary] = []
	var seen: Dictionary = {}
	if not camera_position.is_finite():
		return []
	for packet in snapshots:
		if not packet is Dictionary:
			continue
		var uid: String = str(packet.get("id", ""))
		if uid.is_empty() or seen.has(uid):
			continue
		seen[uid] = true
		var slot: Dictionary = _slots.get(packet.get("archetype", ""), {})
		var asset: Dictionary = _assets.get(slot.get("asset_id", ""), {})
		if asset.is_empty():
			continue
		var position := _position(packet.get("position", null))
		if not position.is_finite():
			continue
		var distance_squared := position.distance_squared_to(camera_position)
		if distance_squared > MAX_DISTANCE * MAX_DISTANCE:
			continue
		options.append({"id": uid, "position": position, "asset": asset,
			"kind": slot.get("kind", ""), "distance_squared": distance_squared})
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["distance_squared"] == b["distance_squared"]:
			return str(a["id"]) < str(b["id"])
		return a["distance_squared"] < b["distance_squared"])
	var plan: Array[Dictionary] = []
	for index in range(mini(options.size(), MAX_VISIBLE)):
		var option: Dictionary = options[index]
		plan.append({"id": option["id"], "position": option["position"],
			"path": "res://assets/world_content/" + option["asset"]["path"],
			"lod_hint": 0 if option["distance_squared"] <= NEAR_DISTANCE * NEAR_DISTANCE else 1,
			"kind": option["kind"]})
	_last_plan = plan
	return plan


func apply_visual_snapshot(snapshots: Array, camera_position: Vector3) -> int:
	## Only display graphics for server-provided entities. Never infer presence
	## of enemies or loot from biome/clock/time-of-day catalogue entries.
	var plan := plan_snapshot(snapshots, camera_position)
	var keep: Dictionary = {}
	for option in plan:
		var uid: String = option["id"]
		keep[uid] = true
		if _spawned.has(uid):
			var existing: Node3D = _spawned[uid]
			if is_instance_valid(existing):
				existing.position = option["position"]
				continue
		var packed: Resource = load(option["path"])
		if not packed is PackedScene:
			continue
		var instance: Node = packed.instantiate()
		var node := instance as Node3D
		if node == null:
			instance.queue_free()
			continue
		add_child(node)
		node.position = option["position"]
		_spawned[uid] = node
	for uid in _spawned.keys():
		if not keep.has(uid):
			if is_instance_valid(_spawned[uid]):
				_spawned[uid].queue_free()
			_spawned.erase(uid)
	return _spawned.size()


func clear_visuals() -> void:
	for uid in _spawned.keys():
		if is_instance_valid(_spawned[uid]):
			_spawned[uid].queue_free()
	_spawned.clear()
	_last_plan.clear()
