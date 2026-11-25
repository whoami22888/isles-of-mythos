extends RefCounted

const MythosCreature = preload("res://entities/mythos/mythos_creature.gd")


static func run(tree: SceneTree, check: Callable) -> void:
	var creature = MythosCreature.new()
	tree.root.add_child(creature)
	var care_events: Array[Dictionary] = []
	var work_events: Array[Dictionary] = []
	var snapshot_changes := [0]
	creature.care_requested.connect(func(id: String, action: String, gain: int) -> void:
		care_events.append({"id": id, "action": action, "gain": gain})
	)
	creature.work_assignment_requested.connect(func(id: String, building_id: String, task: String) -> void:
		work_events.append({"id": id, "building_id": building_id, "task": task})
	)
	creature.authoritative_snapshot_changed.connect(func() -> void:
		snapshot_changes[0] += 1
	)

	var follow := _snapshot("mythos-1", "tamed_follow", "fire", 79.0, 1.0, false, "", 1.0)
	check.call(creature.apply_authoritative_snapshot(follow), "Creature must accept a valid server follow snapshot")
	check.call(creature.get_state_name() == "tamed_follow" and creature.get_element_name() == "fire", "Creature state and element names must map to their enums")
	check.call(creature.mood == 79.0 and creature.hearts == 4 and not creature.is_excited, "Mood 79 must remain below the excited threshold and derive four hearts")
	check.call(creature.xp_multiplier == 1.0 and not creature.work_output_max, "A non-excited server snapshot must not grant excited bonuses")

	var mood_before_care: float = float(creature.mood)
	check.call(creature.pet_companion(), "A tamed companion must emit a pet intent")
	check.call(creature.feed_companion(), "A tamed companion must emit a feed intent")
	check.call(care_events == [
		{"id": "mythos-1", "action": "pet", "gain": 10},
		{"id": "mythos-1", "action": "feed", "gain": 15},
	], "Pet and feed intents must carry the configured mood gains")
	check.call(creature.mood == mood_before_care, "Care intents must not mutate mood before a server snapshot")

	var excited_fire := _snapshot("mythos-1", "tamed_work", "fire", 80.0, 2.0, true, "forge", 1.6, "ore_smelting")
	check.call(creature.apply_authoritative_snapshot(excited_fire), "Fire companion at a Forge must accept the server's 1.6x yield snapshot")
	check.call(creature.is_excited and creature.hearts == 4, "Mood 80 must enter excited state")
	check.call(creature.xp_multiplier == 2.0 and creature.work_output_max, "Excited state must project the server's 2.0x XP and maximum-work flags")
	check.call(is_equal_approx(creature.work_yield_multiplier, 1.6), "Fire at Forge must project 1.6x smelting yield")
	check.call(creature.request_work_assignment("forge-building-1", "ore_smelting"), "A tamed companion must emit a work-assignment intent")
	check.call(work_events == [{"id": "mythos-1", "building_id": "forge-building-1", "task": "ore_smelting"}], "Work assignment intent must include the creature, building and task")
	check.call(creature.state == MythosCreature.State.TAMED_WORK and creature.workstation == "forge", "Work intent must not locally change the server-owned assignment")

	var excited_water_docks := _snapshot("mythos-1", "tamed_work", "water", 85.0, 2.0, true, "docks", 1.4, "fishing")
	check.call(creature.apply_authoritative_snapshot(excited_water_docks), "Water companion at Docks must accept the server's 1.4x yield snapshot")
	check.call(is_equal_approx(creature.work_yield_multiplier, 1.4), "Water at Docks must project 1.4x food yield")
	var excited_water_farm := _snapshot("mythos-1", "tamed_work", "water", 90.0, 2.0, true, "farm", 1.4, "irrigation")
	check.call(creature.apply_authoritative_snapshot(excited_water_farm), "Water companion at Farm must accept the server's 1.4x yield snapshot")
	check.call(is_equal_approx(creature.work_yield_multiplier, 1.4), "Water at Farm must project 1.4x food yield")
	var earth_forge := _snapshot("mythos-1", "tamed_work", "earth", 80.0, 2.0, true, "forge", 1.0, "ore_smelting")
	check.call(creature.apply_authoritative_snapshot(earth_forge), "Unmatched element/workstation pairs must remain at normal yield")
	check.call(is_equal_approx(creature.work_yield_multiplier, 1.0), "Earth at Forge must not receive a Fire bonus")

	var perfect_mood := _snapshot("mythos-1", "tamed_follow", "air", 100.0, 2.0, true, "", 1.0)
	check.call(creature.apply_authoritative_snapshot(perfect_mood), "Creature must accept the maximum mood snapshot")
	check.call(creature.hearts == 5 and creature.is_excited, "Mood 100 must derive five hearts and excited state")

	var resting := _snapshot("mythos-1", "resting", "water", 90.0, 2.0, true, "", 1.0)
	check.call(creature.apply_authoritative_snapshot(resting), "Creature must accept a resting server snapshot")
	check.call(not creature.request_work_assignment("farm-1", "collect"), "A resting creature must not request work")
	check.call(creature.pet_companion() and creature.feed_companion(), "Resting companions may still receive care")

	var wild := _snapshot("wild-1", "wild", "earth", 0.0, 1.0, false, "", 1.0)
	check.call(creature.apply_authoritative_snapshot(wild), "Creature must accept a wild server snapshot")
	check.call(not creature.pet_companion() and not creature.feed_companion(), "Wild creatures must reject owned-companion care actions")
	check.call(not creature.request_work_assignment("forge-1", "ore_smelting"), "Wild creatures must reject work assignment intents")

	var mood_before_invalid: float = float(creature.mood)
	var invalid_mood := _snapshot("wild-1", "wild", "earth", 101.0, 2.0, true, "", 1.0)
	check.call(not creature.apply_authoritative_snapshot(invalid_mood), "Mood outside 0–100 must be rejected")
	check.call(creature.mood == mood_before_invalid, "Rejected mood data must not overwrite the last valid snapshot")
	var invalid_xp := _snapshot("wild-1", "tamed_follow", "fire", 85.0, 1.0, false, "", 1.0)
	check.call(not creature.apply_authoritative_snapshot(invalid_xp), "An excited snapshot with a non-2.0 XP multiplier must be rejected")
	var invalid_yield := _snapshot("wild-1", "tamed_work", "fire", 85.0, 2.0, true, "forge", 1.4, "ore_smelting")
	check.call(not creature.apply_authoritative_snapshot(invalid_yield), "Fire/Forge yield mismatch must be rejected")
	var invalid_element := _snapshot("wild-1", "tamed_follow", "lightning", 50.0, 1.0, false, "", 1.0)
	check.call(not creature.apply_authoritative_snapshot(invalid_element), "Unknown creature elements must be rejected")
	check.call(snapshot_changes[0] == 8, "Only valid authoritative snapshots may emit snapshot_changed")

	creature.queue_free()
	await tree.process_frame


static func _snapshot(
	id: String,
	state: String,
	element: String,
	mood: float,
	xp_multiplier: float,
	work_output_max: bool,
	workstation: String,
	work_yield_multiplier: float,
	work_task: String = ""
) -> Dictionary:
	return {
		"id": id,
		"state": state,
		"element": element,
		"mood": mood,
		"xp_multiplier": xp_multiplier,
		"work_output_max": work_output_max,
		"workstation": workstation,
		"work_task": work_task,
		"work_yield_multiplier": work_yield_multiplier,
	}
