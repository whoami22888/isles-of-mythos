extends Node3D

const Protocol = preload("res://gameplay/vertical_slice_protocol.gd")
const GuildObjectivesPanel = preload("res://gameplay/guild_objectives_panel.gd")
var _guild_objectives: VBoxContainer
const ExpeditionsPanel = preload("res://gameplay/expeditions_panel.gd")
var _expeditions: VBoxContainer
const DailyObjectivesPanel = preload("res://gameplay/daily_objectives_panel.gd")
var _objectives: VBoxContainer
const CraftPanel = preload("res://gameplay/craft_panel.gd")
var _craft: VBoxContainer
const TouchControls = preload("res://gameplay/touch_controls.gd")
var _touch: Control
## Camera orbit yaw (radians) around the authoritative player. Presentation
## only; manual move directions are rotated by it so "up" walks away from the
## camera for both keyboard and joystick. It starts at PI: the camera sits
## seaward of the player and looks inland across the beach, so the coastal
## bay's cliff band is behind the player instead of between camera and player.
var _camera_yaw := PI
const CAMERA_ORBIT_RADIANS_PER_PIXEL := 0.008
var _manual_moving := false
## Gameplay panels live in a viewport-bounded scroll area so every control
## stays reachable at 1280x720 and on phones however long the lists grow.
var _hud_scroll: ScrollContainer
var _hud_panels: VBoxContainer
## Phone HUD. Before gameplay (the pre-login/debug flow) the panel shows the
## connection form with the drawer open, as before. Once the session is handed
## off from login or authenticates, the panel becomes a compact HUD: status,
## Gather and a drawer toggle, collapsed by default, so the game world stays
## visible and the touch joystick zone widens (TouchControls reads the panel
## rect live). Presentation only; no server or protocol state lives here.
## Minimum panel width (stylebox and margins included) of the collapsed HUD;
## the drawer toggle label makes it about 246 px, so the right edge sits near
## 270 px of a 1280 px wide view (about 21%), and the canvas_items
## stretch keeps the same logical width on wider phones such as 2340x1080.
const COMPACT_HUD_WIDTH := 244.0
## The open drawer gets a readable column for the objectives/crafting rows.
const EXPANDED_HUD_WIDTH := 420.0
const COMPACT_HUD_MARGIN := 8
const FULL_HUD_MARGIN := 16
const HUD_TOUCH_TARGET := 48.0
const GATHER_LABEL_FULL := "Touch / click: walk to and gather nearest visible resource"
const GATHER_LABEL_COMPACT := "Gather nearest"
const DRAWER_LABEL_OPEN := "Close drawer"
const DRAWER_LABEL_CLOSED := "Quests & crafting"
var _panel: PanelContainer
var _title: Label
var _drawer_toggle: Button
var _gameplay_hud := false
var _drawer_open := true
## True between an authenticated session and the next observed loss of it;
## only gates whether the Reconnect control is shown in the compact HUD.
var _session_live := false
## Set when a command outcome is unknown and the HUD asks for a manual
## reconnect; cleared by the next successful authentication.
var _reconnect_requested := false
var _client: Node
var _player := Vector3.ZERO
var _markers: Dictionary = {}
var _status: Label
var _state: Label
var _gather: Button
var _endpoint: LineEdit
var _token: LineEdit
var _connect_button: Button
var _handoff_endpoint := ""
var _handoff_token := ""
var _refresh_token := ""
var _refreshing := false
var _refresh_http: HTTPRequest
# Mirrors server CHUNK_SIZE (server/src/world.ts); display/request hint only.
const CHUNK_SIZE := 32.0
# Server gather range is 2.5 units (server/src/app.ts); stop short of it. The
# server still validates every gather, this only decides when to send intent.
const GATHER_APPROACH_DISTANCE := 2.0
const TAP_RESOURCE_RADIUS := 1.5
const MOVE_ARRIVE_DISTANCE := 0.35
const MOVE_INTERVAL_SECONDS := 0.08
# Chunk snapshots are not pushed, so re-read the authoritative chunk on a
# bounded schedule (respawns are 45-90 s) with at most one request in flight.
const CHUNK_REFRESH_SECONDS := 10.0
var _chunk := Vector2i.ZERO
var _chunk_known := false
var _chunk_in_flight := ""
var _refresh_clock := 0.0
var _approaching := false
var _approach_target := ""
var _move_to_point := false
var _move_point := Vector2.ZERO
var _move_clock := 0.0

