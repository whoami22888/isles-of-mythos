extends SceneTree

func _init() -> void:
	var project: String = ProjectSettings.get_setting("application/config/name", "")
	assert(project == "Isles of Mythos")
	assert(ProjectSettings.get_setting("rendering/renderer/rendering_method", "") == "mobile")
	quit()
