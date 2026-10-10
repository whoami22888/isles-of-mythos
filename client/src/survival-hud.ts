import type { PlayerState } from "./player.js";

const SLOT_COUNT = 8;
const MAX_LABEL_LENGTH = 9;

function labelForItem(itemId: string): string {
  const knownLabels: Record<string, string> = {
    cutlass: "CUTLASS",
    flintlock: "FLINTLOCK",
    "ammo.flintlock": "AMMO",
    "capture.orb": "ORB",
    "creature.feed": "FEED",
  };
  const label = knownLabels[itemId] ?? itemId.replace(/[._-]+/g, " ").toUpperCase();
  return label.length > MAX_LABEL_LENGTH ? label.slice(0, MAX_LABEL_LENGTH) : label;
}

function quantityForSlot(itemId: string, inventory: Record<string, number>): number | undefined {
  const inventoryKey = itemId === "flintlock" ? "ammo.flintlock" : itemId;
  const quantity = inventory[inventoryKey];
  return Number.isSafeInteger(quantity) && quantity > 0 ? quantity : undefined;
}

/** Render the authoritative eight-slot hotbar and matching inventory quantities for the HUD. */
export function formatHotbar(state: Pick<PlayerState, "hotbar" | "selectedHotbarSlot" | "inventory">): string {
  const slots = Array.from({ length: SLOT_COUNT }, (_, index) => {
    const itemId = state.hotbar[index] ?? null;
    const selected = index === state.selectedHotbarSlot;
    const prefix = "[" + (index + 1) + (selected ? "*" : "") + "]";
    if (itemId === null) return prefix + " —";
    const quantity = quantityForSlot(itemId, state.inventory);
    return prefix + " " + labelForItem(itemId) + (quantity === undefined ? "" : " x" + quantity);
  });
  return "HOTBAR  " + slots.slice(0, 4).join(" | ") + "\n         " + slots.slice(4).join(" | ");
}
