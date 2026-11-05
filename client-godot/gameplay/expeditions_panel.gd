# Ship expeditions HUD. Presentation only: routes, ships, durations and rewards come
# from the server (GET /expeditions). The client sends ship + route + a fresh request
# id to start, and an expedition id to collect; the server decides everything else.
extends VBoxContainer

signal expedition_collected(expedition_id: String, gold: String)

# (method, path, body_or_null) -> void. Replaced in tests; defaults to HTTPRequest.
var request_sender: Callable
# Returns the current unix time; replaced in tests.
var clock: Callable = func() -> float: return Time.get_unix_time_from_system()
var _base_url := ""
var _token := ""
var _title: Label
var _list_in_flight := false
var _action_in_flight := ""
var _ships: Array = []
var _routes: Array = []
var _expeditions: Array = []
var _rows: Dictionary = {}
var _http_list: HTTPRequest
var _http_action: HTTPRequest
var _pending_action := {}

func _ready() -> void:
	_title = Label.new()
	_title.text = "Expeditions"
	add_child(_title)
	if not request_sender.is_valid():
		request_sender = _send_http

func configure(base_url: String, token: String) -> void:
	_base_url = base_url
	_token = token

func is_configured() -> bool:
	return not _base_url.is_empty() and not _token.is_empty()

func refresh() -> bool:
	if not is_configured() or _list_in_flight:
		return false
	_list_in_flight = true
	request_sender.call(HTTPClient.METHOD_GET, "/expeditions", null)
	return true

func free_ship_id() -> String:
	for ship in _ships:
		if ship is Dictionary and ship.get("status") == "active" and ship.get("shipId") is String:
			return ship["shipId"]
	return ""

func start(route_id: String) -> bool:
	var ship_id := free_ship_id()
	if not is_configured() or not _action_in_flight.is_empty() or ship_id.is_empty() or not _has_route(route_id):
		return false
	_action_in_flight = "start"
	var body := {"shipId": ship_id, "routeId": route_id, "requestId": "exp-" + Crypto.new().generate_random_bytes(12).hex_encode()}
	_pending_action = {"kind": "start"}
	request_sender.call(HTTPClient.METHOD_POST, "/expeditions/start", body)
	_render()
	return true

func collect(expedition_id: String) -> bool:
	if not is_configured() or not _action_in_flight.is_empty() or not can_collect(expedition_id):
		return false
	_action_in_flight = expedition_id
	_pending_action = {"kind": "collect", "id": expedition_id}
	request_sender.call(HTTPClient.METHOD_POST, "/expeditions/collect", {"expeditionId": expedition_id})
	_render()
	return true

func can_collect(expedition_id: String) -> bool:
	var exp = _find(expedition_id)
	return exp != null and exp.get("collectedAt") == null and seconds_left(expedition_id) <= 0

func seconds_left(expedition_id: String) -> int:
	var exp = _find(expedition_id)
	if exp == null:
		return -1
	return maxi(0, int(ceil(_parse_iso(str(exp.get("returnsAt", ""))) - clock.call())))

func on_list_response(code: int, body: Variant) -> void:
	_list_in_flight = false
	if code != 200 or not (body is Dictionary):
		_title.text = "Expeditions (unavailable)"
		return
	_title.text = "Expeditions"
	_routes = body.get("routes", []) if body.get("routes") is Array else []
	_ships = body.get("ships", []) if body.get("ships") is Array else []
	_expeditions = body.get("expeditions", []) if body.get("expeditions") is Array else []
	_render()

func on_action_response(code: int, body: Variant) -> void:
	var action: Dictionary = _pending_action
	_action_in_flight = ""
	_pending_action = {}
	if action.get("kind") == "collect" and code == 200 and body is Dictionary and body.get("expeditionId") == action.get("id"):
		var gold := "0"
		if body.get("reward") is Dictionary:
			gold = str(body["reward"].get("gold", "0"))
		expedition_collected.emit(action["id"], gold)
	# Success or refusal (409 early / ship busy): always re-read the server's view.
	refresh()

