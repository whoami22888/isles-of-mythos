class_name IslesAuthoritativeCommandGateway
extends "res://scripts/websocket_adapter.gd"

## Client presentation only; Fastify/PostgreSQL owns all gameplay state.
## Never automatically replay a mutation with an ambiguous outcome.
signal authenticated(user_id: String)
signal request_acknowledged(request_id: String, message: Dictionary)
signal request_rejected(request_id: String, code: String)
signal request_outcome_unknown(request_id: String, reason: String)
signal server_error(code: String)

const MAX_PENDING := 32
const REQUEST_TIMEOUT_MS := 30000
# This is an intentionally small, explicit IOM-03 command surface.  It contains
# the read-only queries and the server-authorized build/resource flows needed by
# the first Godot client slice.  New protocol messages must be added here with
# matching validation; a regex is not a protocol allow-list.
const COMMAND_FIELDS := {
	"get_guild": [],
	"list_guild_invitations": [],
	"list_realms": [],
	"list_territories": [],
	"list_realm_fortresses": [],
	"my_realm_reputation": [],
	"list_trade_routes": [],
	"list_breeding": [],
	"list_armies": [],
	"list_ships": [],
	"list_fleets": [],
	"list_friends": [],
	"list_blocks": [],
	"get_party": [],
	"party_invitations": [],
	"auction_history": [],
	"list_world_events": [],
	"list_realm_wars": [],
	"list_guild_battles": [],
	"list_endgame_creatures": [],
	"list_mythic_content": [],
	"list_territory_season": [],
	"gather_resource": ["resourceId"],
	"capture": ["targetId"],
	"tame": ["creatureId"],
	"create_base": ["name", "x", "y"],
	"build": ["buildingType", "level", "gridX", "gridY"],
	"get_invasion_waves": ["invasionId"],
	"territory_at": ["x", "y"],
	"ship_inventory": ["shipId"],
	"chat_history": ["channel", "recipientUserId", "guildId", "partyId"],
	"auction_list": ["itemId", "rarity", "category", "minLevel", "maxLevel", "minPrice", "maxPrice"]
}

const RESPONSE_TYPES := [
	"server_ready", "pong", "auth_ok", "player_state", "resource_gathered", "world_chunk",
	"projectile_spawn", "combat_result", "creature_state", "creature_party", "base_state",
	"building_state", "craft_result", "shop_purchase_result", "trade_result", "breeding_started",
	"breeding_jobs", "guild_state", "guild_invitations", "guild_bank_state", "guild_operation_ok",
	"realm_list", "territory_list", "fortress_list", "territory_state", "realm_reputation",
	"trade_route_state", "trade_route_list", "realm_operation_ok", "invasion_list", "invasion_waves",
	"invasion_state", "invasion_operation_ok", "army_state", "army_list", "army_training",
	"army_operation_ok", "battle_state", "defense_state", "defense_list", "ship_state", "ship_list",
	"ship_inventory", "ship_crew", "fleet_state", "fleet_list", "naval_combat_result", "friends_list",
	"blocks_list", "social_operation_ok", "social_reported", "chat_message", "chat_history", "party_state",
	"party_invitations", "party_operation_ok", "auction_list", "auction_state", "auction_history",
	"auction_operation_ok", "world_event_list", "world_event_state", "world_event_reward", "realm_war_list",
	"realm_war_state", "guild_battle_list", "guild_battle_state", "endgame_creature_list",
	"endgame_creature_state", "mythic_content_list", "territory_season_state", "error"
]

var _pending: Dictionary = {}
var _crypto := Crypto.new()
var _action_pattern := RegEx.new()

func _ready() -> void:
	_action_pattern.compile("^[a-z][a-z0-9_]{0,63}$")
	message_received.connect(_on_protocol_message)

func connect_to_server() -> void:
	# A new socket cannot prove the outcome of commands already in flight.
	_fail_pending("reconnect")
	super.connect_to_server()

func _process(delta: float) -> void:
	super._process(delta)
	if not _attempt_active and not _pending.is_empty():
		_fail_pending("connection_lost")
	var now := Time.get_ticks_msec()
	var expired: Array = []
	for request_id in _pending.keys():
		if now - int(_pending[request_id]) >= REQUEST_TIMEOUT_MS:
			expired.append(request_id)
	for request_id in expired:
		_pending.erase(request_id)
		request_outcome_unknown.emit(str(request_id), "reply_timeout")

func is_authenticated() -> bool:
	return _authenticated and _attempt_active and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN

func pending_count() -> int:
	return _pending.size()

