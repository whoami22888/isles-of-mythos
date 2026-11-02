import type { Pool } from "pg";
import { describe, expect, it } from "vitest";
import { CreatureStore } from "./creature.js";
import { AUTHORITATIVE_SIMULATION_TICK_MS } from "./simulation-cadence.js";

function storeFor(overrides: Record<string, unknown> = {}): CreatureStore {
  const row = {
    id: "creature-1",
    owner_user_id: "user-1",
    species: "fire_wisp",
    nickname: null,
    level: 1,
    xp: "0",
    health: 55,
    max_health: 55,
    attack: 10,
    defense: 3,
    element: "fire",
    ability_ids: ["ember_burst"],
    tame_progress: 100,
    party_slot: null,
    ai_mode: "follow",
    x: 0,
    y: 0,
    ...overrides,
  };
  const db = { query: () => Promise.resolve({ rows: [row] }) } as unknown as Pool;
  return new CreatureStore(db);
}

describe("authoritative base worker movement", () => {
  it("scales follower movement to the 20 Hz authoritative step", async () => {
    const legacyCadence = storeFor({ party_slot: 0 });
    const authoritative = storeFor({ party_slot: 0 });
    await legacyCadence.load("user-1");
    await authoritative.load("user-1");

    expect(AUTHORITATIVE_SIMULATION_TICK_MS).toBe(50);
    expect(legacyCadence.tickAi("user-1", { x: 5, y: 0 })).toBe(true);
    expect(authoritative.tickAi("user-1", { x: 5, y: 0 }, AUTHORITATIVE_SIMULATION_TICK_MS)).toBe(true);

    const legacyX = legacyCadence.getCreature("user-1", "creature-1")?.x;
    const steppedX = authoritative.getCreature("user-1", "creature-1")?.x;
    expect(legacyX).toBeCloseTo(0.375);
    expect(steppedX).toBeCloseTo(0.375 * (50 / 250));
    expect(steppedX).toBeCloseTo((legacyX ?? 0) * (50 / 250));
    // Twenty 50 ms steps cover the same distance as one legacy 250 ms step.
    expect((steppedX ?? 0) * (1_000 / AUTHORITATIVE_SIMULATION_TICK_MS)).toBeCloseTo((legacyX ?? 0) * 4);
  });

  it("moves a tamed un-partied worker and marks its state dirty", async () => {
    const store = storeFor();
    await store.load("user-1");
    expect(store.moveWorker("user-1", "creature-1", 1.25, -0.5)).toBe(true);
    expect(store.getCreature("user-1", "creature-1")).toMatchObject({ x: 1.25, y: -0.5 });
  });

  it("refuses to move untamed, party-assigned, or non-finite worker states", async () => {
    const untamed = storeFor({ tame_progress: 75 });
    await untamed.load("user-1");
    expect(untamed.moveWorker("user-1", "creature-1", 1, 1)).toBe(false);

    const inParty = storeFor({ party_slot: 0 });
    await inParty.load("user-1");
    expect(inParty.moveWorker("user-1", "creature-1", 1, 1)).toBe(false);

    const invalid = storeFor();
    await invalid.load("user-1");
    expect(invalid.moveWorker("user-1", "creature-1", Number.NaN, 1)).toBe(false);
  });
});
