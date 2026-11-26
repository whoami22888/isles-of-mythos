export const MAX_SHIP_SPEED_MPS = 40;
export const SPEED_TOLERANCE = 1.25;
export const ILLEGAL_SPEED_AUDIT_FLAG = "ILLEGAL_SHIP_SPEED";

export interface SpatialSample {
  x: number;
  y: number;
  atMs: number;
}

export interface MovementVerdict {
  legal: boolean;
  velocity: number;
  maxAllowed: number;
  rolledBackTo: SpatialSample;
  auditFlag: string | null;
}

export function movementVelocity(from: SpatialSample, to: SpatialSample): number {
  const dtSec = (to.atMs - from.atMs) / 1000;
  if (!Number.isFinite(dtSec) || dtSec <= 0) return Number.POSITIVE_INFINITY;
  const distance = Math.hypot(to.x - from.x, to.y - from.y);
  return distance / dtSec;
}

export function validateSpatialUpdate(previous: SpatialSample, next: SpatialSample): MovementVerdict {
  const velocity = movementVelocity(previous, next);
  const maxAllowed = MAX_SHIP_SPEED_MPS * SPEED_TOLERANCE;
  const legal = velocity <= maxAllowed;
  return {
    legal,
    velocity,
    maxAllowed,
    rolledBackTo: legal ? next : previous,
    auditFlag: legal ? null : ILLEGAL_SPEED_AUDIT_FLAG,
  };
}

export async function recordIllegalMovementAudit(
  write: (flag: string, details: Record<string, unknown>) => Promise<void>,
  verdict: MovementVerdict,
  details: Record<string, unknown> = {},
): Promise<void> {
  if (verdict.legal || !verdict.auditFlag) return;
  await write(verdict.auditFlag, { velocity: verdict.velocity, maxAllowed: verdict.maxAllowed, ...details });
}
