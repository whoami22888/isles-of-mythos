# Weekly guild objective HUD. Presentation only: guild progress, the player's own
# contribution and eligibility come from the server (GET /guild-objectives). The client
# only asks the server to pay a claim; it never reports progress.
extends VBoxContainer

signal reward_claimed(objective_id: String, reward_gold: String)

const LABELS := {"guild.wood": "Guild wood"}
const MIN_REFRESH_INTERVAL_MS := 2000

# (method, path, body_or_null) -> void. Replaced in tests; defaults to HTTPRequest.
var request_sender: Callable
var _base_url := ""
var _token := ""
var _title: Label
var _rows: Dictionary = {}
var _list_in_flight := false
var _claim_in_flight := ""
var _last_refresh_ms := -MIN_REFRESH_INTERVAL_MS
var _in_guild := false
var _http_list: HTTPRequest
var _http_claim: HTTPRequest

func _ready() -> void:
	_title = Label.new()
	_title.text = "Guild objectives"
	add_child(_title)
	if not request_sender.is_valid():
		request_sender = _send_http

func configure(base_url: String, token: String) -> void:
	_base_url = base_url
	_token = token

func is_configured() -> bool:
	return not _base_url.is_empty() and not _token.is_empty()

func refresh(force: bool = false) -> bool:
	if not is_configured() or _list_in_flight:
		return false
	var now := Time.get_ticks_msec()
	if not force and now - _last_refresh_ms < MIN_REFRESH_INTERVAL_MS:
		return false
	_last_refresh_ms = now
	_list_in_flight = true
	request_sender.call(HTTPClient.METHOD_GET, "/guild-objectives", null)
	return true

func claim(objective_id: String) -> bool:
	if not is_configured() or not _claim_in_flight.is_empty():
		return false
	var row = _rows.get(objective_id)
	if row == null or not row["eligible"] or row["claimed"]:
		return false
	_claim_in_flight = objective_id
	_render(objective_id)
	request_sender.call(HTTPClient.METHOD_POST, "/guild-objectives/claim", {"objectiveId": objective_id})
	return true

func on_list_response(code: int, body: Variant) -> void:
	_list_in_flight = false
	if code != 200 or not (body is Dictionary) or not (body.get("objectives") is Array):
		_title.text = "Guild objectives (unavailable)"
		return
	_in_guild = body.get("guildId") is String
	_title.text = "Guild objectives" if _in_guild else "Guild objectives (join a guild)"
	for entry in body["objectives"]:
		if entry is Dictionary:
			_apply(entry)

func on_claim_response(code: int, body: Variant) -> void:
	var id := _claim_in_flight
	_claim_in_flight = ""
	var row = _rows.get(id)
	if row == null:
		return
	if code == 200 and body is Dictionary and body.get("objectiveId") == id:
		row["claimed"] = true
		_render(id)
		reward_claimed.emit(id, str(body.get("rewardGold", "0")))
		return
	# 409 (incomplete, not enough contribution, left the guild) or error: re-read the server.
	_render(id)
	refresh(true)

func row_text(objective_id: String) -> String:
	var row = _rows.get(objective_id)
	return "" if row == null else (row["label"] as Label).text

func claim_enabled(objective_id: String) -> bool:
	var row = _rows.get(objective_id)
	return row != null and not (row["button"] as Button).disabled

func _apply(entry: Dictionary) -> void:
	var id = entry.get("objectiveId")
	if not (id is String) or not LABELS.has(id):
		return
	if not _rows.has(id):
		var line := HBoxContainer.new()
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var button := Button.new()
		button.custom_minimum_size = Vector2(96, 44)
		button.pressed.connect(claim.bind(id))
		line.add_child(label)
		line.add_child(button)
		add_child(line)
		_rows[id] = {"label": label, "button": button}
	var row: Dictionary = _rows[id]
	row["progress"] = int(entry.get("guildProgress", 0))
	row["target"] = int(entry.get("target", 0))
	row["mine"] = int(entry.get("myContribution", 0))
	row["min"] = int(entry.get("minContribution", 0))
	row["eligible"] = entry.get("eligible") == true
	row["claimed"] = entry.get("claimed") == true
	row["reward"] = str(entry.get("rewardGold", "0"))
	_render(id)

func _render(id: String) -> void:
	var row: Dictionary = _rows[id]
	var status := "claimed" if row["claimed"] else "+%s gold" % row["reward"]
	if not row["claimed"] and row["mine"] < row["min"]:
		status = "add %d more yourself" % (row["min"] - row["mine"])
	(row["label"] as Label).text = "%s %d/%d · you %d (%s)" % [LABELS[id], row["progress"], row["target"], row["mine"], status]
	var button := row["button"] as Button
	button.disabled = not row["eligible"] or row["claimed"] or not _claim_in_flight.is_empty()
	button.text = "Claimed" if row["claimed"] else "Claim"

func _send_http(method: int, path: String, body: Variant) -> void:
	var headers := PackedStringArray(["Accept: application/json", "Authorization: Bearer " + _token])
	if method == HTTPClient.METHOD_GET:
		if _http_list == null:
			_http_list = _make_http(func(r, c, _h, raw): on_list_response(c if r == HTTPRequest.RESULT_SUCCESS else 0, JSON.parse_string(raw.get_string_from_utf8())))
		if _http_list.request(_base_url + path, headers, method) != OK:
			on_list_response(0, null)
		return
	if _http_claim == null:
		_http_claim = _make_http(func(r, c, _h, raw): on_claim_response(c if r == HTTPRequest.RESULT_SUCCESS else 0, JSON.parse_string(raw.get_string_from_utf8())))
	headers.append("Content-Type: application/json")
	if _http_claim.request(_base_url + path, headers, method, JSON.stringify(body)) != OK:
		on_claim_response(0, null)

func _make_http(handler: Callable) -> HTTPRequest:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	http.max_redirects = 0
	add_child(http)
	http.request_completed.connect(handler)
	return http