func begin_authenticated_session(endpoint: String, token: String, refresh_token: String = "") -> void:
	_handoff_endpoint = endpoint
	_handoff_token = token
	_refresh_token = refresh_token

func _ready() -> void:
	_status = $Interface/Panel/Margin/Content/Status
	_state = $Interface/Panel/Margin/Content/State
	_gather = $Interface/Panel/Margin/Content/Gather
	_endpoint = $Interface/Panel/Margin/Content/Endpoint
	_token = $Interface/Panel/Margin/Content/Token
	_connect_button = $Interface/Panel/Margin/Content/Connect
	_panel = $Interface/Panel
	_title = $Interface/Panel/Margin/Content/Title
	_drawer_toggle = $Interface/Panel/Margin/Content/DrawerToggle
	_drawer_toggle.pressed.connect(toggle_drawer)
	_gather.pressed.connect(_gather_nearest)
	_connect_button.pressed.connect(_connect)
	_hud_scroll = ScrollContainer.new()
	_hud_scroll.name = "HudScroll"
	_hud_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	$Interface/Panel/Margin/Content.add_child(_hud_scroll)
	_hud_panels = VBoxContainer.new()
	_hud_panels.name = "HudPanels"
	_hud_panels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hud_scroll.add_child(_hud_panels)
	_fit_hud_scroll()
	get_viewport().size_changed.connect(_fit_hud_scroll)
	_guild_objectives = GuildObjectivesPanel.new()
	_guild_objectives.name = "GuildObjectives"
	_hud_panels.add_child(_guild_objectives)
	_guild_objectives.reward_claimed.connect(func(_id: String, gold: String) -> void: _status.text = "Guild reward claimed: +" + gold + " gold")
	_expeditions = ExpeditionsPanel.new()
	_expeditions.name = "Expeditions"
	_hud_panels.add_child(_expeditions)
	_expeditions.expedition_collected.connect(func(_id: String, gold: String) -> void: _status.text = "Expedition returned: +" + gold + " gold")
	_objectives = DailyObjectivesPanel.new()
	_objectives.name = "DailyObjectives"
	_hud_panels.add_child(_objectives)
	_objectives.reward_claimed.connect(func(_id: String, gold: String) -> void: _status.text = "Daily reward claimed: +" + gold + " gold")
	_craft = CraftPanel.new()
	_craft.name = "CraftPanel"
	_craft.craft_sender = func(recipe_id: String) -> String: return _client.request_craft(recipe_id)
	_hud_panels.add_child(_craft)
	_craft.craft_succeeded.connect(func(_id: String) -> void:
		_status.text = "Server ACK: craft persisted"
		_objectives.refresh()
		_guild_objectives.refresh())
	_build_scaffold_world()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_client = Protocol.new()
	add_child(_client)
	_client.status_changed.connect(_on_transport_status)
	_client.authenticated.connect(_on_authenticated)
	_client.player_state_received.connect(_on_player_state)
	_client.world_chunk_received.connect(_on_world_chunk)
	_client.command_acknowledged.connect(_on_ack)
	_client.server_rejected.connect(_on_rejection)
	_client.command_rejected.connect(func(request_id: String, code: String) -> void: _craft.on_craft_rejected(request_id, code))
	_client.command_outcome_unknown.connect(_on_outcome_unknown)
	_client.auth_failed.connect(_on_auth_failed)
	var endpoint := OS.get_environment("IOM_WS_URL")
	if endpoint.is_empty():
		endpoint = ProjectSettings.get_setting("application/config/default_ws_url", "ws://127.0.0.1:3000/ws")
	_endpoint.text = endpoint
	_token.text = OS.get_environment("IOM_AUTH_TOKEN")
	if not _handoff_token.is_empty():
		_endpoint.text = _handoff_endpoint
		_token.text = ""
		_token.hide()
		# Keep the only recovery control; it reuses the in-memory session and
		# never displays the JWT.
		_connect_button.text = "Reconnect"
		_enter_gameplay_hud()
		_connect()
	elif not _token.text.is_empty():
		_connect()
	else:
		_status.text = "Enter a JWT token; this slice has no local authority"
	_death = Label.new()
	_death.name = "DeathBanner"
	_death.text = "You died - respawning"
	_death.visible = false
	_death.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_death.offset_left = -280.0
	_death.offset_top = 28.0
	_death.offset_right = 280.0
	_death.offset_bottom = 84.0
	_death.add_theme_font_size_override("font_size", 28)
	_death.add_theme_color_override("font_color", Color("#fff1d0"))
	_death.add_theme_color_override("font_shadow_color", Color(0.15, 0.05, 0.02, 0.85))
	_death.add_theme_constant_override("shadow_outline_size", 6)
	$Interface.add_child(_death)
	_mount_touch_controls()
	_apply_hud_layout()

