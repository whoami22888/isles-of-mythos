extends SceneTree

# MYTHOS-NET-05: headless Godot client against a REAL Fastify server (driven by
# server/src/creature-snapshot.godot-e2e.test.ts). No mock transport.
#
# Args after `--`: <ws url> <access token> <expected creature count> <sha256 of ids joined by "\n">
#
# Uses ONLY the production IslesWebSocketAdapter (which owns snapshot reassembly); the harness
# never builds an assembler, so this proves what a real consumer of message_received sees.
#
# Flow:
#   1. Connect. The test server cuts this first connection after a few snapshot frames. The
#      client must receive NO creature_party at all (no partial emission), then "Disconnected".
#   2. Reconnect (explicit connect_to_server). The server re-sends a fresh snapshot after
#      authentication; the client must receive exactly ONE complete creature_party with the
#      expected count, unique ids and order-sensitive SHA-256 of ids, and nothing further.

const Adapter = preload("res://scripts/websocket_adapter.gd")

var _adapter
var _expected_count := 0
var _expected_hash := ""
var _phase := 1
var _completes: Array = []
var _errors: Array = []
var _disconnected_phase1 := false
var _parties_phase1 := 0
var _settle_until_ms := 0
var _deadline_ms := 0
var _finished := false

func _init() -> void:
	call_deferred("run")

func _fail(reason: String) -> void:
	if _finished:
		return
	_finished = true
	print("NET05_E2E FAIL: %s" % reason)
	quit(1)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		_fail("expected 4 args: url token count sha256")
		return
	_expected_count = int(args[2])
	_expected_hash = args[3]
	_adapter = Adapter.new()
	root.add_child(_adapter)
	_adapter.configure(args[0], args[1])
	_adapter.message_received.connect(_on_message)
	_adapter.status_changed.connect(_on_status)
	_deadline_ms = Time.get_ticks_msec() + 90000
	_adapter.connect_to_server()

func _on_message(message: Dictionary) -> void:
	if str(message.get("type", "")) != "creature_party":
		return
	if _phase == 1:
		_parties_phase1 += 1
	else:
		_completes.append(message)

func _on_status(status: String) -> void:
	if status == "Disconnected" and _phase == 1:
		_disconnected_phase1 = true
	elif status.begins_with("Creature sync failed"):
		_errors.append(status)

func _process(_delta: float) -> bool:
	if _finished:
		return false
	if Time.get_ticks_msec() > _deadline_ms:
		_fail("timed out (phase %d, phase1_parties=%d, completes=%d, errors=%s)" % [_phase, _parties_phase1, _completes.size(), str(_errors)])
		return false
	if _phase == 1 and _disconnected_phase1:
		if _parties_phase1 != 0:
			_fail("phase 1 emitted %d creature_party message(s); a cut mid-snapshot must emit none" % _parties_phase1)
			return false
		_phase = 2
		_adapter.connect_to_server()
		return false
	if _phase == 2 and not _completes.is_empty():
		# Keep listening briefly so a duplicate or trailing partial emission is caught.
		if _settle_until_ms == 0:
			_settle_until_ms = Time.get_ticks_msec() + 1500
		elif Time.get_ticks_msec() >= _settle_until_ms:
			_verify()
	return false

func _verify() -> void:
	if _finished:
		return
	if not _errors.is_empty():
		_fail("assembler errors: %s" % str(_errors))
		return
	var creatures: Array = _completes[0]["creatures"]
	if creatures.size() != _expected_count:
		_fail("expected %d creatures, got %d" % [_expected_count, creatures.size()])
		return
	var ids: Array = []
	var seen := {}
	for creature in creatures:
		var id: String = str(creature.get("id", ""))
		if id.is_empty() or seen.has(id):
			_fail("missing or duplicate creature id: '%s'" % id)
			return
		seen[id] = true
		ids.append(id)
	var actual_hash: String = "\n".join(ids).sha256_text()
	if actual_hash != _expected_hash:
		_fail("id order/content hash mismatch: %s != %s" % [actual_hash, _expected_hash])
		return
	if _completes.size() != 1:
		_fail("expected exactly one complete snapshot after reconnect, got %d" % _completes.size())
		return
	_finished = true
	print("NET05_E2E PASS creatures=%d phase1_parties=%d completes=%d" % [creatures.size(), _parties_phase1, _completes.size()])
	quit(0)
