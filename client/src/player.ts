export interface PlayerState {
  userId: string; x: number; y: number; health: number; stamina: number; maxStamina: number; hunger: number; oxygen: number;
  xp: number; level: number; gold: number; inventory: Record<string, number>;
  hotbar: Array<string | null>; selectedHotbarSlot: number;
}
export function isPlayerState(value: unknown): value is PlayerState {
  if (typeof value !== "object" || value === null) return false;
  const state = value as Partial<PlayerState>;
  return typeof state.userId === "string" && typeof state.x === "number" && typeof state.y === "number" &&
    typeof state.health === "number" && typeof state.stamina === "number" && typeof state.maxStamina === "number" && typeof state.hunger === "number" && typeof state.oxygen === "number" &&
    typeof state.xp === "number" && typeof state.level === "number" && typeof state.gold === "number" &&
    Array.isArray(state.hotbar) && typeof state.selectedHotbarSlot === "number";
}
