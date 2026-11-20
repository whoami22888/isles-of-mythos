extends Node
class_name RenderFallbackFactory

## Defensive asset loader. The primitives are diagnostic fallbacks, not approved
## production art. Never turn a missing resource into a client-authoritative state.
const LOG_PATH := "user://missing_assets.log"
const ROTATED_LOG_PATH := "user://missing_assets.log.1"
const CHECKER_SIZE := 32
const MAX_LOGGED_PATHS := 1024
const MAX_LOG_BYTES := 262144
const LOG_CATEGORIES := ["scene", "animation", "mesh", "sprite", "texture", "audio", "other"]
static var _logged_paths: Dictionary = {}
static var _logged_path_order: Array[String] = []
static var _logged_path_cursor := 0


static func _allowed_path(path: String, extensions: PackedStringArray) -> bool:
	return path.begins_with("res://") and not path.contains("..") and extensions.has(path.get_extension().to_lower())


static func _load_checked(path: String, extensions: PackedStringArray) -> Resource:
	if not _allowed_path(path, extensions):
		return null
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path)


static func _safe_log_category(category: String) -> String:
	# The first TSV column is a fixed field, never caller-controlled text.
	return category if LOG_CATEGORIES.has(category) else "other"


static func _safe_log_path(path: String) -> String:
	# Keep the TSV record single-line and two-column across C0/C1 controls and Unicode separators.
	var result := ""
	for index in range(mini(path.length(), 512)):
		var codepoint := path.unicode_at(index)
		if codepoint < 32 or (codepoint >= 127 and codepoint <= 159) or codepoint == 0x2028 or codepoint == 0x2029:
			result += " "
		else:
			result += path[index]
	return result


static func _repair_incomplete_log_tail() -> int:
	# A failed resize (or process interruption) can leave an unterminated TSV prefix.
	# Repair it before every append so a later retry cannot concatenate records.
	if not FileAccess.file_exists(LOG_PATH):
		return OK
	var file := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		return FAILED
	var size_before := file.get_length()
	if size_before < 0:
		file.close()
		return FAILED
	if size_before == 0 or size_before >= MAX_LOG_BYTES:
		# At-cap and oversized logs are handled by the bounded rotation/removal path
		# in _append_log_line(); do not reject them as an unrecognized torn tail.
		file.close()
		return OK
	file.seek(0)
	var bytes := file.get_buffer(size_before)
	var read_error := file.get_error()
	if bytes.size() != size_before or read_error != OK:
		file.close()
		return FAILED
	if bytes[bytes.size() - 1] == 10:
		file.close()
		return OK
	var tail_start := 0
	for index in range(bytes.size() - 1, -1, -1):
		if bytes[index] == 10:
			tail_start = index + 1
			break
	var tail := bytes.slice(tail_start)
	var tab_index := tail.find(9)
	var looks_like_record_prefix := false
	if tab_index == -1:
		# Also recover a short write that stopped inside the fixed category field.
		var category_prefix := tail.get_string_from_utf8()
		for category in LOG_CATEGORIES:
			if category.begins_with(category_prefix):
				looks_like_record_prefix = true
				break
	else:
		var category := tail.slice(0, tab_index).get_string_from_utf8()
		looks_like_record_prefix = LOG_CATEGORIES.has(category)
	if not looks_like_record_prefix:
		# Do not reinterpret unrelated legacy bytes as a partial record, and fail closed:
		# appending would concatenate a new record behind an unverified unterminated tail.
		file.close()
		return FAILED
	var resize_error := file.resize(tail_start)
	file.flush()
	var repaired := resize_error == OK and file.get_length() == tail_start
	file.close()
	return OK if repaired else FAILED


static func _append_log_line(line: String, writer: Callable = Callable()):
	if _repair_incomplete_log_tail() != OK:
		return FAILED
	var entry_bytes := line.to_utf8_buffer().size()
	var exists := FileAccess.file_exists(LOG_PATH)
	var existing_size := 0
	if exists:
		var reader := FileAccess.open(LOG_PATH, FileAccess.READ)
		if reader == null:
			return FAILED
		existing_size = reader.get_length()
		reader.close()
		if existing_size < 0:
			return FAILED
	if exists and existing_size + entry_bytes > MAX_LOG_BYTES:
		if existing_size <= MAX_LOG_BYTES:
			# The one-generation backup is replaced on subsequent rotations.
			if DirAccess.rename_absolute(ProjectSettings.globalize_path(LOG_PATH), ProjectSettings.globalize_path(ROTATED_LOG_PATH)) != OK:
				return FAILED
		else:
			# Pre-cap/corrupt oversized logs cannot become unbounded archives.
			if DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG_PATH)) != OK:
				return FAILED
		exists = false
	var file := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if file == null:
		return FAILED
	file.seek_end()
	var size_before := file.get_length()
	if size_before < 0:
		file.close()
		return FAILED
	var write_succeeded := false
	if writer.is_valid():
		write_succeeded = bool(writer.call(file, line))
	else:
		write_succeeded = file.store_string(line)
	file.flush()
	var write_error := file.get_error()
	var size_after := file.get_length()
	if not write_succeeded or write_error != OK or size_after != size_before + entry_bytes:
		# A short/failed append must not leave a prefix that corrupts the next TSV retry.
		# Resize while the file is still open, then flush the rollback before closing.
		var rollback_error := file.resize(size_before)
		if rollback_error == OK:
			file.flush()
	file.close()
	if not write_succeeded or write_error != OK or size_after != size_before + entry_bytes:
		return FAILED
	return OK


