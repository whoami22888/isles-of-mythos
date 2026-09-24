export interface PlayerState {
  userId: string; x: number; y: number; health: number; stamina: number; maxStamina: number; hunger: number; oxygen: number;
  xp: number; level: number; gold: number; inventory: Record<string, number>;
  hotbar: Array<string | null>; selectedHotbarSlot: number;
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function isInventory(value: unknown): value is Record<string, number> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return false;
  return Object.entries(value).every(([key, quantity]) =>
    key.length > 0 && key.length <= 128 && Number.isSafeInteger(quantity) && quantity >= 0 && quantity <= 1_000_000,
  );
}

function isHotbar(value: unknown): value is Array<string | null> {
  return Array.isArray(value) &&
    value.length === 8 &&
    value.every((entry) => entry === null || (typeof entry === "string" && entry.length <= 128));
}

export function isPlayerState(value: unknown): value is PlayerState {
  if (typeof value !== "object" || value === null) return false;
  const state = value as Partial<PlayerState>;
  return typeof state.userId === "string" && state.userId.length > 0 &&
    isFiniteNumber(state.x) && isFiniteNumber(state.y) &&
    isFiniteNumber(state.health) && state.health >= 0 && state.health <= 100 &&
    isFiniteNumber(state.stamina) && state.stamina >= 0 &&
    isFiniteNumber(state.maxStamina) && state.maxStamina > 0 && state.maxStamina <= 1000 && state.stamina <= state.maxStamina &&
    isFiniteNumber(state.hunger) && state.hunger >= 0 && state.hunger <= 100 &&
    isFiniteNumber(state.oxygen) && state.oxygen >= 0 && state.oxygen <= 100 &&
    isFiniteNumber(state.xp) && state.xp >= 0 &&
    Number.isSafeInteger(state.level) && state.level >= 1 &&
    Number.isSafeInteger(state.gold) && state.gold >= 0 &&
    isInventory(state.inventory) && isHotbar(state.hotbar) &&
    Number.isSafeInteger(state.selectedHotbarSlot) && state.selectedHotbarSlot >= 0 && state.selectedHotbarSlot < 8;
}
