extends RefCounted

## Accept only the renderer required for production mobile evidence.
## Requested command-line flags are not proof: Godot may fall back automatically.
static func is_mobile_vulkan(method: String, driver: String) -> bool:
	return method == "mobile" and driver == "vulkan"