func is_gameplay_hud() -> bool:
	return _gameplay_hud

func is_drawer_open() -> bool:
	return _drawer_open

func toggle_drawer() -> void:
	set_drawer_open(not _drawer_open)

func set_drawer_open(open: bool) -> void:
	_drawer_open = open
	_apply_hud_layout()

## Switches to the compact gameplay HUD once per scene with the drawer
## collapsed. Later re-authentications keep the player's drawer choice.
func _enter_gameplay_hud() -> void:
	if _gameplay_hud:
		return
	_gameplay_hud = true
	_drawer_open = false
	_apply_hud_layout()

func _apply_hud_layout() -> void:
	if _panel == null or _hud_scroll == null:
		return
	var compact := _gameplay_hud
	_title.visible = not compact
	_endpoint.visible = not compact
	# The JWT field is never shown again after a login handoff.
	_token.visible = not compact and _handoff_token.is_empty()
	# Reconnect is the recovery control: shown until a session is live, again
	# whenever it is lost or a command outcome is unknown, and always inside
	# the open drawer so a manual reconnect is never out of reach.
	_connect_button.visible = not compact or not _session_live or _reconnect_requested or _drawer_open
	_state.visible = not compact or _drawer_open
	_gather.text = GATHER_LABEL_COMPACT if compact else GATHER_LABEL_FULL
	_hud_scroll.visible = _drawer_open
	_drawer_toggle.text = DRAWER_LABEL_OPEN if _drawer_open else DRAWER_LABEL_CLOSED
	var touch_height := HUD_TOUCH_TARGET if compact else 0.0
	_gather.custom_minimum_size.y = touch_height
	_connect_button.custom_minimum_size.y = touch_height
	_drawer_toggle.custom_minimum_size.y = HUD_TOUCH_TARGET
	if not compact:
		_panel.custom_minimum_size.x = 0.0
	else:
		_panel.custom_minimum_size.x = EXPANDED_HUD_WIDTH if _drawer_open else COMPACT_HUD_WIDTH
	var margin: MarginContainer = $Interface/Panel/Margin
	var inset := COMPACT_HUD_MARGIN if compact else FULL_HUD_MARGIN
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, inset)
	# Containers only grow on their own: shrink the panel to its new minimum
	# once the visibility changes have propagated, then re-centre the player.
	call_deferred("_settle_hud_layout")

func _settle_hud_layout() -> void:
	if _panel == null or not is_inside_tree():
		return
	_panel.reset_size()
	# Wrapped labels (the status line) report their final height only after the
	# new width is laid out; shrink once more on the next frame.
	await get_tree().process_frame
	if _panel == null or not is_inside_tree():
		return
	_panel.reset_size()
	_frame_player_in_play_area($Camera)

## Phone controls sit below the HUD in the Interface layer; touches that start
## on the HUD panel stay with the HUD.
func _mount_touch_controls() -> void:
	_touch = TouchControls.new()
	_touch.name = "TouchControls"
	_touch.blocked_controls.append($Interface/Panel as Control)
	$Interface.add_child(_touch)
	$Interface.move_child(_touch, 0)
	_touch.camera_drag.connect(_on_camera_drag)
	_touch.tapped.connect(_handle_tap)

func _on_camera_drag(delta: Vector2) -> void:
	_camera_yaw = wrapf(_camera_yaw - delta.x * CAMERA_ORBIT_RADIANS_PER_PIXEL, -PI, PI)
	_follow_camera()

## The single manual-movement source: keyboard actions and the touch joystick
## (screen space, +y = down/towards camera) combined into a unit world XZ
## direction, rotated by the camera orbit. Zero when there is no input.
func manual_move_intent() -> Vector2:
	var screen := Vector2.ZERO
	var focus := get_viewport().gui_get_focus_owner()
	if not (focus is LineEdit):
		screen = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if _touch != null:
		screen += _touch.joystick_vector()
	if screen.length() < 0.0001:
		return Vector2.ZERO
	return screen.normalized().rotated(-_camera_yaw)

