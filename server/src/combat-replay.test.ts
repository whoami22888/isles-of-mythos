import { describe, expect, it } from "vitest";
import { CombatReplayCache } from "./combat-replay.js";

describe("combat replay protection", () => {
  it("returns the original response for an exact duplicate request", () => {
    const cache = new CombatReplayCache<{ damage: number }>(30_000, 8);
    cache.remember("user-1", "attack-1", "creature:1:2|0|1|0", { damage: 12 }, 1000);
    expect(cache.lookup("user-1", "attack-1", "creature:1:2|0|1|0", 1100)).toEqual({ kind: "hit", response: { damage: 12 } });
  });
  it("rejects request-id reuse with a different payload", () => {
    const cache = new CombatReplayCache<{ damage: number }>();
    cache.remember("user-1", "attack-1", "creature:1:2|0|1|0", { damage: 12 }, 1000);
    expect(cache.lookup("user-1", "attack-1", "creature:9:9|0|1|0", 1100)).toEqual({ kind: "conflict" });
  });
  it("expires and bounds entries", () => {
    const cache = new CombatReplayCache<number>(100, 2);
    cache.remember("u", "a", "a", 1, 0);
    cache.remember("u", "b", "b", 2, 0);
    cache.remember("u", "c", "c", 3, 0);
    expect(cache.lookup("u", "a", "a", 50)).toEqual({ kind: "miss" });
    expect(cache.lookup("u", "b", "b", 50)).toEqual({ kind: "hit", response: 2 });
    expect(cache.lookup("u", "c", "c", 50)).toEqual({ kind: "hit", response: 3 });
    expect(cache.lookup("u", "b", "b", 101)).toEqual({ kind: "miss" });
  });
});