static func _log_missing_with_writer(path: String, category: String, writer: Callable) -> void:
	# Normalize both fields before building the deduplication key or TSV record.
	var safe_category := _safe_log_category(category)
	var safe_path := _safe_log_path(path)
	var key := safe_category + ":" + safe_path
	if _logged_paths.has(key):
		return
	if not writer.is_valid():
		return
	var line := "%s\t%s\n" % [safe_category, safe_path]
	var write_error = writer.call(line)
	# A failed or partial write must remain retryable after storage recovers.
	if write_error != OK:
		return
	# Keep only the most recent unique paths in memory. The bounded disk log
	# continues recording new paths after this cache fills instead of silently
	# dropping every later diagnostic.
	if _logged_path_order.size() < MAX_LOGGED_PATHS:
		_logged_path_order.append(key)
	else:
		var evicted_key: String = _logged_path_order[_logged_path_cursor]
		_logged_paths.erase(evicted_key)
		_logged_path_order[_logged_path_cursor] = key
		_logged_path_cursor = (_logged_path_cursor + 1) % MAX_LOGGED_PATHS
	_logged_paths[key] = true


static func _log_missing(path: String, category: String) -> void:
	var writer := func(line: String):
		return _append_log_line(line)
	_log_missing_with_writer(path, category, writer)

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


static func instantiate_scene_or_null(
	packed_scene: PackedScene,
	path: String = "",
	category: String = "other"
) -> Node:
	# A ResourceLoader result can be a PackedScene without a usable root. Check
	# instantiability before calling instantiate(), then validate the returned node.
	if packed_scene == null or not packed_scene.can_instantiate():
		if not path.is_empty():
			_log_missing(path, category)
		return null
	var instance := packed_scene.instantiate()
	if not is_instance_valid(instance):
		if not path.is_empty():
			_log_missing(path, category)
		return null
	return instance


static func _has_renderable_mesh(node: Node) -> bool:
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null and mesh.get_surface_count() > 0:
			return true
	elif node is MultiMeshInstance3D:
		var multimesh := (node as MultiMeshInstance3D).multimesh
		if (
			multimesh != null
			and multimesh.mesh != null
			and multimesh.mesh.get_surface_count() > 0
			and multimesh.instance_count > 0
			and multimesh.visible_instance_count != 0
		):
			return true
	for child in node.get_children():
		if _has_renderable_mesh(child):
			return true
	return false


static func mesh_resource_or_fallback(resource: Resource, path: String, kind: String = "character") -> Node3D:
	if resource is PackedScene:
		var instance := instantiate_scene_or_null(resource as PackedScene, path, "mesh")
		if instance is Node3D and _has_renderable_mesh(instance):
			return instance
		if is_instance_valid(instance):
			instance.free()
	elif resource is Mesh:
		var mesh := resource as Mesh
		if mesh.get_surface_count() > 0:
			var node := MeshInstance3D.new()
			node.mesh = mesh
			return node
	return get_fallback_mesh(path, kind)


static func load_mesh_or_fallback(path: String, kind: String = "character") -> Node3D:
	var resource := _load_checked(path, PackedStringArray(["glb", "gltf", "fbx"]))
	return mesh_resource_or_fallback(resource, path, kind)


static func _checkerboard_texture() -> Texture2D:
	var checker := Image.create(CHECKER_SIZE, CHECKER_SIZE, false, Image.FORMAT_RGBA8)
	for y in range(CHECKER_SIZE):
		for x in range(CHECKER_SIZE):
			var bright := ((x / 4) + (y / 4)) % 2 == 0
			checker.set_pixel(x, y, Color.WHITE if bright else Color.BLACK)
	return ImageTexture.create_from_image(checker)


static func get_fallback_sprite(path: String) -> ColorRect:
	_log_missing(path, "sprite")
	var background := ColorRect.new()
	background.name = "MissingSpriteDiagnostic"
	background.color = Color(1.0, 0.0, 1.0)
	# This node is a visual placeholder; let its parent Button/Control receive touch input.
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.custom_minimum_size = Vector2(CHECKER_SIZE, CHECKER_SIZE)
	background.size = Vector2(CHECKER_SIZE, CHECKER_SIZE)
	var child := TextureRect.new()
	child.name = "Checkerboard"
	# The checkerboard is decorative and must not intercept pointer input either.
	child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	child.texture = _checkerboard_texture()
	child.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	child.stretch_mode = TextureRect.STRETCH_SCALE
	child.size = Vector2(CHECKER_SIZE, CHECKER_SIZE)
	background.add_child(child)
	return background


static func load_texture_or_fallback(path: String) -> Texture2D:
	var resource := _load_checked(path, PackedStringArray(["png", "webp"]))
	if resource is Texture2D:
		return resource as Texture2D
	_log_missing(path, "texture")
	return _checkerboard_texture()


static func load_sprite_or_fallback(path: String) -> Control:
	var resource := _load_checked(path, PackedStringArray(["png", "webp"]))
	if resource is Texture2D:
		var sprite := TextureRect.new()
		# Loaded sprites are presentation-only; interaction belongs to their parent.
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sprite.texture = resource
		return sprite
	return get_fallback_sprite(path)


static func load_scene_or_null(path: String, category: String = "scene") -> PackedScene:
	var resource := _load_checked(path, PackedStringArray(["glb", "gltf", "fbx"]))
	if resource is PackedScene:
		return resource as PackedScene
	_log_missing(path, category)
	return null


static func load_audio_or_fallback(path: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	var resource := _load_checked(path, PackedStringArray(["ogg", "wav"]))
	if resource is AudioStream:
		player.stream = resource
	else:
		_log_missing(path, "audio")
	# A missing clip is silent rather than an engine error or a fake sound.
	return player
