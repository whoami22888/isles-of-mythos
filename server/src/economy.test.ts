import { describe, expect, it } from "vitest";
import {
  MAX_GOLD_DOUBLOONS,
  MAX_ITEM_STACK,
  addGoldDoubloons,
  applyInventoryDelta,
  cloneInventory,
  parseGoldDoubloons,
  subtractGoldDoubloons,
  runEconomyTransaction,
} from "./economy.js";
import { createDbPool } from "./db.js";
import { buildApp } from "./app.js";

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

describe("economy transaction concurrency", () => {
  it("serializes concurrent economy mutations and commits inventory plus currency atomically", async () => {
    const db = createDbPool();
    const app = await buildApp({ db });
    const unique = Date.now();
    try {
      const response = await app.inject({
        method: "POST",
        url: "/auth/register",
        payload: {
          username: `economy_${unique}`,
          email: `economy_${unique}@example.com`,
          password: "Correct-Horse-Battery-9",
        },
      });
      expect(response.statusCode).toBe(201);
      const body = JSON.parse(response.body) as { user: { id: string } };
      const userId = body.user.id;

      await db.query(
        "UPDATE player_profiles SET gold=$2, inventory=$3::jsonb WHERE user_id=$1",
        [userId, "500000000", JSON.stringify({ wood: 0 })],
      );

      const operations = Array.from({ length: 32 }, () => runEconomyTransaction(db, userId, async ({ gold, inventory }) => {
        const nextGold = subtractGoldDoubloons(gold, 1000n);
        const nextInventory = applyInventoryDelta(inventory, "wood", 100);
        return { gold: nextGold, inventory: nextInventory, value: true };
      }));
      await Promise.all(operations);

      const row = await db.query<{ gold: string; inventory: Record<string, number> }>(
        "SELECT gold, inventory FROM player_profiles WHERE user_id=$1",
        [userId],
      );
      expect(row.rows[0].gold).toBe("499968000");
      expect(row.rows[0].inventory.wood).toBe(3200);

      await expect(runEconomyTransaction(db, userId, async ({ gold, inventory }) => {
        const nextGold = subtractGoldDoubloons(gold, 1000n);
        const nextInventory = applyInventoryDelta(inventory, "wood", 1);
        void nextGold;
        void nextInventory;
        throw new Error("FORCED_ROLLBACK");
      })).rejects.toThrow("FORCED_ROLLBACK");

      const afterRollback = await db.query<{ gold: string; inventory: Record<string, number> }>(
        "SELECT gold, inventory FROM player_profiles WHERE user_id=$1",
        [userId],
      );
      expect(afterRollback.rows[0].gold).toBe("499968000");
      expect(afterRollback.rows[0].inventory.wood).toBe(3200);
    } finally {
      await app.close();
      await db.end();
    }
  });
});