func send_request(action: String, fields: Dictionary = {}) -> String:
	if not is_authenticated():
		return ""
	if _pending.size() >= MAX_PENDING:
		return ""
	if _action_pattern.search(action) == null or not COMMAND_FIELDS.has(action):
		return ""
	if not _valid_fields(action, fields):
		return ""
	var request_id := _crypto.generate_random_bytes(16).hex_encode()
	if request_id.is_empty() or _pending.has(request_id):
		return ""
	var message: Dictionary = _normalized_fields(action, fields)
	message["type"] = action
	message["requestId"] = request_id
	# UI must wait for a correlated server acknowledgement before displaying success.
	var send_error := _socket.send_text(JSON.stringify(message))
	if send_error != OK:
		request_outcome_unknown.emit(request_id, "send_failed")
		return ""
	_pending[request_id] = Time.get_ticks_msec()
	return request_id

func _on_protocol_message(message: Dictionary) -> void:
	var message_type = message.get("type")
	if not message_type is String:
		return
	if message_type == "auth_ok":
		var user_id = message.get("userId")
		if _auth_sent and user_id is String and not user_id.is_empty():
			_authenticated = true
			authenticated.emit(user_id)
		return
	var request_id = message.get("requestId")
	if message_type == "error":
		var code = message.get("code")
		if not code is String or code.is_empty() or code.length() > 64:
			return
		if request_id is String and request_id.length() <= 64 and _pending.has(request_id):
			_pending.erase(request_id)
			request_rejected.emit(request_id, code)
			return
		# No requestId, or one we are not waiting on: never guess which mutation failed.
		server_error.emit(code)
		return
	if not is_authenticated() or not RESPONSE_TYPES.has(message_type):
		return
	if request_id is String and request_id.length() <= 64 and _pending.has(request_id):
		_pending.erase(request_id)
		request_acknowledged.emit(request_id, message)

func _fail_pending(reason: String) -> void:
	if _pending.is_empty():
		return
	var ids: Array = _pending.keys()
	_pending.clear()
	for request_id in ids:
		request_outcome_unknown.emit(str(request_id), reason)

func _valid_fields(action: String, fields: Dictionary) -> bool:
	if fields.has("type") or fields.has("requestId"):
		return false
	var allowed: Array = COMMAND_FIELDS[action]
	for key in fields.keys():
		if not key is String or not allowed.has(key):
			return false
	# The server remains authoritative for values and permissions.  These checks
	# only prevent malformed wire messages and accidental client-side authority.
	match action:
		"gather_resource", "capture", "tame", "get_invasion_waves", "ship_inventory":
			return _non_empty_string(fields, allowed[0], 128)
		"create_base":
			return _non_empty_string(fields, "name", 64) and _bounded_int(fields, "x", -1000000, 1000000) and _bounded_int(fields, "y", -1000000, 1000000)
		"build":
			return _non_empty_string(fields, "buildingType", 32) and _bounded_int(fields, "level", 0, 100) and _bounded_int(fields, "gridX", -128, 128) and _bounded_int(fields, "gridY", -128, 128)
		"territory_at":
			return _bounded_int(fields, "x", -1000000, 1000000) and _bounded_int(fields, "y", -1000000, 1000000)
		"chat_history":
			return _enum_string(fields, "channel", ["local", "region", "party", "guild", "trade", "global", "system", "whisper"]) and _nullable_string(fields, "recipientUserId", 64) and _nullable_string(fields, "guildId", 64) and _nullable_string(fields, "partyId", 64)
		"auction_list":
			return _nullable_string(fields, "itemId", 64) and _nullable_string(fields, "rarity", 32) and _nullable_string(fields, "category", 32) and _nullable_int(fields, "minLevel") and _nullable_int(fields, "maxLevel") and _nullable_string(fields, "minPrice", 32) and _nullable_string(fields, "maxPrice", 32)
	return fields.is_empty()

func _non_empty_string(fields: Dictionary, key: String, limit: int) -> bool:
	var value = fields.get(key)
	return value is String and not value.is_empty() and value.length() <= limit

func _nullable_string(fields: Dictionary, key: String, limit: int) -> bool:
	var value = fields.get(key)
	return value == null or (value is String and value.length() <= limit)

func _bounded_int(fields: Dictionary, key: String, minimum: int, maximum: int) -> bool:
	var value = fields.get(key)
	return value is int and value >= minimum and value <= maximum

func _nullable_int(fields: Dictionary, key: String) -> bool:
	var value = fields.get(key)
	return value == null or value is int

func _enum_string(fields: Dictionary, key: String, values: Array) -> bool:
	var value = fields.get(key)
	return value is String and values.has(value)

func _normalized_fields(action: String, fields: Dictionary) -> Dictionary:
	var normalized: Dictionary = fields.duplicate(true)
	if action == "chat_history":
		for key in ["recipientUserId", "guildId", "partyId"]:
			if not normalized.has(key):
				normalized[key] = null
	elif action == "auction_list":
		for key in ["itemId", "rarity", "category", "minLevel", "maxLevel", "minPrice", "maxPrice"]:
			if not normalized.has(key):
				normalized[key] = null
	return normalized
