/** Headings shorter than this are not a direction and make a unit conversion unstable. */
export const MIN_SAIL_HEADING_LENGTH = 1e-6;

export interface UnitSailHeading {
  x: number;
  y: number;
}

/**
 * Authoritative sail heading. Components are a direction in [-1, 1], not a
 * throttle and not a speed. `(1, 1)` is the same speed as `(1, 0)`.
 * Returns null for non-finite, out-of-range, zero, or unsafe tiny inputs.
 */
export function unitSailHeading(dx: unknown, dy: unknown): UnitSailHeading | null {
  if (typeof dx !== "number" || typeof dy !== "number") return null;
  if (!Number.isFinite(dx) || !Number.isFinite(dy)) return null;
  if (Math.abs(dx) > 1 || Math.abs(dy) > 1) return null;
  const length = Math.hypot(dx, dy);
  if (!(length >= MIN_SAIL_HEADING_LENGTH)) return null;
  return { x: dx / length, y: dy / length };
}
