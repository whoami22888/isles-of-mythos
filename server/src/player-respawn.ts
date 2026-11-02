import { PLAYER_MAX_HEALTH, PLAYER_MAX_HUNGER, PLAYER_MAX_OXYGEN, type PlayerState } from "./player.js";
import { CHUNK_SIZE, TileKind, generateChunk, tileAtWorld } from "./world.js";

export const RESPAWN_DELAY_MS = 5_000;
export const SPAWN_GRACE_MS = 10_000;

export function nextRespawnAt(now: number): number {
  return now + RESPAWN_DELAY_MS;
}

export function hasSpawnGrace(until: number | undefined, now: number): boolean {
  return until !== undefined && now < until;
}

export function applyAuthoritativeRespawn(state: PlayerState, spawn: { x: number; y: number }): void {
  state.health = PLAYER_MAX_HEALTH;
  state.stamina = state.maxStamina;
  state.hunger = PLAYER_MAX_HUNGER;
  state.oxygen = PLAYER_MAX_OXYGEN;
  state.x = spawn.x;
  state.y = spawn.y;
}

let cachedSpawn: { x: number; y: number } | null = null;

/** Grass tile outside creature activation range. Computed once from the world seed. */
export function safeSpawnPoint(): { x: number; y: number } {
  if (cachedSpawn) return cachedSpawn;
  const creatures: Array<{ x: number; y: number }> = [];
  for (let chunkY = -3; chunkY <= 3; chunkY += 1) {
    for (let chunkX = -3; chunkX <= 3; chunkX += 1) {
      for (const creature of generateChunk(chunkX, chunkY).creatures) creatures.push(creature);
    }
  }
  const minClearance = 12;
  for (let y = -CHUNK_SIZE * 2; y <= CHUNK_SIZE * 2; y += 1) {
    for (let x = -CHUNK_SIZE * 2; x <= CHUNK_SIZE * 2; x += 1) {
      if (tileAtWorld(x, y) !== TileKind.Grass) continue;
      let crowded = false;
      for (const creature of creatures) {
        if (Math.abs(creature.x - x) > minClearance || Math.abs(creature.y - y) > minClearance) continue;
        if (Math.hypot(creature.x - x, creature.y - y) < minClearance) {
          crowded = true;
          break;
        }
      }
      if (!crowded) {
        cachedSpawn = { x: x + 0.5, y: y + 0.5 };
        return cachedSpawn;
      }
    }
  }
  cachedSpawn = { x: CHUNK_SIZE + 0.5, y: CHUNK_SIZE + 0.5 };
  return cachedSpawn;
}
