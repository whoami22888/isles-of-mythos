import { describe, expect, it } from "vitest";
import { createDefaultPlayer } from "./player.js";
import { TileKind, generateChunk, tileAtWorld } from "./world.js";
import {
  RESPAWN_DELAY_MS,
  SPAWN_GRACE_MS,
  applyAuthoritativeRespawn,
  hasSpawnGrace,
  nextRespawnAt,
  safeSpawnPoint,
} from "./player-respawn.js";

describe("authoritative player respawn", () => {
  it("restores vitals after 5s at a safe spawn and suppresses attacks for 10s", () => {
    const now = 1_700_000_000_000;
    expect(RESPAWN_DELAY_MS).toBe(5_000);
    expect(SPAWN_GRACE_MS).toBe(10_000);
    expect(nextRespawnAt(now)).toBe(now + 5_000);

    const state = createDefaultPlayer("respawn-user");
    state.health = 0;
    state.stamina = 0;
    state.hunger = 0;
    state.oxygen = 0;
    state.x = 40;
    state.y = -25;
    const spawn = safeSpawnPoint();
    expect(tileAtWorld(Math.floor(spawn.x), Math.floor(spawn.y))).toBe(TileKind.Grass);
    for (let chunkY = -3; chunkY <= 3; chunkY += 1) {
      for (let chunkX = -3; chunkX <= 3; chunkX += 1) {
        for (const creature of generateChunk(chunkX, chunkY).creatures) {
          expect(Math.hypot(creature.x - spawn.x, creature.y - spawn.y)).toBeGreaterThanOrEqual(12);
        }
      }
    }
    applyAuthoritativeRespawn(state, spawn);
    expect(state.health).toBe(100);
    expect(state.stamina).toBe(state.maxStamina);
    expect(state.x).toBe(spawn.x);
    expect(state.y).toBe(spawn.y);
    const graceUntil = now + SPAWN_GRACE_MS;
    expect(hasSpawnGrace(graceUntil, now)).toBe(true);
    expect(hasSpawnGrace(graceUntil, now + 9_999)).toBe(true);
    expect(hasSpawnGrace(graceUntil, now + SPAWN_GRACE_MS)).toBe(false);
  });
});
