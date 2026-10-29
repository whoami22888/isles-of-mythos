extends SceneTree

# MYTHOS-NET-05: headless Godot client against a REAL Fastify server (driven by
# server/src/creature-snapshot.godot-e2e.test.ts). Uses the production
# IslesWebSocketAdapter plus CreatureSnapshotAssembler; no mock transport.
#
# Args after `--`: <ws url> <access token> <expected creature count> <sha256 of ids joined by "\n">
#
# Flow:
#   1. Connect. The test server cuts this first connection after a few snapshot frames,
#      so the client must see a PARTIAL snapshot, no complete one, then a disconnect.
#   2. Reconnect (explicit connect_to_server). The server re-sends a fresh snapshot after
#      authentication; the client must receive the COMPLETE collection (count, uniqueness,
#      order-sensitive SHA-256 of ids) without any duplicate or missing creature.

const Adapter = preload("res://scripts/websocket_adapter.gd")
const Assembler = preload("res://scripts/creature_snapshot_assembler.gd")

var _adapter
var _assembler := Assembler.new()
var _expected_count := 0
var _expected_hash := ""
var _phase := 1
var _partial_frames_phase1 := 0
var _frames_phase2 := 0
var _completes: Array = []
var _errors: Array = []
var _disconnected_after_partial := false
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
	var result: Dictionary = _assembler.feed(message)
	match result["status"]:
		"partial":
			if _phase == 1:
				_partial_frames_phase1 += 1
			else:
				_frames_phase2 += 1
		"complete":
			_frames_phase2 += 1
			_completes.append(result["message"])
		"error":
			_errors.append(result["reason"])

func _on_status(status: String) -> void:
	if status == "Disconnected":
		# A partial snapshot can never complete after the connection is lost.
		var was_partial: bool = _assembler.is_partial()
		_assembler.reset()
		if _phase == 1:
			_disconnected_after_partial = was_partial

func _process(_delta: float) -> bool:
	if _finished:
		return false
	if Time.get_ticks_msec() > _deadline_ms:
		_fail("timed out (phase %d, partial_frames=%d, completes=%d, errors=%s)" % [_phase, _partial_frames_phase1, _completes.size(), str(_errors)])
		return false
	if _phase == 1 and _disconnected_after_partial:
		if not _completes.is_empty():
			_fail("phase 1 produced a complete snapshot; the mid-stream cut did not happen")
			return false
		if _partial_frames_phase1 < 1:
			_fail("phase 1 saw no partial snapshot frames")
			return false
		_phase = 2
		_adapter.connect_to_server()
		return false
	if _phase == 2 and not _completes.is_empty():
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
	print("NET05_E2E PASS creatures=%d partial_frames_before_cut=%d frames_after_reconnect=%d" % [creatures.size(), _partial_frames_phase1, _frames_phase2])
	quit(0)
