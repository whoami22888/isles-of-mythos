# Daily objectives HUD. Presentation only: progress and rewards come from the
# server (GET /daily-objectives, POST /daily-objectives/claim). The client never
# reports progress; it only asks the server to pay a completed objective.
extends VBoxContainer

signal reward_claimed(objective_id: String, reward_gold: String)

const LABELS := {
	"gather.wood": "Gather wood",
	"gather.stone": "Gather stone",
	"craft.any": "Craft items",
}
const MIN_REFRESH_INTERVAL_MS := 2000

# (method, path, body_or_null) -> void. Replaced in tests; defaults to HTTPRequest.
var request_sender: Callable
var _base_url := ""
var _token := ""
var _rows: Dictionary = {}
var _title: Label
var _list_in_flight := false
var _claims_in_flight: Dictionary = {}
var _last_refresh_ms := -MIN_REFRESH_INTERVAL_MS
var _http_list: HTTPRequest
var _http_claim: HTTPRequest
var _pending_claim := ""

func _ready() -> void:
	_title = Label.new()
	_title.text = "Daily objectives"
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
	request_sender.call(HTTPClient.METHOD_GET, "/daily-objectives", null)
	return true

func claim(objective_id: String) -> bool:
	if not is_configured() or _claims_in_flight.has(objective_id) or not _claims_in_flight.is_empty():
		return false
	var row = _rows.get(objective_id)
	if row == null or not row["complete"] or row["claimed"]:
		return false
	_claims_in_flight[objective_id] = true
	(row["button"] as Button).disabled = true
	request_sender.call(HTTPClient.METHOD_POST, "/daily-objectives/claim", {"objectiveId": objective_id})
	return true

func on_list_response(code: int, body: Variant) -> void:
	_list_in_flight = false
	if code != 200 or not (body is Dictionary) or not (body.get("objectives") is Array):
		_title.text = "Daily objectives (unavailable)"
		return
	_title.text = "Daily objectives"
	for entry in body["objectives"]:
		if entry is Dictionary:
			_apply_row(entry)

func on_claim_response(objective_id: String, code: int, body: Variant) -> void:
	_claims_in_flight.erase(objective_id)
	var row = _rows.get(objective_id)
	if row == null:
		return
	if code == 200 and body is Dictionary and body.get("objectiveId") == objective_id:
		row["claimed"] = true
		_render_row(objective_id)
		reward_claimed.emit(objective_id, str(body.get("rewardGold", "0")))
		return
	# 409 (not yet complete) or a transport error: re-read the server's view.
	_render_row(objective_id)
	refresh(true)

func row_text(objective_id: String) -> String:
	var row = _rows.get(objective_id)
	return "" if row == null else (row["label"] as Label).text

func claim_enabled(objective_id: String) -> bool:
	var row = _rows.get(objective_id)
	return row != null and not (row["button"] as Button).disabled

func _apply_row(entry: Dictionary) -> void:
	var id = entry.get("objectiveId")
	if not (id is String) or not LABELS.has(id):
		return
	if not _rows.has(id):
		var line := HBoxContainer.new()
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var button := Button.new()
		button.text = "Claim"
		button.custom_minimum_size = Vector2(96, 44)
		button.pressed.connect(claim.bind(id))
		line.add_child(label)
		line.add_child(button)
		add_child(line)
		_rows[id] = {"label": label, "button": button}
	var row: Dictionary = _rows[id]
	row["progress"] = int(entry.get("progress", 0))
	row["target"] = int(entry.get("target", 0))
	row["complete"] = entry.get("complete") == true
	row["claimed"] = entry.get("claimed") == true
	row["reward"] = str(entry.get("rewardGold", "0"))
	_render_row(id)

func _render_row(id: String) -> void:
	var row: Dictionary = _rows[id]
	var suffix := "claimed" if row["claimed"] else "+%s gold" % row["reward"]
	(row["label"] as Label).text = "%s %d/%d (%s)" % [LABELS[id], row["progress"], row["target"], suffix]
	var button := row["button"] as Button
	button.disabled = not row["complete"] or row["claimed"] or _claims_in_flight.has(id)
	button.text = "Claimed" if row["claimed"] else "Claim"

func _send_http(method: int, path: String, body: Variant) -> void:
	var headers := PackedStringArray(["Accept: application/json", "Authorization: Bearer " + _token])
	if method == HTTPClient.METHOD_GET:
		if _http_list == null:
			_http_list = _make_http(_on_http_list)
		if _http_list.request(_base_url + path, headers, method) != OK:
			on_list_response(0, null)
		return
	if _http_claim == null:
		_http_claim = _make_http(_on_http_claim)
	_pending_claim = str(body.get("objectiveId", ""))
	headers.append("Content-Type: application/json")
	if _http_claim.request(_base_url + path, headers, method, JSON.stringify(body)) != OK:
		on_claim_response(_pending_claim, 0, null)

func _make_http(handler: Callable) -> HTTPRequest:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	http.max_redirects = 0
	add_child(http)
	http.request_completed.connect(handler)
	return http

func _on_http_list(result: int, code: int, _headers: PackedStringArray, raw: PackedByteArray) -> void:
	on_list_response(code if result == HTTPRequest.RESULT_SUCCESS else 0, JSON.parse_string(raw.get_string_from_utf8()))

func _on_http_claim(result: int, code: int, _headers: PackedStringArray, raw: PackedByteArray) -> void:
	on_claim_response(_pending_claim, code if result == HTTPRequest.RESULT_SUCCESS else 0, JSON.parse_string(raw.get_string_from_utf8()))
