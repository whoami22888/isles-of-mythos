export const WOOD_SCARCITY_RATIO = 0.05;
export const STEEL_ABUNDANCE_RATIO = 0.9;
export const MAX_WOOD_SPAWN_BONUS = 0.35;

export interface InventoryRatios {
  wood: number;
  steel: number;
  other?: number;
}

export function resourceRatios(counts: InventoryRatios): { wood: number; steel: number; total: number } {
  const total = Math.max(0, counts.wood) + Math.max(0, counts.steel) + Math.max(0, counts.other ?? 0);
  if (total <= 0) return { wood: 0, steel: 0, total: 0 };
  return { wood: counts.wood / total, steel: counts.steel / total, total };
}

export function woodSpawnBonus(counts: InventoryRatios): number {
  const ratios = resourceRatios(counts);
  if (ratios.total <= 0) return 0;
  if (ratios.steel >= STEEL_ABUNDANCE_RATIO && ratios.wood < WOOD_SCARCITY_RATIO) {
    const deficit = WOOD_SCARCITY_RATIO - ratios.wood;
    const scale = deficit / WOOD_SCARCITY_RATIO;
    return Math.min(MAX_WOOD_SPAWN_BONUS, MAX_WOOD_SPAWN_BONUS * scale);
  }
  return 0;
}
