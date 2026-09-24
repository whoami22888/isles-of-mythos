import { describe, expect, it } from "vitest";
import { SHOP_ITEMS, calculatePurchase, getShopItem } from "./shop.js";

describe("shop catalogue", () => {
  it("contains resources, upgrades and defences", () => {
    expect(SHOP_ITEMS.some((item) => item.category === "resource")).toBe(true);
    expect(SHOP_ITEMS.some((item) => item.category === "upgrade")).toBe(true);
    expect(SHOP_ITEMS.some((item) => item.category === "defence")).toBe(true);
  });

  it("calculates purchases from server catalogue prices", () => {
    const cannon = getShopItem("defence.cannon");
    expect(cannon).toBeDefined();
    expect(calculatePurchase(cannon!, 2)).toBe(cannon!.priceGold * 2);
  });

  it("rejects invalid or excessive quantities", () => {
    const wall = getShopItem("defence.wall.segment");
    expect(wall).toBeDefined();
    expect(calculatePurchase(wall!, 0)).toBeNull();
    expect(calculatePurchase(wall!, wall!.maxPurchase + 1)).toBeNull();
    expect(calculatePurchase(wall!, 1.5)).toBeNull();
  });
});