## Sends the manual direction through the existing server `move` intent at the
## same bounded cadence as tap-to-move. Returns true while manual input is held.
func _manual_move_step(delta: float) -> bool:
	var intent := manual_move_intent()
	if intent == Vector2.ZERO:
		_manual_moving = false
		return false
	# Manual input always wins: cancel any approach started by a tap or the
	# Gather button while the stick or a key is held, not only on the first frame.
	_stop_approach()
	if not _manual_moving:
		_manual_moving = true
		_move_clock = MOVE_INTERVAL_SECONDS
	_move_clock += delta
	if _move_clock >= MOVE_INTERVAL_SECONDS:
		_move_clock = 0.0
		_client.request_move(intent.x, intent.y)
	return true

func _connect() -> void:
	_client.configure(_handoff_endpoint if not _handoff_token.is_empty() else _endpoint.text,
		_handoff_token if not _handoff_token.is_empty() else _token.text)
	_client.connect_to_server()

# Scaffold ground edge length: four chunks, so the player's chunk plus a one-chunk margin is always covered
# once the plane is snapped to the player's chunk centre (see _recenter_ground).
# It is only a fallback: it stays hidden whenever the coastal world mounts.
const GROUND_SIZE := CHUNK_SIZE * 4.0
## Point of the authored coastal bay (its local space) that the centre of the
## player's chunk maps to. With a 32 m chunk this puts the chunk over the
## beach, grass shelf and cliff band (local z -9..23) instead of open sea.
const COASTAL_CHUNK_ANCHOR := Vector3(0.0, 0.0, 7.0)
const PLAYER_HALF_HEIGHT := 0.9
## Off-island positions wade at this depth below the water line instead of
## sinking to the seabed; presentation only, the server owns the position.
const WADE_DEPTH := 0.5
const MARKER_RADIUS := 0.3
## Coastal-bay local X/Z of the harbour ship in the gameplay view.
const GAMEPLAY_SHIP_MOORING := Vector2(1.0, -17.0)
var _ground: MeshInstance3D
var _coastal: Node3D
var _death: Label

func _build_scaffold_world() -> void:
	_ground = MeshInstance3D.new()
	_ground.name = "ScaffoldGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	_ground.mesh = plane
	_ground.material_override = _material(Color("#183b3a"))
	add_child(_ground)
	_mount_coastal_world()
	if _coastal:
		_ground.visible = false
	_recenter_ground()
	var player := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.height = 1.8
	capsule.radius = 0.35
	player.mesh = capsule
	player.material_override = _material(Color("#d9a441"))
	player.name = "ServerPlayerRepresentation"
	add_child(player)
	player.position = Vector3(_player.x, _feet_height(_player.x, _player.z) + PLAYER_HALF_HEIGHT, _player.z)
	_player = player.position
	if _coastal == null:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-55, -25, 0)
		light.light_energy = 1.2
		add_child(light)
	var camera := $Camera as Camera3D
	camera.current = true
	_follow_camera()

func _mount_coastal_world() -> void:
	var packed: PackedScene = load("res://scenes/realistic_coastal_slice.tscn")
	if packed == null:
		return
	_coastal = packed.instantiate()
	_coastal.name = "CoastalWorld"
	add_child(_coastal)
	var gameplay = _coastal.get("gameplay_camera")
	if gameplay is Camera3D:
		(gameplay as Camera3D).current = false
	var cinematic = _coastal.get("cinematic_camera")
	if cinematic is Camera3D:
		(cinematic as Camera3D).current = false
	# The bay's harbour ship is moored at local z -5.8 for the cinematic; from
	# the seaward follow camera its masts would stand between the camera and
	# the beach the player walks on, so the gameplay view moors it offshore.
	var ship = _coastal.get("ship_focal")
	if ship is Node3D:
		(ship as Node3D).position = Vector3(GAMEPLAY_SHIP_MOORING.x, (ship as Node3D).position.y, GAMEPLAY_SHIP_MOORING.y)
		# A moored ship leaves no wake; otherwise the ocean shader draws a
		# static wake trail from the hull towards the beach.
		var water := _coastal.get_node_or_null("ShallowToDeepWater") as MeshInstance3D
		if water and water.material_override is ShaderMaterial:
			(water.material_override as ShaderMaterial).set_shader_parameter("wake_strength", 0.0)
	for node in _coastal.find_children("*", "DirectionalLight3D", true, false):
		if node is DirectionalLight3D:
			(node as DirectionalLight3D).shadow_enabled = false

const CAMERA_OFFSET := Vector3(0, 28, 24)