func row_text(key: String) -> String:
	var row = _rows.get(key)
	return "" if row == null else (row["label"] as Label).text

func button_enabled(key: String) -> bool:
	var row = _rows.get(key)
	return row != null and not (row["button"] as Button).disabled

func tick() -> void:
	_render()

func _process(_delta: float) -> void:
	if not _expeditions.is_empty():
		_render()

func _has_route(route_id: String) -> bool:
	for route in _routes:
		if route is Dictionary and route.get("routeId") == route_id:
			return true
	return false

func _find(expedition_id: String):
	for exp in _expeditions:
		if exp is Dictionary and exp.get("expeditionId") == expedition_id:
			return exp
	return null

func _render() -> void:
	var seen := {}
	for route in _routes:
		if not (route is Dictionary) or not (route.get("routeId") is String):
			continue
		var key := "route:" + str(route["routeId"])
		seen[key] = true
		var row := _row(key, "Sail", start.bind(route["routeId"]))
		(row["label"] as Label).text = "%s · %ds · +%s gold" % [route["routeId"], int(route.get("durationSeconds", 0)), str(route.get("gold", "0"))]
		(row["button"] as Button).disabled = free_ship_id().is_empty() or not _action_in_flight.is_empty()
	for exp in _expeditions:
		if not (exp is Dictionary) or not (exp.get("expeditionId") is String) or exp.get("collectedAt") != null:
			continue
		var id: String = exp["expeditionId"]
		var key := "exp:" + id
		seen[key] = true
		var row := _row(key, "Collect", collect.bind(id))
		var left := seconds_left(id)
		(row["label"] as Label).text = "%s · %s" % [str(exp.get("routeId", "")), "returned" if left <= 0 else "%ds left" % left]
		(row["button"] as Button).disabled = not can_collect(id) or not _action_in_flight.is_empty()
	for key in _rows.keys():
		if not seen.has(key):
			(_rows[key]["line"] as Node).queue_free()
			_rows.erase(key)

func _row(key: String, action: String, handler: Callable) -> Dictionary:
	if _rows.has(key):
		return _rows[key]
	var line := HBoxContainer.new()
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var button := Button.new()
	button.text = action
	button.custom_minimum_size = Vector2(96, 44)
	button.pressed.connect(handler)
	line.add_child(label)
	line.add_child(button)
	add_child(line)
	_rows[key] = {"line": line, "label": label, "button": button}
	return _rows[key]

static func _parse_iso(value: String) -> float:
	# "2026-11-05T08:00:00.679Z" -> unix seconds (UTC) including the fraction, so
	# the client never treats an expedition as returned before the server does.
	if value.length() < 19:
		return 0.0
	var seconds := float(Time.get_unix_time_from_datetime_string(value.substr(0, 19)))
	if value.length() > 20 and value[19] == ".":
		var digits := ""
		for i in range(20, value.length()):
			if not value[i].is_valid_int():
				break
			digits += value[i]
		if not digits.is_empty():
			seconds += float("0." + digits)
	return seconds

func _send_http(method: int, path: String, body: Variant) -> void:
	var headers := PackedStringArray(["Accept: application/json", "Authorization: Bearer " + _token])
	if method == HTTPClient.METHOD_GET:
		if _http_list == null:
			_http_list = _make_http(func(r, c, _h, raw): on_list_response(c if r == HTTPRequest.RESULT_SUCCESS else 0, JSON.parse_string(raw.get_string_from_utf8())))
		if _http_list.request(_base_url + path, headers, method) != OK:
			on_list_response(0, null)
		return
	if _http_action == null:
		_http_action = _make_http(func(r, c, _h, raw): on_action_response(c if r == HTTPRequest.RESULT_SUCCESS else 0, JSON.parse_string(raw.get_string_from_utf8())))
	headers.append("Content-Type: application/json")
	if _http_action.request(_base_url + path, headers, method, JSON.stringify(body)) != OK:
		on_action_response(0, null)

func _make_http(handler: Callable) -> HTTPRequest:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	http.max_redirects = 0
	add_child(http)
	http.request_completed.connect(handler)
	return http
