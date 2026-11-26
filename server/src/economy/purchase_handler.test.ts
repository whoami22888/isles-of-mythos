import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { buildApp } from "../app.js";
import { createDbPool } from "../db.js";
import { PlayerStore } from "../player.js";
import { INSUFFICIENT_FUNDS } from "./purchase_handler.js";

async function createBuyer() {
  const db = createDbPool();
  const app = await buildApp({ db });
  const unique = randomUUID().replace(/-/g, "").slice(0, 24);
  const response = await app.inject({
    method: "POST",
    url: "/auth/register",
    payload: {
      username: `buy_${unique}`,
      email: `buy_${unique}@example.com`,
      password: "Correct-Horse-Battery-9",
    },
  });
  expect(response.statusCode).toBe(201);
  const body = JSON.parse(response.body) as { user: { id: string }; accessToken: string };
  await new PlayerStore(db).loadOrCreate(body.user.id);
  return { db, app, userId: body.user.id, token: body.accessToken };
}

describe("POST /api/v1/economy/buy-item", () => {
  it("charges gold, grants the item, and writes a currency_transactions receipt", async () => {
    const { db, app, userId, token } = await createBuyer();
    try {
      await db.query("UPDATE player_profiles SET gold=$2, inventory=$3::jsonb WHERE user_id=$1", [
        userId,
        "100",
        JSON.stringify({}),
      ]);
      const response = await app.inject({
        method: "POST",
        url: "/api/v1/economy/buy-item",
        headers: { authorization: `Bearer ${token}` },
        payload: { itemId: "resource.wood", quantity: 2 },
      });
      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body) as {
        balance: string;
        receipt: { itemId: string; quantity: number; goldSpent: string; transactionId: string };
      };
      expect(body.balance).toBe("80");
      expect(body.receipt).toMatchObject({ itemId: "resource.wood", quantity: 2, goldSpent: "20" });
      expect(body.receipt.transactionId).toMatch(/^[0-9a-f-]{36}$/);

      const profile = await db.query<{ gold: string; inventory: Record<string, number> }>(
        "SELECT gold, inventory FROM player_profiles WHERE user_id=$1",
        [userId],
      );
      expect(profile.rows[0]).toEqual({ gold: "80", inventory: { "resource.wood": 2 } });
      const ledger = await db.query<{ item_id: string; quantity: number; gold_spent: string; gold_before: string; gold_after: string }>(
        "SELECT item_id, quantity, gold_spent, gold_before, gold_after FROM currency_transactions WHERE id=$1",
        [body.receipt.transactionId],
      );
      expect(ledger.rows[0]).toEqual({
        item_id: "resource.wood",
        quantity: 2,
        gold_spent: "20",
        gold_before: "100",
        gold_after: "80",
      });
    } finally {
      await app.close();
      await db.end();
    }
  });

  it("lets only one of two concurrent exact-balance buys succeed and returns HTTP 400 Insufficient Funds for the other", async () => {
    const { db, app, userId, token } = await createBuyer();
    try {
      await db.query("UPDATE player_profiles SET gold=$2, inventory=$3::jsonb WHERE user_id=$1", [
        userId,
        "10",
        JSON.stringify({}),
      ]);
      const [first, second] = await Promise.all([
        app.inject({
          method: "POST",
          url: "/api/v1/economy/buy-item",
          headers: { authorization: `Bearer ${token}` },
          payload: { itemId: "resource.wood", quantity: 1 },
        }),
        app.inject({
          method: "POST",
          url: "/api/v1/economy/buy-item",
          headers: { authorization: `Bearer ${token}` },
          payload: { itemId: "resource.wood", quantity: 1 },
        }),
      ]);
      const statuses = [first.statusCode, second.statusCode].sort((a, b) => a - b);
      expect(statuses).toEqual([200, 400]);
      const failed = first.statusCode === 400 ? first : second;
      expect(JSON.parse(failed.body)).toEqual({ error: INSUFFICIENT_FUNDS, message: "Insufficient Funds" });

      const profile = await db.query<{ gold: string; inventory: Record<string, number> }>(
        "SELECT gold, inventory FROM player_profiles WHERE user_id=$1",
        [userId],
      );
      expect(profile.rows[0]).toEqual({ gold: "0", inventory: { "resource.wood": 1 } });
      const ledger = await db.query<{ count: string }>(
        "SELECT count(*)::text AS count FROM currency_transactions WHERE user_id=$1 AND item_id=$2",
        [userId, "resource.wood"],
      );
      expect(ledger.rows[0].count).toBe("1");
    } finally {
      await app.close();
      await db.end();
    }
  });
});
