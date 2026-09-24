export type ShopCategory = "resource" | "upgrade" | "defence";

export interface ShopItem {
  id: string;
  name: string;
  category: ShopCategory;
  priceGold: number;
  maxPurchase: number;
  description: string;
}

export const SHOP_ITEMS: readonly ShopItem[] = [
  { id: "resource.wood", name: "Wood Bundle", category: "resource", priceGold: 10, maxPurchase: 100, description: "A bundle of construction-grade timber." },
  { id: "resource.stone", name: "Stone Bundle", category: "resource", priceGold: 15, maxPurchase: 100, description: "A bundle of building stone." },
  { id: "resource.iron", name: "Iron Ore Bundle", category: "resource", priceGold: 25, maxPurchase: 100, description: "A bundle of iron ore for advanced crafting." },
  { id: "resource.herb", name: "Herb Bundle", category: "resource", priceGold: 12, maxPurchase: 100, description: "Medicinal and crafting herbs." },
  { id: "upgrade.camp.tier2", name: "Camp Tier II Upgrade", category: "upgrade", priceGold: 500, maxPurchase: 1, description: "Unlocks the next camp construction tier." },
  { id: "upgrade.storage.tier2", name: "Storage Tier II Upgrade", category: "upgrade", priceGold: 350, maxPurchase: 1, description: "Increases storage capacity when installed." },
  { id: "upgrade.forge.tier2", name: "Forge Tier II Upgrade", category: "upgrade", priceGold: 450, maxPurchase: 1, description: "Unlocks improved metal crafting." },
  { id: "defence.wall.segment", name: "Defensive Wall Segment", category: "defence", priceGold: 40, maxPurchase: 100, description: "A placeable defensive wall segment." },
  { id: "defence.cannon", name: "Defensive Cannon", category: "defence", priceGold: 250, maxPurchase: 20, description: "A placeable cannon for settlement defence." },
  { id: "defence.watchtower", name: "Watchtower", category: "defence", priceGold: 400, maxPurchase: 10, description: "A defensive tower for perimeter surveillance." },
];

export function getShopItem(itemId: string): ShopItem | undefined {
  return SHOP_ITEMS.find((item) => item.id === itemId);
}

export function calculatePurchase(item: ShopItem, quantity: number): number | null {
  if (!Number.isSafeInteger(quantity) || quantity < 1 || quantity > item.maxPurchase) return null;
  const total = item.priceGold * quantity;
  return Number.isSafeInteger(total) ? total : null;
}
