extends SceneTree

const NavalVesselRegression = preload("res://tests/naval_vessel_regression.gd")
var _failures := 0

func check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

func _init() -> void:
	call_deferred("run")

func run() -> void:
	await NavalVesselRegression.run(self, Callable(self, "check"))
	print("IOM Prompt 015 naval vessel checks: %s failures" % _failures)
	quit(1 if _failures else 0)