# Keep the gameplay camera on the authoritative player so an account restored
# far from the origin is still on screen. Presentation only; no game state.
func _follow_camera() -> void:
	_recenter_ground()
	var camera: Camera3D = $Camera
	var target := Vector3(_player.x, _player.y - PLAYER_HALF_HEIGHT, _player.z)
	camera.look_at_from_position(target + CAMERA_OFFSET.rotated(Vector3.UP, _camera_yaw), target)
	_frame_player_in_play_area(camera)

func _on_viewport_resized() -> void:
	_frame_player_in_play_area($Camera)

## Shift the view sideways (Camera3D.h_offset, not the camera position or
## orbit pivot) so the player sits in the middle of the screen area left free
## by the HUD panel instead of at the panel's edge. Presentation only.
func _frame_player_in_play_area(camera: Camera3D) -> void:
	var screen := get_viewport().get_visible_rect().size
	var panel := get_node_or_null("Interface/Panel") as Control
	if screen.y <= 0.0 or panel == null or not panel.is_visible_in_tree():
		camera.h_offset = 0.0
		return
	var free_left := clampf(panel.get_global_rect().end.x, 0.0, screen.x * 0.6)
	var shift_px := (free_left + screen.x) * 0.5 - screen.x * 0.5
	var view_height := 2.0 * CAMERA_OFFSET.length() * tan(deg_to_rad(camera.fov) * 0.5)
	camera.h_offset = -shift_px * view_height / screen.y

# Snap the scaffold ground to the centre of the player's chunk (not the raw position, so it does not jitter
# every move). Presentation only; no game state.
func _recenter_ground() -> void:
	if _ground == null:
		return
	var chunk := _chunk_for_position(_player)
	_ground.position = Vector3((float(chunk.x) + 0.5) * CHUNK_SIZE, 0.0, (float(chunk.y) + 0.5) * CHUNK_SIZE)
	if _coastal == null:
		return
	var anchor := _ground.position - COASTAL_CHUNK_ANCHOR
	if _coastal.position.is_equal_approx(anchor):
		return
	_coastal.relocate(anchor)
	# The bay only moves when the player's chunk changes; keep everything that
	# is already on screen standing on the relocated terrain.
	for resource_id in _markers:
		var marker: Node3D = _markers[resource_id]
		marker.position.y = _surface_height(marker.position.x, marker.position.z) + MARKER_RADIUS
	var representation := get_node_or_null("ServerPlayerRepresentation") as Node3D
	if representation:
		_player.y = _feet_height(_player.x, _player.z) + PLAYER_HALF_HEIGHT
		representation.position = _player

## Visible surface at a server position mapped to world X/Z: the coastal
## terrain or the water line above it, or the flat scaffold at y = 0.
func _surface_height(x: float, z: float) -> float:
	if _coastal == null:
		return 0.0
	return maxf(_coastal.terrain_height_at(x, z), _coastal.water_level())

func _feet_height(x: float, z: float) -> float:
	if _coastal == null:
		return 0.0
	return maxf(_coastal.terrain_height_at(x, z), _coastal.water_level() - WADE_DEPTH)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	return material

func _on_transport_status(status: String) -> void:
	_status.text = status

func _on_authenticated(_user_id: String) -> void:
	_status.text = "Authenticated; awaiting server player position…"
	_session_live = true
	_reconnect_requested = false
	_enter_gameplay_hud()
	_apply_hud_layout()
	_configure_guild_objectives()
	_configure_expeditions()
	_configure_objectives()
	# The chunk is requested once the server reports where the player is.
	_chunk_known = false
	_chunk_in_flight = ""
	_refresh_clock = 0.0
	_stop_approach()

func _chunk_for_position(position: Vector3) -> Vector2i:
	return Vector2i(floori(position.x / CHUNK_SIZE), floori(position.z / CHUNK_SIZE))

func _request_current_chunk() -> void:
	if not _chunk_in_flight.is_empty():
		return
	var chunk := _chunk_for_position(_player)
	var request_id: String = _client.request_world_chunk(chunk.x, chunk.y)
	if request_id.is_empty():
		return
	_chunk = chunk
	_chunk_known = true
	_chunk_in_flight = request_id
	_refresh_clock = 0.0

