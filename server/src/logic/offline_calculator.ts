export const MAX_OFFLINE_SECONDS = 86_400;

export interface OfflineYieldInput {
  lastOnlineMs: number;
  nowMs: number;
  baseRatePerSecond: number;
  creatureBuffs?: readonly number[];
  vipBuff?: number;
  stored: number;
  storageCapacity: number;
}

export interface OfflineYieldResult {
  deltaSeconds: number;
  uncappedYield: number;
  appliedYield: number;
  storedAfter: number;
}

export function offlineDeltaSeconds(lastOnlineMs: number, nowMs: number): number {
  if (!Number.isFinite(lastOnlineMs) || !Number.isFinite(nowMs) || nowMs < lastOnlineMs) return 0;
  return Math.min(MAX_OFFLINE_SECONDS, Math.floor((nowMs - lastOnlineMs) / 1000));
}

export function computeOfflineYield(input: OfflineYieldInput): OfflineYieldResult {
  const deltaSeconds = offlineDeltaSeconds(input.lastOnlineMs, input.nowMs);
  const buffSum = (input.creatureBuffs ?? []).reduce((sum, value) => sum + Math.max(0, value), 0);
  const vipBuff = input.vipBuff ?? 1;
  const uncappedYield = Math.max(
    0,
    deltaSeconds * Math.max(0, input.baseRatePerSecond) * (1 + buffSum) * Math.max(0, vipBuff),
  );
  const free = Math.max(0, input.storageCapacity - Math.max(0, input.stored));
  const appliedYield = Math.min(uncappedYield, free);
  return {
    deltaSeconds,
    uncappedYield,
    appliedYield,
    storedAfter: Math.max(0, input.stored) + appliedYield,
  };
}
