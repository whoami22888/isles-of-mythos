extends CharacterBody3D
class_name MythosCreature

## Client projection of a server-owned companion. Care, XP, work and production
## effects are requests/snapshot fields only; this node never applies them locally.

enum State { WILD, TAMED_FOLLOW, TAMED_WORK, RESTING }
enum Element { WATER, FIRE, EARTH, AIR }

signal care_requested(creature_id: String, action: String, expected_mood_gain: int)
signal work_assignment_requested(creature_id: String, building_id: String, task: String)
signal authoritative_snapshot_changed

const PET_MOOD_GAIN := 10
const FEED_MOOD_GAIN := 15
const EXCITED_MOOD_THRESHOLD := 80.0
const EXCITED_XP_MULTIPLIER := 2.0
const FIRE_FORGE_YIELD_MULTIPLIER := 1.6
const WATER_DOCKS_FARM_YIELD_MULTIPLIER := 1.4
const STATE_BY_NAME := {
	"wild": State.WILD,
	"tamed_follow": State.TAMED_FOLLOW,
	"tamed_work": State.TAMED_WORK,
	"resting": State.RESTING,
}
const ELEMENT_BY_NAME := {
	"water": Element.WATER,
	"fire": Element.FIRE,
	"earth": Element.EARTH,
	"air": Element.AIR,
}

var creature_id: String = ""
var state: int = State.WILD
var element: int = Element.WATER
var mood: float = 0.0
var hearts: int = 1
var is_excited: bool = false
var xp_multiplier: float = 1.0
var work_output_max: bool = false
var workstation: String = ""
var work_task: String = ""
var work_yield_multiplier: float = 1.0
var _has_authoritative_snapshot: bool = false


## The server snapshot must contain the authoritative mood, state and calculated
## multipliers. Reject inconsistent data instead of inventing client-side effects.
func apply_authoritative_snapshot(snapshot: Dictionary) -> bool:
	var id_value: Variant = snapshot.get("id")
	var state_name_value: Variant = snapshot.get("state")
	var element_name_value: Variant = snapshot.get("element")
	var mood_value: Variant = snapshot.get("mood")
	var xp_value: Variant = snapshot.get("xp_multiplier")
	var max_output_value: Variant = snapshot.get("work_output_max")
	var workstation_value: Variant = snapshot.get("workstation")
	var work_task_value: Variant = snapshot.get("work_task")
	var yield_value: Variant = snapshot.get("work_yield_multiplier")

	if not (id_value is String) or id_value.strip_edges().is_empty():
		return false
	if not (state_name_value is String) or not STATE_BY_NAME.has(state_name_value):
		return false
	if not (element_name_value is String) or not ELEMENT_BY_NAME.has(element_name_value):
		return false
	if not (mood_value is int or mood_value is float):
		return false
	if not (xp_value is int or xp_value is float):
		return false
	if not (max_output_value is bool) or not (workstation_value is String) or not (work_task_value is String):
		return false
	if not (yield_value is int or yield_value is float):
		return false

	var next_mood := float(mood_value)
	var next_xp_multiplier := float(xp_value)
	var next_yield_multiplier := float(yield_value)
	if not is_finite(next_mood) or next_mood < 0.0 or next_mood > 100.0:
		return false
	if not is_finite(next_xp_multiplier) or not is_finite(next_yield_multiplier):
		return false

	var next_state: int = STATE_BY_NAME[state_name_value]
	var next_element: int = ELEMENT_BY_NAME[element_name_value]
	var next_workstation := workstation_value.strip_edges().to_lower()
	var next_work_task := work_task_value.strip_edges().to_lower()
	var next_excited := next_state != State.WILD and next_mood >= EXCITED_MOOD_THRESHOLD
	var expected_xp := EXCITED_XP_MULTIPLIER if next_excited else 1.0
	if absf(next_xp_multiplier - expected_xp) > 0.001:
		return false
	if max_output_value != next_excited:
		return false

	var expected_yield := 1.0
	if next_state == State.TAMED_WORK:
		if next_workstation.is_empty():
			return false
		if next_work_task.is_empty():
			return false
		expected_yield = _expected_work_yield(next_element, next_workstation, next_work_task)
	elif not next_workstation.is_empty() or not next_work_task.is_empty():
		return false
	if absf(next_yield_multiplier - expected_yield) > 0.001:
		return false

	creature_id = id_value
	state = next_state
	element = next_element
	mood = next_mood
	hearts = clampi(int(ceil(next_mood / 20.0)), 1, 5)
	is_excited = next_excited
	xp_multiplier = next_xp_multiplier
	work_output_max = max_output_value
	workstation = next_workstation
	work_task = next_work_task
	work_yield_multiplier = next_yield_multiplier
	_has_authoritative_snapshot = true
	authoritative_snapshot_changed.emit()
	return true


## Emits the requested +10 care action. Mood changes only after a server snapshot.
func pet_companion() -> bool:
	if not _has_authoritative_snapshot or state == State.WILD:
		return false
	care_requested.emit(creature_id, "pet", PET_MOOD_GAIN)
	return true


## Emits the requested +15 feed action. Mood changes only after a server snapshot.
func feed_companion() -> bool:
	if not _has_authoritative_snapshot or state == State.WILD:
		return false
	care_requested.emit(creature_id, "feed", FEED_MOOD_GAIN)
	return true


## Emits an assignment intent for the existing server worker-assignment command.
## No local state or production output is changed.
func request_work_assignment(building_id: String, task: String) -> bool:
	if not _has_authoritative_snapshot or state == State.WILD or state == State.RESTING:
		return false
	var clean_building_id := building_id.strip_edges()
	var clean_task := task.strip_edges().to_lower()
	if clean_building_id.is_empty() or clean_task.is_empty():
		return false
	work_assignment_requested.emit(creature_id, clean_building_id, clean_task)
	return true


func get_state_name() -> String:
	for state_name in STATE_BY_NAME:
		if STATE_BY_NAME[state_name] == state:
			return state_name
	return "wild"


func get_element_name() -> String:
	for element_name in ELEMENT_BY_NAME:
		if ELEMENT_BY_NAME[element_name] == element:
			return element_name
	return "water"


func _expected_work_yield(creature_element: int, target_workstation: String, target_task: String) -> float:
	if (
		creature_element == Element.FIRE
		and target_workstation == "forge"
		and target_task == "ore_smelting"
	):
		return FIRE_FORGE_YIELD_MULTIPLIER
	if (
		creature_element == Element.WATER
		and target_workstation in ["docks", "fishing_dock", "farm"]
		and target_task in ["collect", "irrigation", "fishing", "net_operation", "aquatic_harvesting"]
	):
		return WATER_DOCKS_FARM_YIELD_MULTIPLIER
	return 1.0
