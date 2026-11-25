/** Shared naval kinematics used by sailing and broadside targeting. */

import type { UnitSailHeading } from "./sail-heading.js";

export type BroadsideSide = "port" | "starboard";

export const BROADSIDE_HALF_ARC = Math.PI / 4;
export const CANNON_COOLDOWN_MS = 1000;

/** Shortest signed angle from `from` to `to`, in (-PI, PI]. */
export function shortestSignedAngle(from: number, to: number): number {
  return Math.atan2(Math.sin(to - from), Math.cos(to - from));
}

/**
 * Apply a persisted turn-rate limit (radians per second) to a requested heading.
 * Travel continues along the heading actually reached this tick, not the requested
 * heading, so inertia and turning radius stay server-authoritative.
 */
export function applyTurnRate(
  currentHeading: number,
  requested: UnitSailHeading,
  turnRate: number,
  dt: number,
): { heading: number; travel: UnitSailHeading } {
  const requestedHeading = Math.atan2(requested.y, requested.x);
  const maxTurn = Math.max(0, turnRate) * Math.max(0, dt);
  const delta = shortestSignedAngle(currentHeading, requestedHeading);
  const applied = Math.abs(delta) <= maxTurn ? delta : Math.sign(delta) * maxTurn;
  const heading = currentHeading + applied;
  return { heading, travel: { x: Math.cos(heading), y: Math.sin(heading) } };
}

/**
 * Heading 0 faces +X. Port is the +Y beam (heading + PI/2), starboard is -Y
 * (heading - PI/2). Each broadside uses a PI/4 half-arc, optionally widened by
 * a navigator bonus already expressed in radians.
 */
export function resolveBroadside(
  heading: number,
  fromX: number,
  fromY: number,
  toX: number,
  toY: number,
  extraHalfArc = 0,
): BroadsideSide | null {
  const targetAngle = Math.atan2(toY - fromY, toX - fromX);
  const halfArc = BROADSIDE_HALF_ARC + Math.max(0, extraHalfArc);
  const portDelta = Math.abs(shortestSignedAngle(heading + Math.PI / 2, targetAngle));
  const starDelta = Math.abs(shortestSignedAngle(heading - Math.PI / 2, targetAngle));
  const onPort = portDelta <= halfArc;
  const onStar = starDelta <= halfArc;
  if (!onPort && !onStar) return null;
  if (onPort && (!onStar || portDelta <= starDelta)) return "port";
  return "starboard";
}
