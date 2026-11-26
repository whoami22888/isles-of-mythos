extends Node
class_name OnboardingSequence

const COLD_OPEN_BUDGET_SECONDS := 15 * 60

var phases := [
	{"id": "tutorial_cannon_battle", "seconds": 240, "requires_action": true},
	{"id": "scripted_shipwreck", "seconds": 180, "requires_action": true},
	{"id": "mythos_rescue", "seconds": 240, "requires_action": true},
	{"id": "first_campsite_placement", "seconds": 240, "requires_action": true},
]

func total_seconds() -> int:
	var total := 0
	for phase in phases:
		total += int(phase["seconds"])
	return total

func is_within_cold_open_budget() -> bool:
	return total_seconds() <= COLD_OPEN_BUDGET_SECONDS

func phase_ids() -> PackedStringArray:
	var ids: PackedStringArray = []
	for phase in phases:
		ids.append(str(phase["id"]))
	return ids
