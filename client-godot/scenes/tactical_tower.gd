extends Node3D
class_name TacticalTower
## Prompt 017: tactical defense tower aggro, aim, and attack signalling.
##
## Presentation and intent only. The server owns whether a shot lands and the
## invader's actual health. This node detects the closest invader in an Area3D
## range, yaws the barrel toward them, and emits `attack_fired` on cooldown
## with the elemental damage multiplier applied to a proposed damage value.
## It never writes invader health itself.

signal target_acquired(target: Node3D)
signal target_lost
signal attack_fired(target: Node3D, payload: Dictionary)

const INVADER_GROUP := "tactical_invaders"

## Same four elements as MythosCreature / the companion contract.
enum Element { WATER, FIRE, EARTH, AIR }

## Advantage cycle: Fire > Earth > Air > Water > Fire. Reverse is resisted.
const ELEMENT_ADVANTAGE := 1.5
const ELEMENT_RESIST := 1.0 / 1.5

@export var attack_range: float = 12.0:
	set(value):
		attack_range = maxf(0.1, value)
		_sync_range_shape()

@export var attack_cooldown: float = 1.0
@export var base_damage: float = 10.0
@export var element: Element = Element.FIRE
@export var barrel_yaw_speed: float = 8.0
@export var invader_collision_mask: int = 1
@export var auto_tick: bool = true

var current_target: Node3D = null

var _area: Area3D
var _shape: CollisionShape3D
var _sphere: SphereShape3D
var _barrel: Node3D
var _cooldown_left: float = 0.0


func _ready() -> void:
	_ensure_nodes()
	_sync_range_shape()
	set_physics_process(auto_tick)


func _physics_process(delta: float) -> void:
	tick(delta)


## Advance cooldown, acquire the closest invader, yaw the barrel, and fire.
func tick(delta: float) -> void:
	_ensure_nodes()
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	var next := find_closest_invader()
	if next != current_target:
		current_target = next
		if current_target:
			target_acquired.emit(current_target)
		else:
			target_lost.emit()
	if current_target and is_instance_valid(current_target):
		aim_barrel_at(current_target, delta)
		if _cooldown_left <= 0.0:
			fire_at(current_target)
	else:
		current_target = null


func find_closest_invader() -> Node3D:
	_ensure_nodes()
	var best: Node3D = null
	var best_dist := INF
	for candidate in _candidates():
		if not is_instance_valid(candidate) or not (candidate is Node3D):
			continue
		if not is_in_range(candidate):
			continue
		var dist := global_position.distance_to((candidate as Node3D).global_position)
		if dist < best_dist:
			best_dist = dist
			best = candidate
	return best


