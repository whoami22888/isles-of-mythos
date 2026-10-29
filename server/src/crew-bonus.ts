// Server-side crew stacking rules (Finding D). Crew contributions used to be plain sums, so filling a roster with
// identical specialists scaled combat/repair power without bound. Contributions now stack with diminishing returns
// and a hard per-effect ceiling. All parameters are provisional balance values owned by the server only.

/** Each next-best contributor counts for DECAY^rank of its value (best first). Sum is bounded by best/(1-DECAY). */
export const CREW_STACK_DECAY = 0.5;

/** Hard ceilings on the stacked value of each effect, in the same units as the raw per-crew contribution. */
export const CREW_BONUS_CAPS = {
  gunner: 200,          // stacked gunner skill*morale; fireCannon adds floor(value/10) cannons => at most +20 damage
  creatureAbility: 30,  // stacked creature ability damage across crew
  engineerRepair: 150,  // extra hull restored by repairShip on top of its base 20
  medicFire: 150,       // extra seconds of fire removed by fightFire on top of its base 5
  boardingPower: 220    // stacked boarding power; twice the strongest single member (skill 100 + morale 100/10)
} as const;

/**
 * Stack per-crew contributions: best first, each following contributor weighted by CREW_STACK_DECAY^rank, then
 * clamped to `cap`. Invalid (non-finite or negative) contributions are ignored; an invalid cap fails closed to 0.
 */
export function stackCrewContributions(values: readonly number[], cap: number): number {
  if (typeof cap !== "number" || Number.isNaN(cap) || cap < 0) return 0;
  const sorted = values.filter(v => Number.isFinite(v) && v > 0).sort((x, y) => y - x);
  let total = 0, weight = 1;
  for (const v of sorted) { total += v * weight; weight *= CREW_STACK_DECAY; }
  return Math.min(total, cap);
}
