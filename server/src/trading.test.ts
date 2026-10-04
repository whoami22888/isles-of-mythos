import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";
import { MAX_ITEM_STACK } from "./economy.js";
import { PlayerStore } from "./player.js";
import { tradePlayers } from "./trading.js";

async function createTradePlayers() {
  const db = createDbPool();
  const app = await buildApp({ db });
  const create = async (prefix: string) => {
    const unique = randomUUID().replace(/-/g, "").slice(0, 24);
    const response = await app.inject({
      method: "POST",
      url: "/auth/register",
      payload: {
        username: prefix + "_" + unique,
        email: prefix + "_" + unique + "@example.com",
        password: "Correct-Horse-Battery-9",
      },
    });
    expect(response.statusCode).toBe(201);
    const body = JSON.parse(response.body) as { user: { id: string } };
    await new PlayerStore(db).loadOrCreate(body.user.id);
    return body.user.id;
  };
  return { db, app, fromUserId: await create("tradea"), toUserId: await create("tradeb") };
}

async function setEconomy(db: ReturnType<typeof createDbPool>, userId: string, gold: string, inventory: Record<string, number>) {
  await db.query(
    "UPDATE player_profiles SET gold=$2, inventory=$3::jsonb WHERE user_id=$1",
    [userId, gold, JSON.stringify(inventory)],
  );
}

