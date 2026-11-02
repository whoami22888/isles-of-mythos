/**
 * Owner-locked authoritative simulation cadence.
 * Combat, projectiles, creature AI, statuses, and worker steps advance on this
 * clock. One-second survival, naval fire, and the 5s/60s domain schedulers are
 * separate and must not be reported as this tick.
 *
 * The previous combat timer was 33 ms (~30 Hz). A measured rate at or above 20 Hz
 * was treated as success, so that timer passed the performance gate. The contract
 * is 20 Hz, with a jitter band so a slightly early or late monotonic scheduler
 * still passes and a ~30 Hz timer does not.
 */
export const AUTHORITATIVE_SIMULATION_HZ = 20;
export const AUTHORITATIVE_SIMULATION_TICK_MS = 1_000 / AUTHORITATIVE_SIMULATION_HZ;
export const AUTHORITATIVE_TICK_RATE_MIN_HZ = 19;
export const AUTHORITATIVE_TICK_RATE_MAX_HZ = 22;

export function authoritativeTickRateAccepted(hz: number): boolean {
  return Number.isFinite(hz)
    && hz >= AUTHORITATIVE_TICK_RATE_MIN_HZ
    && hz <= AUTHORITATIVE_TICK_RATE_MAX_HZ;
}

/**
 * Delay until the next fixed 20 Hz step.
 * `previousDeadlineNs === 0` starts the clock one step ahead of `nowNs`.
 * A late callback waits one full step from now. It does not emit a catch-up
 * burst, so a stall cannot report a 30 Hz spike.
 */
export function nextAuthoritativeTickDelayMs(
  nowNs: bigint,
  previousDeadlineNs: bigint,
  tickMs: number = AUTHORITATIVE_SIMULATION_TICK_MS,
): { delayMs: number; deadlineNs: bigint } {
  if (!Number.isInteger(tickMs) || tickMs <= 0) throw new Error("INVALID_SIMULATION_TICK");
  const stepNs = BigInt(tickMs) * 1_000_000n;
  let deadlineNs = previousDeadlineNs === 0n ? nowNs + stepNs : previousDeadlineNs + stepNs;
  if (deadlineNs <= nowNs) deadlineNs = nowNs + stepNs;
  return { delayMs: Number(deadlineNs - nowNs) / 1e6, deadlineNs };
}
