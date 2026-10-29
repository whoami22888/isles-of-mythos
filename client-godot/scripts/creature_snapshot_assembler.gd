class_name CreatureSnapshotAssembler
extends RefCounted

# MYTHOS-NET-05: reassembles bounded, paginated server->client creature snapshots into
# one complete `creature_party` message, so consumers never see a partial collection.
#
# Wire contract (server/src/creature-snapshot.ts):
#   page 0     -> {type:"creature_party",      snapshotId, page:0, pageCount, total, creatures}
#   pages 1..n -> {type:"creature_party_page", snapshotId, page,   pageCount, total, creatures}
# A `creature_party` frame without paging metadata is the legacy single-frame form and
# passes through unchanged.
#
# feed() returns {status, reason, message}:
#   "ignored"  - not a creature snapshot frame
#   "partial"  - accepted, snapshot not yet complete (nothing to deliver)
#   "complete" - `message` is the full creature_party (all pages, in order)
#   "error"    - `reason` says why; the partial snapshot was discarded. The server re-sends a
#                fresh complete snapshot after every authentication, so recovery is a reconnect.

const MAX_PAGES := 1024
const MAX_CREATURES := 50000

var _active := false
var _snapshot_id := 0
var _page_count := 0
var _total := 0
var _next_page := 0
var _creatures: Array = []

func is_partial() -> bool:
	return _active

# Call when the connection is lost: a partial snapshot can never be completed.
func reset() -> void:
	_active = false
	_snapshot_id = 0
	_page_count = 0
	_total = 0
	_next_page = 0
	_creatures = []

func feed(message: Dictionary) -> Dictionary:
	var type: String = str(message.get("type", ""))
	if type != "creature_party" and type != "creature_party_page":
		return _result("ignored", "")
	var creatures = message.get("creatures")
	if not (creatures is Array):
		return _fail("snapshot_malformed")

	# Legacy single-frame form: no paging metadata at all.
	if type == "creature_party" and not message.has("pageCount") and not message.has("page"):
		reset()
		return _result("complete", "", {"type": "creature_party", "creatures": creatures, "total": creatures.size()})

	var page := _whole_number(message.get("page"))
	var page_count := _whole_number(message.get("pageCount"))
	var total := _whole_number(message.get("total"))
	var snapshot_id := _whole_number(message.get("snapshotId"))
	if page < 0 or page_count < 1 or total < 0 or snapshot_id < 0 or page >= page_count:
		return _fail("snapshot_malformed")
	if (type == "creature_party") != (page == 0):
		return _fail("snapshot_malformed")
	if page_count > MAX_PAGES or total > MAX_CREATURES:
		return _fail("snapshot_too_large")

	if page == 0:
		# A new first page always supersedes an incomplete snapshot (e.g. a re-send).
		reset()
		_active = true
		_snapshot_id = snapshot_id
		_page_count = page_count
		_total = total
	else:
		if not _active:
			return _fail("snapshot_orphan_page")
		if snapshot_id != _snapshot_id:
			return _fail("snapshot_id_mismatch")
		if page_count != _page_count or total != _total:
			return _fail("snapshot_malformed")
		if page != _next_page:
			return _fail("snapshot_page_gap")

	if _creatures.size() + creatures.size() > _total:
		return _fail("snapshot_total_mismatch")
	_creatures.append_array(creatures)
	_next_page = page + 1
	if _next_page < _page_count:
		return _result("partial", "")
	if _creatures.size() != _total:
		return _fail("snapshot_total_mismatch")
	var complete := {"type": "creature_party", "creatures": _creatures, "total": _total, "snapshotId": _snapshot_id, "complete": true}
	reset()
	return _result("complete", "", complete)

# JSON numbers arrive as floats; accept only whole, finite, non-negative numbers.
func _whole_number(value) -> int:
	if not (value is int or value is float):
		return -1
	var number: float = float(value)
	if is_nan(number) or is_inf(number) or number < 0.0 or number != floor(number) or number > 9007199254740991.0:
		return -1
	return int(number)

func _fail(reason: String) -> Dictionary:
	reset()
	return _result("error", reason)

func _result(status: String, reason: String, message: Dictionary = {}) -> Dictionary:
	return {"status": status, "reason": reason, "message": message}
