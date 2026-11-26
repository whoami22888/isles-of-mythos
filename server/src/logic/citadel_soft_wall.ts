import type { Pool } from "pg";

/** Frozen 15→16 soft-wall contract. Must not drift. */
export const CITADEL_SOFT_WALL_FROM_LEVEL = 15;
export const CITADEL_SOFT_WALL_TARGET_LEVEL = 16;
export const CITADEL_SOFT_WALL_WOOD = 5_000_000;
export const CITADEL_SOFT_WALL_STEEL = 5_000_000;
export const CITADEL_SOFT_WALL_FOOD = 1_000_000;
export const CITADEL_SOFT_WALL_BADGES = 500;
export const CITADEL_SOFT_WALL_BLOCKED = "CITADEL_SOFT_WALL_BLOCKED";
export const CITADEL_SOFT_WALL_AUDIT_FLAG = "CITADEL_SOFT_WALL_BLOCKED";

export interface SoftWallResources {
  wood?: number;
  steel?: number;
  food?: number;
}

export function meetsCitadelSoftWallResourceGate(storage: SoftWallResources): boolean {
  return (
    (storage.wood ?? 0) >= CITADEL_SOFT_WALL_WOOD
    && (storage.steel ?? 0) >= CITADEL_SOFT_WALL_STEEL
    && (storage.food ?? 0) >= CITADEL_SOFT_WALL_FOOD
  );
}

export function meetsCitadelSoftWallBadgeGate(badges: bigint | number): boolean {
  return BigInt(badges) >= BigInt(CITADEL_SOFT_WALL_BADGES);
}

/** Level 16 upgrade is allowed when resources OR 500 Triumph Badges are present. */
export function canClearCitadelSoftWall(storage: SoftWallResources, badges: bigint | number): boolean {
  return meetsCitadelSoftWallResourceGate(storage) || meetsCitadelSoftWallBadgeGate(badges);
}

export function assertCitadelSoftWall(storage: SoftWallResources, badges: bigint | number): void {
  if (!canClearCitadelSoftWall(storage, badges)) throw new Error(CITADEL_SOFT_WALL_BLOCKED);
}

export async function recordCitadelSoftWallAudit(
  db: Pool,
  userId: string,
  details: Record<string, unknown> = {},
): Promise<void> {
  try {
    await db.query(
      "INSERT INTO audit_logs (user_id, flag, details) VALUES ($1, $2, $3::jsonb)",
      [userId, CITADEL_SOFT_WALL_AUDIT_FLAG, JSON.stringify(details)],
    );
  } catch {
    // Audit failure must not replace the original soft-wall rejection.
  }
}
