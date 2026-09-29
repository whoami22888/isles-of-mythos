import { describe, expect, it } from "vitest";
import {
  MAX_GOLD_DOUBLOONS,
  MAX_ITEM_STACK,
  addGoldDoubloons,
  applyInventoryDelta,
  cloneInventory,
  parseGoldDoubloons,
  subtractGoldDoubloons,
} from "./economy.js";

describe("economy foundation", () => {
  it("keeps Gold Doubloons exact beyond JavaScript safe-integer range", () => {
    const balance = parseGoldDoubloons("500000000");
    expect(balance).toBe(500000000n);
    expect(addGoldDoubloons(balance, 500000000n)).toBe(1000000000n);
    expect(parseGoldDoubloons(MAX_GOLD_DOUBLOONS)).toBe(MAX_GOLD_DOUBLOONS);
  });

  it("rejects negative and overflowing Gold Doubloons", () => {
    expect(() => parseGoldDoubloons("-1")).toThrow("INVALID_GOLD");
    expect(() => parseGoldDoubloons("9223372036854775808")).toThrow("GOLD_OVERFLOW");
    expect(() => addGoldDoubloons(MAX_GOLD_DOUBLOONS, 1n)).toThrow("GOLD_OVERFLOW");
    expect(() => subtractGoldDoubloons(10n, 11n)).toThrow("INSUFFICIENT_GOLD");
  });

  it("applies atomic-style inventory deltas without negative or oversized stacks", () => {
    const inventory = cloneInventory({ iron: 100 });
    expect(applyInventoryDelta(inventory, "iron", -40)).toEqual({ iron: 60 });
    expect(applyInventoryDelta(inventory, "steel", 5)).toEqual({ iron: 100, steel: 5 });
    expect(() => applyInventoryDelta(inventory, "iron", -101)).toThrow("INSUFFICIENT_INVENTORY");
    expect(() => applyInventoryDelta(inventory, "iron", MAX_ITEM_STACK + 1)).toThrow("INVALID_ITEM_QUANTITY");
    expect(() => cloneInventory({ iron: MAX_ITEM_STACK + 1 })).toThrow("INVALID_ITEM_QUANTITY");
  });
});
