extends Node
class_name RenderFallbackFactory

## Defensive asset loader. The primitives are diagnostic fallbacks, not approved
## production art. Never turn a missing resource into a client-authoritative state.
const LOG_PATH := "user://missing_assets.log"
const ROTATED_LOG_PATH := "user://missing_assets.log.1"
const CHECKER_SIZE := 32
const MAX_LOGGED_PATHS := 1024
const MAX_LOG_BYTES := 262144
static var _logged_paths: Dictionary = {}


static func _allowed_path(path: String, extensions: PackedStringArray) -> bool:
	return path.begins_with("res://") and not path.contains("..") and extensions.has(path.get_extension().to_lower())


static func _load_checked(path: String, extensions: PackedStringArray) -> Resource:
	if not _allowed_path(path, extensions):
		return null
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path)


static func _safe_log_path(path: String) -> String:
	# Keep the TSV record single-line and two-column, including for C0/DEL chars.
	var result := ""
	for index in range(mini(path.length(), 512)):
		var codepoint := path.unicode_at(index)
		if codepoint < 32 or codepoint == 127:
			result += " "
		else:
			result += path[index]
	return result


static func _log_missing(path: String, category: String) -> void:
	# Asset paths are untrusted. Sanitize log lines and bound the number written.
	var safe_path := _safe_log_path(path)
	var key := category + ":" + safe_path
	if _logged_paths.has(key) or _logged_paths.size() >= MAX_LOGGED_PATHS:
		return
	var line := "%s\t%s\n" % [category, safe_path]
	var entry_bytes := line.to_utf8_buffer().size()
	# Check size without allocating the entire log. Preserve one bounded archive.
	var exists := FileAccess.file_exists(LOG_PATH)
	var existing_size := 0
	if exists:
		var reader := FileAccess.open(LOG_PATH, FileAccess.READ)
		if reader == null:
			return
		existing_size = reader.get_length()
		reader.close()
	if exists and existing_size + entry_bytes > MAX_LOG_BYTES:
		if existing_size <= MAX_LOG_BYTES:
			# The one-generation backup is replaced on subsequent rotations.
			if DirAccess.rename_absolute(ProjectSettings.globalize_path(LOG_PATH), ProjectSettings.globalize_path(ROTATED_LOG_PATH)) != OK:
				return
		else:
			# Pre-cap/corrupt oversized logs cannot become unbounded archives.
			if DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG_PATH)) != OK:
				return
		exists = false
	var file := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_string(line)
	file.flush()
	var write_error := file.get_error()
	file.close()
	# Do not suppress a future retry when the write failed (e.g. full storage).
	if write_error != OK:
		return
	_logged_paths[key] = true

static func get_fallback_mesh(path: String, kind: String = "character") -> MeshInstance3D:
	_log_missing(path, "mesh")
	var fallback := MeshInstance3D.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if kind == "character" or kind == "creature":
		fallback.mesh = CapsuleMesh.new()
		material.albedo_color = Color(0.0, 0.8, 1.0)
	else:
		fallback.mesh = BoxMesh.new()
		material.albedo_color = Color(1.0, 0.0, 1.0)
	fallback.material_override = material
	fallback.name = "MissingAssetDiagnostic"
	return fallback


static func load_mesh_or_fallback(path: String, kind: String = "character") -> Node3D:
	var resource := _load_checked(path, PackedStringArray(["glb", "gltf"]))
	if resource is PackedScene:
		var instance := (resource as PackedScene).instantiate()
		if instance is Node3D:
			return instance
		instance.free()
	elif resource is Mesh:
		var node := MeshInstance3D.new()
		node.mesh = resource
		return node
	return get_fallback_mesh(path, kind)


static func get_fallback_sprite(path: String) -> ColorRect:
	_log_missing(path, "sprite")
	var background := ColorRect.new()
	background.name = "MissingSpriteDiagnostic"
	background.color = Color(1.0, 0.0, 1.0)
	background.custom_minimum_size = Vector2(CHECKER_SIZE, CHECKER_SIZE)
	background.size = Vector2(CHECKER_SIZE, CHECKER_SIZE)
	var checker := Image.create(CHECKER_SIZE, CHECKER_SIZE, false, Image.FORMAT_RGBA8)
	for y in range(CHECKER_SIZE):
		for x in range(CHECKER_SIZE):
			var bright := ((x / 4) + (y / 4)) % 2 == 0
			checker.set_pixel(x, y, Color.WHITE if bright else Color.BLACK)
	var child := TextureRect.new()
	child.name = "Checkerboard"
	child.texture = ImageTexture.create_from_image(checker)
	child.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	child.stretch_mode = TextureRect.STRETCH_SCALE
	child.size = Vector2(CHECKER_SIZE, CHECKER_SIZE)
	background.add_child(child)
	return background


static func load_sprite_or_fallback(path: String) -> Control:
	var resource := _load_checked(path, PackedStringArray(["png", "webp"]))
	if resource is Texture2D:
		var sprite := TextureRect.new()
		sprite.texture = resource
		return sprite
	return get_fallback_sprite(path)


static func load_audio_or_fallback(path: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	var resource := _load_checked(path, PackedStringArray(["ogg", "wav"]))
	if resource is AudioStream:
		player.stream = resource
	else:
		_log_missing(path, "audio")
	# A missing clip is silent rather than an engine error or a fake sound.
	return player
