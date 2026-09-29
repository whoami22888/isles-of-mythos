export type ShopCategory = "resource" | "upgrade" | "defence";

export interface ShopItem {
  id: string;
  name: string;
  category: ShopCategory;
  priceGold: bigint;
  maxPurchase: number;
  description: string;
}

export const SHOP_ITEMS: readonly ShopItem[] = [
  { id: "resource.wood", name: "Wood Bundle", category: "resource", priceGold: 10n, maxPurchase: 100, description: "A bundle of construction-grade timber." },
  { id: "resource.stone", name: "Stone Bundle", category: "resource", priceGold: 15n, maxPurchase: 100, description: "A bundle of building stone." },
  { id: "resource.iron", name: "Iron Ore Bundle", category: "resource", priceGold: 25n, maxPurchase: 100, description: "A bundle of iron ore for advanced crafting." },
  { id: "resource.herb", name: "Herb Bundle", category: "resource", priceGold: 12n, maxPurchase: 100, description: "Medicinal and crafting herbs." },
  { id: "upgrade.camp.tier2", name: "Camp Tier II Upgrade", category: "upgrade", priceGold: 500n, maxPurchase: 1, description: "Unlocks the next camp construction tier." },
  { id: "upgrade.storage.tier2", name: "Storage Tier II Upgrade", category: "upgrade", priceGold: 350n, maxPurchase: 1, description: "Increases storage capacity when installed." },
  { id: "upgrade.forge.tier2", name: "Forge Tier II Upgrade", category: "upgrade", priceGold: 450n, maxPurchase: 1, description: "Unlocks improved metal crafting." },
  { id: "defence.wall.segment", name: "Defensive Wall Segment", category: "defence", priceGold: 40n, maxPurchase: 100, description: "A placeable defensive wall segment." },
  { id: "defence.cannon", name: "Defensive Cannon", category: "defence", priceGold: 250n, maxPurchase: 20, description: "A placeable cannon for settlement defence." },
  { id: "defence.watchtower", name: "Watchtower", category: "defence", priceGold: 400n, maxPurchase: 10, description: "A defensive tower for perimeter surveillance." },
];

export function getShopItem(itemId: string): ShopItem | undefined {
  return SHOP_ITEMS.find((item) => item.id === itemId);
}

export function calculatePurchase(item: ShopItem, quantity: number): number | null {
  if (!Number.isSafeInteger(quantity) || quantity < 1 || quantity > item.maxPurchase) return null;
  const total = item.priceGold * quantity;
  return Number.isSafeInteger(total) ? total : null;
}
