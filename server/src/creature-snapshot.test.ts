import { describe, expect, it } from "vitest";
import { buildCreatureSnapshotFrames, CREATURE_SNAPSHOT_PAGE_BYTES } from "./creature-snapshot.js";

// MYTHOS-NET-05: server->client creature snapshots must be bounded per frame.
// The 64 KiB maxPayload only bounds client->server frames; before this change the
// server sent every owned creature in one unbounded `creature_party` frame.

interface Frame {
  type: string;
  snapshotId: number;
  page: number;
  pageCount: number;
  total: number;
  creatures: { id: string }[];
}

function creature(index: number, nickname: string | null = `Pet ${index}`) {
  return {
    id: `00000000-0000-4000-8000-${String(index).padStart(12, "0")}`,
    ownerUserId: "11111111-1111-4111-8111-111111111111",
    species: "ember-drake",
    nickname,
    level: 10 + (index % 90),
    xp: 12345,
    health: 100,
    maxHealth: 120,
    attack: 30,
    defense: 20,
    element: "fire",
    abilityIds: ["ember-breath"],
    tameProgress: 100,
    partySlot: index < 3 ? index : null,
    aiMode: "follow",
    x: index,
    y: -index,
  };
}

const bytes = (frame: unknown) => Buffer.byteLength(JSON.stringify(frame), "utf8");
const asFrames = (value: unknown) => value as Frame[];

describe("creature snapshot framing", () => {
  it("keeps the per-frame budget well under the 64 KiB frame limit", () => {
    expect(CREATURE_SNAPSHOT_PAGE_BYTES).toBeLessThanOrEqual(49152);
    expect(CREATURE_SNAPSHOT_PAGE_BYTES).toBeGreaterThan(0);
  });

  it("sends an empty collection as one creature_party frame", () => {
    const frames = asFrames(buildCreatureSnapshotFrames([], 7));
    expect(frames).toHaveLength(1);
    expect(frames[0]).toMatchObject({ type: "creature_party", snapshotId: 7, page: 0, pageCount: 1, total: 0, creatures: [] });
  });

  it("keeps a small collection in a single legacy-compatible creature_party frame", () => {
    const owned = [creature(0), creature(1), creature(2)];
    const frames = asFrames(buildCreatureSnapshotFrames(owned, 1));
    expect(frames).toHaveLength(1);
    expect(frames[0]?.type).toBe("creature_party");
    expect(frames[0]?.creatures).toEqual(owned);
    expect(frames[0]).toMatchObject({ page: 0, pageCount: 1, total: 3 });
  });

  it("splits a >1 MiB collection into ordered, bounded, complete pages", () => {
    const owned = Array.from({ length: 5000 }, (_, i) => creature(i));
    const frames = asFrames(buildCreatureSnapshotFrames(owned, 42));

    const totalBytes = frames.reduce((sum, frame) => sum + bytes(frame), 0);
    expect(totalBytes).toBeGreaterThan(1_048_576);
    expect(frames.length).toBeGreaterThan(20);

    frames.forEach((frame, index) => {
      expect(bytes(frame)).toBeLessThanOrEqual(CREATURE_SNAPSHOT_PAGE_BYTES);
      expect(frame.type).toBe(index === 0 ? "creature_party" : "creature_party_page");
      expect(frame).toMatchObject({ snapshotId: 42, page: index, pageCount: frames.length, total: 5000 });
      expect(frame.creatures.length).toBeGreaterThan(0);
    });

    const reassembled = frames.flatMap((frame) => frame.creatures);
    expect(reassembled).toHaveLength(5000);
    expect(reassembled.map((c) => c.id)).toEqual(owned.map((c) => c.id));
    expect(reassembled).toEqual(owned);
  });

  it("measures budget in UTF-8 bytes, not characters", () => {
    const wide = "\u{1F409}".repeat(8); // 8 characters, 32 bytes
    const owned = Array.from({ length: 1500 }, (_, i) => creature(i, wide));
    const frames = asFrames(buildCreatureSnapshotFrames(owned, 3));
    frames.forEach((frame) => expect(bytes(frame)).toBeLessThanOrEqual(CREATURE_SNAPSHOT_PAGE_BYTES));
    expect(frames.flatMap((f) => f.creatures)).toHaveLength(1500);
  });

  it("never drops or loops on a single creature larger than the page budget", () => {
    const owned = [creature(0), creature(1, "x".repeat(70000)), creature(2)];
    const frames = asFrames(buildCreatureSnapshotFrames(owned, 9, 4096));
    expect(frames.flatMap((f) => f.creatures.map((c) => c.id))).toEqual(owned.map((c) => c.id));
    expect(frames.every((f) => f.pageCount === frames.length)).toBe(true);
  });

  it("is deterministic for identical input", () => {
    const owned = Array.from({ length: 800 }, (_, i) => creature(i));
    expect(buildCreatureSnapshotFrames(owned, 5)).toEqual(buildCreatureSnapshotFrames(owned, 5));
  });

  it("rejects an unusable page budget", () => {
    expect(() => buildCreatureSnapshotFrames([creature(0)], 1, 0)).toThrow();
    expect(() => buildCreatureSnapshotFrames([creature(0)], 1, Number.NaN)).toThrow();
  });
});