describe("player trading transactions", () => {
  it("atomically transfers items and Gold Doubloons", async () => {
    const { db, app, fromUserId, toUserId } = await createTradePlayers();
    try {
      await setEconomy(db, fromUserId, "1000", { "resource.wood": 10 });
      await setEconomy(db, toUserId, "100", {});

      const result = await tradePlayers(db, {
        requestId: "trade-1",
        fromUserId,
        toUserId,
        gold: "250",
        items: [{ itemId: "resource.wood", quantity: 4 }],
      });

      expect(result.from).toEqual({
        userId: fromUserId,
        gold: "750",
        inventory: { "resource.wood": 6 },
      });
      expect(result.to).toEqual({
        userId: toUserId,
        gold: "350",
        inventory: { "resource.wood": 4 },
      });
    } finally {
      await app.close();
      await db.end();
    }
  });

  it("rejects insufficient resources without changing either player", async () => {
    const { db, app, fromUserId, toUserId } = await createTradePlayers();
    try {
      await setEconomy(db, fromUserId, "1000", { "resource.wood": 2 });
      await setEconomy(db, toUserId, "100", {});
      await expect(tradePlayers(db, {
        requestId: "trade-2",
        fromUserId,
        toUserId,
        gold: "250",
        items: [{ itemId: "resource.wood", quantity: 4 }],
      })).rejects.toThrow("INSUFFICIENT_INVENTORY");

      const rows = await db.query<{ user_id: string; gold: string; inventory: Record<string, number> }>(
        "SELECT user_id, gold, inventory FROM player_profiles WHERE user_id = ANY($1::uuid[]) ORDER BY user_id",
        [[fromUserId, toUserId]],
      );
      expect(rows.rows).toEqual([
        { user_id: fromUserId, gold: "1000", inventory: { "resource.wood": 2 } },
        { user_id: toUserId, gold: "100", inventory: {} },
      ].sort((a, b) => a.user_id.localeCompare(b.user_id)));
    } finally {
      await app.close();
      await db.end();
    }
  });

  it("rolls back both sides when the recipient inventory would overflow", async () => {
    const { db, app, fromUserId, toUserId } = await createTradePlayers();
    try {
      await setEconomy(db, fromUserId, "1000", { "resource.wood": 1 });
      await setEconomy(db, toUserId, "100", { "resource.wood": MAX_ITEM_STACK });
      await expect(tradePlayers(db, {
        requestId: "trade-3",
        fromUserId,
        toUserId,
        gold: "250",
        items: [{ itemId: "resource.wood", quantity: 1 }],
      })).rejects.toThrow("INVENTORY_LIMIT");

      const rows = await db.query<{ user_id: string; gold: string; inventory: Record<string, number> }>(
        "SELECT user_id, gold, inventory FROM player_profiles WHERE user_id = ANY($1::uuid[]) ORDER BY user_id",
        [[fromUserId, toUserId]],
      );
      expect(rows.rows).toEqual([
        { user_id: fromUserId, gold: "1000", inventory: { "resource.wood": 1 } },
        { user_id: toUserId, gold: "100", inventory: { "resource.wood": MAX_ITEM_STACK } },
      ].sort((a, b) => a.user_id.localeCompare(b.user_id)));
    } finally {
      await app.close();
      await db.end();
    }
  });

  it("returns the same result for a replayed request without duplicating the transfer", async () => {
    const { db, app, fromUserId, toUserId } = await createTradePlayers();
    try {
      await setEconomy(db, fromUserId, "1000", { "resource.wood": 10 });
      await setEconomy(db, toUserId, "100", {});

      const request = {
        requestId: "trade-replay",
        fromUserId,
        toUserId,
        gold: "250",
        items: [{ itemId: "resource.wood", quantity: 4 }],
      };
      const first = await tradePlayers(db, request);
      const second = await tradePlayers(db, request);
      expect(second).toEqual(first);

      const rows = await db.query<{ user_id: string; gold: string; inventory: Record<string, number> }>(
        "SELECT user_id, gold, inventory FROM player_profiles WHERE user_id = ANY($1::uuid[]) ORDER BY user_id",
        [[fromUserId, toUserId]],
      );
      expect(rows.rows).toEqual([
        { user_id: fromUserId, gold: "750", inventory: { "resource.wood": 6 } },
        { user_id: toUserId, gold: "350", inventory: { "resource.wood": 4 } },
      ].sort((a, b) => a.user_id.localeCompare(b.user_id)));
    } finally {
      await app.close();
      await db.end();
    }
  });

  it("rejects the same request id with different trade contents", async () => {
    const { db, app, fromUserId, toUserId } = await createTradePlayers();
    try {
      await setEconomy(db, fromUserId, "1000", { "resource.wood": 10 });
      await setEconomy(db, toUserId, "100", {});

      await tradePlayers(db, {
        requestId: "trade-conflict",
        fromUserId,
        toUserId,
        gold: "250",
        items: [{ itemId: "resource.wood", quantity: 4 }],
      });
      await expect(tradePlayers(db, {
        requestId: "trade-conflict",
        fromUserId,
        toUserId,
        gold: "1",
        items: [{ itemId: "resource.wood", quantity: 4 }],
      })).rejects.toThrow("TRADE_REQUEST_CONFLICT");
    } finally {
      await app.close();
      await db.end();
    }
  });

  it("locks both player rows in deterministic order for concurrent opposite trades", async () => {
    const { db, app, fromUserId, toUserId } = await createTradePlayers();
    try {
      await setEconomy(db, fromUserId, "1000", { "resource.wood": 10 });
      await setEconomy(db, toUserId, "1000", { "resource.stone": 10 });

      const [first, second] = await Promise.all([
        tradePlayers(db, {
          requestId: "trade-a",
          fromUserId,
          toUserId,
          gold: "10",
          items: [{ itemId: "resource.wood", quantity: 1 }],
        }),
        tradePlayers(db, {
          requestId: "trade-b",
          fromUserId: toUserId,
          toUserId: fromUserId,
          gold: "20",
          items: [{ itemId: "resource.stone", quantity: 1 }],
        }),
      ]);

      expect(first.from.userId).toBe(fromUserId);
      expect(second.from.userId).toBe(toUserId);
      const rows = await db.query<{ user_id: string; gold: string; inventory: Record<string, number> }>(
        "SELECT user_id, gold, inventory FROM player_profiles WHERE user_id = ANY($1::uuid[]) ORDER BY user_id",
        [[fromUserId, toUserId]],
      );
      const byUser = new Map(rows.rows.map((row) => [row.user_id, row]));
      expect(byUser.get(fromUserId)).toEqual({
        user_id: fromUserId,
        gold: "1010",
        inventory: { "resource.wood": 9, "resource.stone": 1 },
      });
      expect(byUser.get(toUserId)).toEqual({
        user_id: toUserId,
        gold: "990",
        inventory: { "resource.stone": 9, "resource.wood": 1 },
      });
    } finally {
      await app.close();
      await db.end();
    }
  });
});