func is_in_range(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	return global_position.distance_to(node.global_position) <= attack_range + 0.0001


## Yaw only (Y-axis) so the barrel faces the target on the XZ plane.
func aim_barrel_at(target: Node3D, delta: float = 1.0) -> void:
	_ensure_nodes()
	if target == null or not is_instance_valid(target):
		return
	var offset := target.global_position - _barrel.global_position
	offset.y = 0.0
	if offset.length_squared() < 0.000001:
		return
	var desired := atan2(offset.x, offset.z)
	var current := _barrel.rotation.y
	var max_step := barrel_yaw_speed * maxf(delta, 0.0)
	if max_step <= 0.0 or is_inf(barrel_yaw_speed):
		_barrel.rotation.y = desired
	else:
		_barrel.rotation.y = lerp_angle(current, desired, clampf(max_step / PI, 0.0, 1.0))


func fire_at(target: Node3D) -> Dictionary:
	if target == null or not is_instance_valid(target) or not is_in_range(target):
		return {}
	var defender := invader_element(target)
	var multiplier := elemental_multiplier(element, defender)
	var payload := {
		"base_damage": base_damage,
		"multiplier": multiplier,
		"damage": base_damage * multiplier,
		"attacker_element": element_name(element),
		"defender_element": element_name(defender),
	}
	_cooldown_left = maxf(0.0, attack_cooldown)
	attack_fired.emit(target, payload)
	return payload


## Fire advantage over Earth is 1.5× (prompt example). The same cycle is used
## for the other pairs; the reverse is resisted (1 / 1.5). Same-element is 1×.
static func elemental_multiplier(attacker: Element, defender: Element) -> float:
	if attacker == _beats(defender):
		return ELEMENT_ADVANTAGE
	if defender == _beats(attacker):
		return ELEMENT_RESIST
	return 1.0


static func _beats(defender: Element) -> Element:
	match defender:
		Element.EARTH:
			return Element.FIRE
		Element.AIR:
			return Element.EARTH
		Element.WATER:
			return Element.AIR
		Element.FIRE:
			return Element.WATER
		_:
			return defender


static func element_name(value: Element) -> String:
	match value:
		Element.WATER:
			return "water"
		Element.FIRE:
			return "fire"
		Element.EARTH:
			return "earth"
		Element.AIR:
			return "air"
		_:
			return "unknown"


static func parse_element(value) -> Element:
	if value is Element:
		return value
	if value is int:
		return clampi(value, 0, 3) as Element
	var key := str(value).strip_edges().to_lower()
	match key:
		"water":
			return Element.WATER
		"fire":
			return Element.FIRE
		"earth":
			return Element.EARTH
		"air":
			return Element.AIR
		_:
			return Element.EARTH


func invader_element(node: Node) -> Element:
	if node == null:
		return Element.EARTH
	if node.has_method("get_element"):
		return parse_element(node.call("get_element"))
	if "element" in node:
		return parse_element(node.get("element"))
	if node.has_meta("element"):
		return parse_element(node.get_meta("element"))
	return Element.EARTH


func get_barrel() -> Node3D:
	_ensure_nodes()
	return _barrel


func get_detection_area() -> Area3D:
	_ensure_nodes()
	return _area


func _candidates() -> Array:
	var seen: Dictionary = {}
	var out: Array = []
	if _area != null:
		for body in _area.get_overlapping_bodies():
			if body is Node3D and not seen.has(body):
				seen[body] = true
				out.append(body)
		for area in _area.get_overlapping_areas():
			var owner: Node = area
			if area.get_parent() is Node3D:
				owner = area.get_parent()
			if owner is Node3D and not seen.has(owner):
				seen[owner] = true
				out.append(owner)
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group(INVADER_GROUP):
			if node is Node3D and not seen.has(node):
				seen[node] = true
				out.append(node)
	return out


func _ensure_nodes() -> void:
	if _area == null or not is_instance_valid(_area):
		_area = get_node_or_null("DetectionArea") as Area3D
		if _area == null:
			_area = Area3D.new()
			_area.name = "DetectionArea"
			add_child(_area)
		_area.monitoring = true
		_area.monitorable = false
		_area.collision_layer = 0
		_area.collision_mask = invader_collision_mask
	if _shape == null or not is_instance_valid(_shape):
		_shape = _area.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if _shape == null:
			_shape = CollisionShape3D.new()
			_shape.name = "CollisionShape3D"
			_area.add_child(_shape)
	if _sphere == null or not is_instance_valid(_sphere):
		_sphere = _shape.shape as SphereShape3D
		if _sphere == null:
			_sphere = SphereShape3D.new()
			_shape.shape = _sphere
	if _barrel == null or not is_instance_valid(_barrel):
		_barrel = get_node_or_null("Barrel") as Node3D
		if _barrel == null:
			_barrel = Node3D.new()
			_barrel.name = "Barrel"
			add_child(_barrel)
			var mesh := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.3, 0.3, 1.4)
			mesh.mesh = box
			mesh.position = Vector3(0.0, 0.6, 0.7)
			_barrel.add_child(mesh)


func _sync_range_shape() -> void:
	if _sphere == null:
		return
	_sphere.radius = attack_range