func _process(delta: float) -> void:
	if _client == null or not _client.is_authenticated():
		if _session_live:
			# The session dropped: bring back the Reconnect control.
			_session_live = false
			_apply_hud_layout()
		_stop_approach()
		return
	_refresh_clock += delta
	if _chunk_known and _refresh_clock >= CHUNK_REFRESH_SECONDS:
		_refresh_clock = 0.0
		_request_current_chunk()
	if _manual_move_step(delta):
		return
	if _approaching:
		_move_clock += delta
		if _move_clock >= MOVE_INTERVAL_SECONDS:
			_move_clock = 0.0
			_approach_step()

func _stop_approach() -> void:
	_approaching = false
	_approach_target = ""
	_move_to_point = false

## One step of "walk to the target, then gather". Movement is only the existing
## server `move` intent; the server computes the position and the client keeps
## walking until the server-reported position is within gather range.
func _approach_step() -> void:
	if not _approaching:
		return
	if not _client.is_authenticated() or (not _move_to_point and not _markers.has(_approach_target)):
		_stop_approach()
		return
	var offset: Vector2
	if _move_to_point:
		offset = Vector2(_move_point.x - _player.x, _move_point.y - _player.z)
		if offset.length() <= MOVE_ARRIVE_DISTANCE:
			_stop_approach()
			return
	else:
		var marker: Node3D = _markers[_approach_target]
		offset = Vector2(marker.position.x - _player.x, marker.position.z - _player.z)
		if offset.length() <= GATHER_APPROACH_DISTANCE:
			var target := _approach_target
			_stop_approach()
			_send_gather(target)
			return
	var direction := offset.normalized()
	_client.request_move(direction.x, direction.y)

func _on_player_state(state: Dictionary) -> void:
	_craft.set_inventory(state.get("inventory"))
	var x = state.get("x")
	var y = state.get("y")
	if x is int or x is float:
		var world_y = y if y is int or y is float else 0
		# Server x/y map to world x/z unchanged; only the presentation height
		# comes from the coastal terrain once the bay sits on this chunk.
		_player = Vector3(float(x), _player.y, float(world_y))
		_recenter_ground()
		_player.y = _feet_height(_player.x, _player.z) + PLAYER_HALF_HEIGHT
		$ServerPlayerRepresentation.position = _player
		_follow_camera()
		var health = state.get("health", 1)
		if _death:
			_death.visible = (health is int or health is float) and float(health) <= 0.0
		_state.text = "Server player position: (%d, %d)" % [int(_player.x), int(_player.z)]
		# Follow the authoritative position: request the chunk containing the
		# player on first state and whenever the player crosses a boundary.
		if _client.is_authenticated() and (not _chunk_known or _chunk_for_position(_player) != _chunk):
			_chunk_in_flight = ""
			_request_current_chunk()

func _on_world_chunk(request_id: String, chunk: Dictionary) -> void:
	if request_id == _chunk_in_flight:
		_chunk_in_flight = ""
	# Ignore snapshots for a chunk the player is no longer in.
	var chunk_x = chunk.get("x")
	var chunk_y = chunk.get("y")
	if (chunk_x is int or chunk_x is float) and (chunk_y is int or chunk_y is float):
		if _chunk_known and Vector2i(int(chunk_x), int(chunk_y)) != _chunk:
			return
	_status.text = "Authoritative world chunk received"
	var current_ids: Dictionary = {}
	for resource in chunk.get("resources", []):
		if not resource is Dictionary:
			continue
		var resource_id = resource.get("id")
		if not resource_id is String:
			continue
		current_ids[resource_id] = true
		var marker: MeshInstance3D
		if _markers.has(resource_id):
			marker = _markers[resource_id]
		else:
			marker = _create_resource_marker(resource_id)
		var marker_x := float(resource.get("x", 0))
		var marker_z := float(resource.get("y", 0))
		marker.position = Vector3(marker_x, _surface_height(marker_x, marker_z) + MARKER_RADIUS, marker_z)
	# The server's chunk snapshot is authoritative: remove resources no longer
	# present, including depleted nodes, without retaining orphaned MeshInstances.
	for resource_id in _markers.keys():
		if not current_ids.has(resource_id):
			_markers[resource_id].queue_free()
			_markers.erase(resource_id)

func _create_resource_marker(resource_id: String) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.3
	sphere.height = 0.6
	marker.mesh = sphere
	marker.material_override = _material(Color("#67d4a3"))
	marker.name = "ServerResource_" + resource_id.replace(":", "_")
	add_child(marker)
	_markers[resource_id] = marker
	return marker

func _intent_for_ground(x: float, z: float) -> String:
	var resource_id := _resource_near(Vector2(x, z), TAP_RESOURCE_RADIUS)
	if resource_id != "":
		_begin_resource_approach(resource_id)
		return "gather"
	_begin_free_move(Vector2(x, z))
	return "move"

