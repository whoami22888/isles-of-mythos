extends SceneTree

# MYTHOS-NET-05: reassembly of paginated server->client creature snapshots.
# Contract (server/src/creature-snapshot.ts):
#   page 0     -> {type:"creature_party",      snapshotId, page:0, pageCount, total, creatures}
#   pages 1..n -> {type:"creature_party_page", snapshotId, page,   pageCount, total, creatures}

const Assembler = preload("res://scripts/creature_snapshot_assembler.gd")
var _failures := 0

func check(condition: bool, description: String) -> void:
	if not condition:
		push_error(description)
		_failures += 1

func _init() -> void:
	call_deferred("run")

func _frame(page: int, page_count: int, total: int, ids: Array, snapshot_id: int = 1) -> Dictionary:
	var creatures: Array = []
	for id in ids:
		creatures.append({"id": id})
	return {
		"type": "creature_party" if page == 0 else "creature_party_page",
		"snapshotId": snapshot_id, "page": page, "pageCount": page_count,
		"total": total, "creatures": creatures,
	}

func _ids(result: Dictionary) -> Array:
	var ids: Array = []
	for creature in result["message"]["creatures"]:
		ids.append(creature["id"])
	return ids

func run() -> void:
	var a := Assembler.new()

	# Unrelated messages are ignored and never disturb a partial snapshot.
	check(a.feed({"type": "player_state"})["status"] == "ignored", "Unrelated message must be ignored")

	# Legacy frame (no paging metadata) passes through as a complete snapshot.
	var legacy := a.feed({"type": "creature_party", "creatures": [{"id": "a"}, {"id": "b"}]})
	check(legacy["status"] == "complete" and _ids(legacy) == ["a", "b"], "Legacy creature_party must pass through unchanged")

	# Single-page snapshot with metadata completes immediately.
	var single := a.feed(_frame(0, 1, 2, ["a", "b"]))
	check(single["status"] == "complete" and _ids(single) == ["a", "b"], "Single-page snapshot must complete")
	check(single["message"]["type"] == "creature_party" and single["message"]["total"] == 2, "Completed message must be a creature_party with total")

	# Empty collection.
	var empty := a.feed(_frame(0, 1, 0, []))
	check(empty["status"] == "complete" and _ids(empty).is_empty(), "Empty snapshot must complete with no creatures")

	# Multi-page snapshot reassembles in order and only the last page completes it.
	check(not a.is_partial(), "No partial snapshot expected before paging")
	var r0 := a.feed(_frame(0, 3, 5, ["c1", "c2"], 9))
	check(r0["status"] == "partial" and a.is_partial(), "First page must be partial")
	var r1 := a.feed(_frame(1, 3, 5, ["c3", "c4"], 9))
	check(r1["status"] == "partial", "Middle page must be partial")
	var r2 := a.feed(_frame(2, 3, 5, ["c5"], 9))
	check(r2["status"] == "complete" and _ids(r2) == ["c1", "c2", "c3", "c4", "c5"], "Final page must complete in order")
	check(not a.is_partial(), "Completed snapshot must clear the partial state")

	# JSON numbers arrive as floats in Godot; metadata must still be accepted.
	var parsed = JSON.parse_string('{"type":"creature_party","snapshotId":4,"page":0,"pageCount":2,"total":2,"creatures":[{"id":"x"}]}')
	check(a.feed(parsed)["status"] == "partial", "Float-typed JSON metadata must be accepted")
	var parsed2 = JSON.parse_string('{"type":"creature_party_page","snapshotId":4,"page":1,"pageCount":2,"total":2,"creatures":[{"id":"y"}]}')
	var done := a.feed(parsed2)
	check(done["status"] == "complete" and _ids(done) == ["x", "y"], "Float-typed JSON pages must reassemble")

	# A page gap is an error and discards the partial snapshot.
	a.feed(_frame(0, 3, 4, ["g1", "g2"], 2))
	var gap := a.feed(_frame(2, 3, 4, ["g4"], 2))
	check(gap["status"] == "error" and gap["reason"] == "snapshot_page_gap", "Skipped page must raise snapshot_page_gap")
	check(not a.is_partial(), "Error must discard the partial snapshot")

	# A page from a different snapshot is an error.
	a.feed(_frame(0, 2, 2, ["m1"], 5))
	var mismatch := a.feed(_frame(1, 2, 2, ["m2"], 6))
	check(mismatch["status"] == "error" and mismatch["reason"] == "snapshot_id_mismatch", "Foreign snapshotId must raise snapshot_id_mismatch")

	# A continuation page with no start is an orphan.
	var orphan := a.feed(_frame(1, 2, 2, ["o2"], 7))
	check(orphan["status"] == "error" and orphan["reason"] == "snapshot_orphan_page", "Continuation without a start must raise snapshot_orphan_page")

	# A new page 0 supersedes an incomplete snapshot (e.g. after a re-send).
	a.feed(_frame(0, 3, 6, ["old1", "old2"], 10))
	var fresh0 := a.feed(_frame(0, 2, 3, ["n1", "n2"], 11))
	check(fresh0["status"] == "partial", "New page 0 must start a fresh snapshot")
	var fresh1 := a.feed(_frame(1, 2, 3, ["n3"], 11))
	check(fresh1["status"] == "complete" and _ids(fresh1) == ["n1", "n2", "n3"], "Superseding snapshot must contain only the new data")

	# Declared total must match what was received.
	a.feed(_frame(0, 2, 5, ["t1"], 12))
	var wrong_total := a.feed(_frame(1, 2, 5, ["t2"], 12))
	check(wrong_total["status"] == "error" and wrong_total["reason"] == "snapshot_total_mismatch", "Wrong total must raise snapshot_total_mismatch")

	# Inconsistent metadata between pages of one snapshot.
	a.feed(_frame(0, 3, 4, ["i1"], 13))
	var bad_count := a.feed(_frame(1, 4, 4, ["i2"], 13))
	check(bad_count["status"] == "error" and bad_count["reason"] == "snapshot_malformed", "Changing pageCount mid-snapshot must raise snapshot_malformed")

	# Bounds.
	var too_many_pages := a.feed(_frame(0, Assembler.MAX_PAGES + 1, 10, ["p"], 14))
	check(too_many_pages["status"] == "error" and too_many_pages["reason"] == "snapshot_too_large", "pageCount over MAX_PAGES must be rejected")
	var too_many_creatures := a.feed(_frame(0, 2, Assembler.MAX_CREATURES + 1, ["p"], 15))
	check(too_many_creatures["status"] == "error" and too_many_creatures["reason"] == "snapshot_too_large", "total over MAX_CREATURES must be rejected")

	# Malformed metadata.
	for bad in [
		{"type": "creature_party", "snapshotId": 1, "page": 0, "pageCount": 0, "total": 0, "creatures": []},
		{"type": "creature_party", "snapshotId": 1, "page": 0, "pageCount": 1.5, "total": 0, "creatures": []},
		{"type": "creature_party", "snapshotId": 1, "page": 0, "pageCount": 1, "total": -1, "creatures": []},
		{"type": "creature_party", "snapshotId": 1, "page": 0, "pageCount": 1, "total": 0, "creatures": "nope"},
		{"type": "creature_party", "snapshotId": 1, "page": 1, "pageCount": 1, "total": 0, "creatures": []},
		{"type": "creature_party_page", "page": 1, "pageCount": 2, "total": 1, "creatures": []},
	]:
		var result := a.feed(bad)
		check(result["status"] == "error" and result["reason"] == "snapshot_malformed", "Malformed metadata must raise snapshot_malformed: %s" % JSON.stringify(bad))

	# reset() discards a partial snapshot (used when the connection is lost).
	a.feed(_frame(0, 2, 2, ["r1"], 20))
	check(a.is_partial(), "Partial snapshot expected before reset")
	a.reset()
	check(not a.is_partial(), "reset() must clear the partial snapshot")
	var after_reset := a.feed(_frame(1, 2, 2, ["r2"], 20))
	check(after_reset["reason"] == "snapshot_orphan_page", "Continuation after reset must be an orphan")

	print("MYTHOS-NET-05 creature snapshot assembler: %d failures" % _failures)
	quit(1 if _failures > 0 else 0)
