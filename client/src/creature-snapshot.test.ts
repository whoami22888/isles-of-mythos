import { describe, expect, it } from "vitest";
import { CreatureSnapshotAssembler } from "./creature-snapshot.js";
import { parseServerMessage } from "./network.js";

// MYTHOS-NET-05: the browser client must reassemble paged creature snapshots, otherwise
// a collection larger than one frame silently shrinks to page 0.

const creature = (id: string) => ({
  id, species: "ember-drake", nickname: "Pet", level: 1, xp: 0, health: 100, maxHealth: 120, attack: 30, defense: 20,
  element: "fire", abilityIds: ["ember-breath"], tameProgress: 100, aiMode: "follow", partySlot: null, x: 1, y: 2,
});
const frame = (page: number, pageCount: number, total: number, ids: string[], snapshotId = 1) => ({
  type: page === 0 ? "creature_party" : "creature_party_page", snapshotId, page, pageCount, total, creatures: ids.map(creature),
});
const ids = (r: { message?: { creatures: { id: string }[] } }) => (r.message?.creatures ?? []).map((c) => c.id);

describe("CreatureSnapshotAssembler", () => {
  it("passes a legacy single-frame creature_party through", () => {
    const a = new CreatureSnapshotAssembler();
    const r = a.feed({ type: "creature_party", creatures: [creature("a"), creature("b")] });
    expect(r.status).toBe("complete");
    expect(ids(r)).toEqual(["a", "b"]);
  });

  it("ignores unrelated messages", () => {
    expect(new CreatureSnapshotAssembler().feed({ type: "auth_ok", userId: "u" }).status).toBe("ignored");
  });

  it("reassembles pages in order and completes only on the last page", () => {
    const a = new CreatureSnapshotAssembler();
    expect(a.feed(frame(0, 3, 5, ["c1", "c2"], 9)).status).toBe("partial");
    expect(a.isPartial()).toBe(true);
    expect(a.feed(frame(1, 3, 5, ["c3", "c4"], 9)).status).toBe("partial");
    const done = a.feed(frame(2, 3, 5, ["c5"], 9));
    expect(done.status).toBe("complete");
    expect(ids(done)).toEqual(["c1", "c2", "c3", "c4", "c5"]);
    expect(a.isPartial()).toBe(false);
  });

  it("completes an empty single-page snapshot", () => {
    const r = new CreatureSnapshotAssembler().feed(frame(0, 1, 0, []));
    expect(r.status).toBe("complete");
    expect(ids(r)).toEqual([]);
  });

  it.each([
    ["page gap", [frame(0, 3, 4, ["g1", "g2"], 2), frame(2, 3, 4, ["g4"], 2)], "snapshot_page_gap"],
    ["foreign snapshot id", [frame(0, 2, 2, ["m1"], 5), frame(1, 2, 2, ["m2"], 6)], "snapshot_id_mismatch"],
    ["orphan page", [frame(1, 2, 2, ["o2"], 7)], "snapshot_orphan_page"],
    ["total mismatch", [frame(0, 2, 5, ["t1"], 12), frame(1, 2, 5, ["t2"], 12)], "snapshot_total_mismatch"],
    ["changed pageCount", [frame(0, 3, 4, ["i1"], 13), frame(1, 4, 4, ["i2"], 13)], "snapshot_malformed"],
    ["too many pages", [frame(0, 1025, 10, ["p"], 14)], "snapshot_too_large"],
    ["too many creatures", [frame(0, 2, 50001, ["p"], 15)], "snapshot_too_large"],
  ])("rejects %s and discards the partial snapshot", (_name, frames, reason) => {
    const a = new CreatureSnapshotAssembler();
    let last = a.feed(frames[0]);
    for (const f of frames.slice(1)) last = a.feed(f);
    expect(last.status).toBe("error");
    expect(last.reason).toBe(reason);
    expect(a.isPartial()).toBe(false);
  });

  it("lets a new page 0 supersede an incomplete snapshot", () => {
    const a = new CreatureSnapshotAssembler();
    a.feed(frame(0, 3, 6, ["old1", "old2"], 10));
    expect(a.feed(frame(0, 2, 3, ["n1", "n2"], 11)).status).toBe("partial");
    expect(ids(a.feed(frame(1, 2, 3, ["n3"], 11)))).toEqual(["n1", "n2", "n3"]);
  });

  it("reset() discards a partial snapshot (connection lost)", () => {
    const a = new CreatureSnapshotAssembler();
    a.feed(frame(0, 2, 2, ["r1"], 20));
    a.reset();
    expect(a.isPartial()).toBe(false);
    expect(a.feed(frame(1, 2, 2, ["r2"], 20)).reason).toBe("snapshot_orphan_page");
  });
});

describe("parseServerMessage creature snapshot frames", () => {
  it("keeps paging metadata on creature_party and parses creature_party_page", () => {
    const first = parseServerMessage(frame(0, 2, 2, ["a"], 3));
    expect(first).toMatchObject({ type: "creature_party", snapshotId: 3, page: 0, pageCount: 2, total: 2 });
    const next = parseServerMessage(frame(1, 2, 2, ["b"], 3));
    expect(next).toMatchObject({ type: "creature_party_page", snapshotId: 3, page: 1, pageCount: 2, total: 2 });
  });

  it("still parses a legacy creature_party without paging metadata", () => {
    expect(parseServerMessage({ type: "creature_party", creatures: [creature("a")] })).toMatchObject({ type: "creature_party" });
  });

  it("rejects a creature_party_page with invalid metadata", () => {
    expect(parseServerMessage({ ...frame(1, 2, 2, ["b"]), page: -1 })).toBeNull();
    expect(parseServerMessage({ ...frame(1, 2, 2, ["b"]), pageCount: 1.5 })).toBeNull();
    expect(parseServerMessage({ type: "creature_party_page", creatures: [] })).toBeNull();
  });
});