func _resource_near(xz: Vector2, radius: float) -> String:
	var best := ""
	var best_distance := radius
	for resource_id in _markers:
		var marker: Node3D = _markers[resource_id]
		var distance := Vector2(marker.position.x, marker.position.z).distance_to(xz)
		if distance <= best_distance:
			best_distance = distance
			best = resource_id
	return best

func _begin_free_move(xz: Vector2) -> void:
	if not _client.is_authenticated():
		_status.text = "Authenticate before issuing a server command"
		return
	_approaching = true
	_approach_target = ""
	_move_to_point = true
	_move_point = xz
	_move_clock = MOVE_INTERVAL_SECONDS
	_status.text = "Moving; server validates position"

func _begin_resource_approach(resource_id: String) -> void:
	if not _client.is_authenticated():
		_status.text = "Authenticate before issuing a server command"
		return
	if not _markers.has(resource_id):
		return
	var marker_position: Vector3 = _markers[resource_id].position
	if Vector2(marker_position.x - _player.x, marker_position.z - _player.z).length() > GATHER_APPROACH_DISTANCE:
		_approaching = true
		_move_to_point = false
		_approach_target = resource_id
		_move_clock = MOVE_INTERVAL_SECONDS
		_status.text = "Moving toward resource; server validates position"
		return
	_send_gather(resource_id)

const TAP_RAY_MAX_DISTANCE := 400.0
const TAP_RAY_STEP := 0.5

func _ground_point(screen: Vector2) -> Variant:
	var camera: Camera3D = $Camera
	var origin := camera.project_ray_origin(screen)
	var normal := camera.project_ray_normal(screen)
	if _coastal != null:
		return _surface_ray_hit(origin, normal)
	if absf(normal.y) < 0.0001:
		return null
	var distance := -origin.y / normal.y
	if distance < 0.0:
		return null
	return origin + normal * distance

## First crossing of the camera ray with the visible terrain/water surface.
## Bounded march plus bisection, run only on a tap; no physics bodies needed.
func _surface_ray_hit(origin: Vector3, normal: Vector3) -> Variant:
	var previous := 0.0
	var distance := TAP_RAY_STEP
	while distance <= TAP_RAY_MAX_DISTANCE:
		var point := origin + normal * distance
		if point.y <= _surface_height(point.x, point.z):
			var low := previous
			var high := distance
			for _i in range(12):
				var mid := (low + high) * 0.5
				var probe := origin + normal * mid
				if probe.y <= _surface_height(probe.x, probe.z):
					high = mid
				else:
					low = mid
			return origin + normal * high
		previous = distance
		distance += TAP_RAY_STEP
	return null

func _handle_tap(screen: Vector2) -> void:
	var point: Variant = _ground_point(screen)
	if point == null:
		return
	var world: Vector3 = point
	_intent_for_ground(world.x, world.z)

func _http_base(endpoint: String) -> String:
	if not _client._is_safe_authenticated_url(endpoint) or not endpoint.ends_with("/ws"):
		return ""
	if endpoint.begins_with("wss://"):
		return "https://" + endpoint.substr(6).trim_suffix("/ws")
	if endpoint.begins_with("ws://"):
		return "http://" + endpoint.substr(5).trim_suffix("/ws")
	return ""

func _on_auth_failed(reason: String) -> void:
	if _refreshing:
		return
	if reason == "INVALID_TOKEN" and not _refresh_token.is_empty():
		_refreshing = true
		_status.text = "Session expired. Refreshing…"
		_request_refresh()
		return
	_return_to_login(reason)

