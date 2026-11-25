extends SceneTree

## Non-headless Vulkan Mobile entrypoint for the Prompt 010 draw-call contract.
## The structural regression remains shared with the IOM-00 headless suite; this
## entrypoint requires a real RenderingServer adapter so the one-draw-call
## assertion cannot silently downgrade to the Dummy renderer.

const MultiMeshRegression := preload("res://tests/multimesh_instancer_regression.gd")

var _failures := 0


func _init() -> void:
	call_deferred("run")


func check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1


func run() -> void:
	var adapter_name := RenderingServer.get_video_adapter_name()
	var rendering_method := RenderingServer.get_current_rendering_method()
	check(not adapter_name.is_empty(), "A non-headless rendering adapter is required for draw-call acceptance")
	check(rendering_method == "mobile", "The rendered draw-call regression must use the Godot Mobile renderer")
	if _failures > 0:
		quit(1)
		return

	await MultiMeshRegression.run(self, Callable(self, "check"))
	print(
		"MULTIMESH_RENDER_TEST_COMPLETE method=%s adapter=%s failures=%d"
		% [rendering_method, adapter_name, _failures]
	)
	quit(1 if _failures > 0 else 0)
