export const HOARD_RATIO = 0.85;
export const HOARD_HOURS = 72;
export const RAID_OVERFLOW_FRACTION = 0.05;

export interface HoardState {
  stored: number;
  capacity: number;
  hoardStartedAtMs: number | null;
  lastUpgradeAtMs: number | null;
}

export interface SeaRaidEvent {
  triggered: boolean;
  utilization: number;
  hoardHours: number;
  seized: number;
  storedAfter: number;
}

export function storageUtilization(stored: number, capacity: number): number {
  if (capacity <= 0) return 0;
  return stored / capacity;
}

export function evaluateSeaRaider(state: HoardState, nowMs: number): SeaRaidEvent {
  const utilization = storageUtilization(state.stored, state.capacity);
  const hoarding = utilization > HOARD_RATIO;
  const lastUpgrade = state.lastUpgradeAtMs ?? 0;
  const hoardStart = hoarding ? (state.hoardStartedAtMs ?? nowMs) : null;
  const hoardHours = hoardStart == null ? 0 : (nowMs - hoardStart) / 3_600_000;
  const upgradedDuring = lastUpgrade >= (hoardStart ?? nowMs);
  const triggered = hoarding && !upgradedDuring && hoardHours > HOARD_HOURS;
  const overflow = Math.max(0, state.stored - state.capacity * HOARD_RATIO);
  const seized = triggered ? overflow * RAID_OVERFLOW_FRACTION : 0;
  return {
    triggered,
    utilization,
    hoardHours,
    seized,
    storedAfter: Math.max(0, state.stored - seized),
  };
}