func _request_refresh() -> void:
	var base := _http_base(_handoff_endpoint)
	if base.is_empty():
		_return_to_login("INVALID_TOKEN")
		return
	if _refresh_http == null:
		_refresh_http = HTTPRequest.new()
		_refresh_http.timeout = 15.0
		_refresh_http.max_redirects = 0
		add_child(_refresh_http)
		_refresh_http.request_completed.connect(_on_refresh_completed)
	var error := _refresh_http.request(
		base + "/auth/refresh",
		PackedStringArray(["Content-Type: application/json", "Accept: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify({"refreshToken": _refresh_token}))
	if error != OK:
		_return_to_login("INVALID_TOKEN")

func _on_refresh_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_refreshing = false
	var decoded = JSON.parse_string(body.get_string_from_utf8())
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300 or not (decoded is Dictionary):
		_return_to_login("INVALID_TOKEN")
		return
	var access = decoded.get("accessToken", "")
	var refresh = decoded.get("refreshToken", "")
	if not (access is String) or access.is_empty() or not (refresh is String) or refresh.is_empty():
		_return_to_login("INVALID_TOKEN")
		return
	_handoff_token = access
	_refresh_token = refresh
	_token.text = ""
	_client.configure(_handoff_endpoint, access)
	_client.connect_to_server()
	_status.text = "Session refreshed. Reconnecting…"

# Guild objectives use the WebSocket session's HTTP base and current access token.
func _configure_guild_objectives() -> void:
	var base := ""
	if _client.has_method("_is_safe_authenticated_url"):
		base = _http_base(_handoff_endpoint)
	_guild_objectives.configure(base, _handoff_token)
	_guild_objectives.refresh(true)

# Expeditions use the WebSocket session's HTTP base and current access token.
func _configure_expeditions() -> void:
	var base := ""
	if _client.has_method("_is_safe_authenticated_url"):
		base = _http_base(_handoff_endpoint)
	_expeditions.configure(base, _handoff_token)
	_expeditions.refresh()

# Daily objectives use the same server as the WebSocket session and its current
# access token. Unsafe or unknown endpoints leave the panel unconfigured.
func _configure_objectives() -> void:
	var base := ""
	if _client.has_method("_is_safe_authenticated_url"):
		base = _http_base(_handoff_endpoint)
	_objectives.configure(base, _handoff_token)
	_objectives.refresh(true)

func _return_to_login(reason: String) -> void:
	_refreshing = false
	_stop_approach()
	var boot = load("res://scenes/boot.tscn").instantiate()
	get_tree().root.add_child(boot)
	get_tree().current_scene = boot
	if boot.has_method("show_signed_out"):
		boot.show_signed_out(reason)
	queue_free()

func _gather_nearest() -> void:
	if _markers.is_empty():
		_status.text = "No server-visible resource in this chunk"
		return
	var nearest_id := ""
	var nearest_distance := INF
	for resource_id in _markers:
		var marker: Node3D = _markers[resource_id]
		# Server range is planar x/y; presentation heights must not reorder it.
		var distance := Vector2(marker.position.x - _player.x, marker.position.z - _player.z).length()
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_id = resource_id
	_begin_resource_approach(nearest_id)

func _send_gather(nearest_id: String) -> void:
	var request_id: String = _client.request_gather(nearest_id)
	_status.text = "Awaiting server gather ACK (%s)" % request_id if not request_id.is_empty() else "Command window unavailable"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_handle_tap(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.device != -1:
		_handle_tap(event.position)

func _on_ack(_request_id: String, message: Dictionary) -> void:
	if message.get("type") == "craft_result":
		_craft.on_craft_ack(_request_id, message)
		return
	if message.get("type") == "resource_gathered":
		# Guild progress is server-derived from the gather ledger; re-read it (rate bounded).
		_guild_objectives.refresh()

		# Progress is server-derived from the gather ledger; re-read it (rate bounded).
		_objectives.refresh()
		var resource_id = message.get("resourceId")
		if resource_id is String and _markers.has(resource_id):
			_markers[resource_id].queue_free()
			_markers.erase(resource_id)
		_status.text = "Server ACK: resource persisted; local view refreshed"
		var state = message.get("state")
		if state is Dictionary:
			_craft.set_inventory(state.get("inventory"))
			_state.text = "Authoritative inventory state received"

## Bound the scroll area to 45% of the visible height (at least 180 px) so
## the fixed controls above it plus the scroll area fit on screen.
func _fit_hud_scroll() -> void:
	if _hud_scroll == null:
		return
	var visible_height := get_viewport().get_visible_rect().size.y
	_hud_scroll.custom_minimum_size = Vector2(0.0, maxf(180.0, visible_height * 0.45))

func _on_rejection(code: String) -> void:
	_craft.on_server_error(code)
	if code == "PLAYER_DEAD" and _death:
		_death.visible = true
		_death.text = "You died - respawning"
	_status.text = "Server rejected command: %s" % code

func _on_outcome_unknown(request_id: String) -> void:
	_craft.on_outcome_unknown(request_id)
	if request_id == _chunk_in_flight:
		_chunk_in_flight = ""
	_status.text = "Command outcome unknown; reconnect manually before retrying"
	_reconnect_requested = true
	_apply_hud_layout()
