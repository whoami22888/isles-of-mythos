import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";
import { MAX_ITEM_STACK } from "./economy.js";
import { PlayerStore } from "./player.js";
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
    expect(calculatePurchase(cannon!, 2)).toBe(cannon!.priceGold * 2n);
  });

  it("rejects invalid or excessive quantities", () => {
    const wall = getShopItem("defence.wall.segment");
    expect(wall).toBeDefined();
    expect(calculatePurchase(wall!, 0)).toBeNull();
    expect(calculatePurchase(wall!, wall!.maxPurchase + 1)).toBeNull();
    expect(calculatePurchase(wall!, 1.5)).toBeNull();
  });
});

async function createShopPlayer() {
  const db = createDbPool();
  const app = await buildApp({ db });
  const unique = randomUUID().replace(/-/g, "").slice(0, 24);
  const response = await app.inject({
    method: "POST",
    url: "/auth/register",
    payload: {
      username: `shop_${unique}`,
      email: `shop_${unique}@example.com`,
      password: "Correct-Horse-Battery-9",
    },
  });
  expect(response.statusCode).toBe(201);
  const body = JSON.parse(response.body) as { user: { id: string }; accessToken: string };
  await new PlayerStore(db).loadOrCreate(body.user.id);
  return { db, app, userId: body.user.id, token: body.accessToken };
}

describe("shop catalogue", () => {
  it("contains resources, upgrades and defences", () => {
    expect(SHOP_ITEMS.some((item) => item.category === "resource")).toBe(true);
    expect(SHOP_ITEMS.some((item) => item.category === "upgrade")).toBe(true);
    expect(SHOP_ITEMS.some((item) => item.category === "defence")).toBe(true);
  });

  it("calculates purchases from server catalogue prices", () => {
    const cannon = getShopItem("defence.cannon");
    expect(cannon).toBeDefined();
    expect(calculatePurchase(cannon!, 2)).toBe(cannon!.priceGold * 2n);
  });

  it("rejects invalid or excessive quantities", () => {
    const wall = getShopItem("defence.wall.segment");
    expect(wall).toBeDefined();
    expect(calculatePurchase(wall!, 0)).toBeNull();
    expect(calculatePurchase(wall!, wall!.maxPurchase + 1)).toBeNull();
    expect(calculatePurchase(wall!, 1.5)).toBeNull();
  });

  it("atomically charges the server price and grants the purchased item", async () => {
    const { db, app, userId, token } = await createShopPlayer();
    try {
      await db.query("UPDATE player_profiles SET gold=$2, inventory=$3::jsonb WHERE user_id=$1", [
        userId,
        "100",
        JSON.stringify({}),
      ]);
      const response = await app.inject({
        method: "POST",
        url: "/shop/purchase",
        headers: { authorization: `Bearer ${token}` },
        payload: { requestId: "purchase-1", itemId: "resource.wood", quantity: 2 },
      });
      expect(response.statusCode).toBe(200);
      expect(JSON.parse(response.body)).toMatchObject({
        itemId: "resource.wood",
        quantity: 2,
        totalGold: "20",
        state: { gold: "80", inventory: { "resource.wood": 2 } },
      });
    } finally {
      await app.close();
      await db.end();
    }
  });

  it("executes an HTTP purchase only once for a repeated request id", async () => {
    const { db, app, userId, token } = await createShopPlayer();
    try {
      await db.query("UPDATE player_profiles SET gold=$2, inventory=$3::jsonb WHERE user_id=$1", [userId, "100", JSON.stringify({})]);
      const first = await app.inject({ method: "POST", url: "/shop/purchase", headers: { authorization: `Bearer ${token}` }, payload: { requestId: "purchase-once", itemId: "resource.wood", quantity: 2 } });
      expect(first.statusCode).toBe(200);
      await app.close();
      const restartedApp = await buildApp({ db });
      const second = await restartedApp.inject({ method: "POST", url: "/shop/purchase", headers: { authorization: `Bearer ${token}` }, payload: { requestId: "purchase-once", itemId: "resource.wood", quantity: 2 } });
      expect(second.statusCode).toBe(200);
      expect(JSON.parse(second.body)).toEqual(JSON.parse(first.body));
      await restartedApp.close();
      const row = await db.query<{ gold: string; inventory: Record<string, number> }>("SELECT gold, inventory FROM player_profiles WHERE user_id=$1", [userId]);
      expect(row.rows[0]).toEqual({ gold: "80", inventory: { "resource.wood": 2 } });
    } finally { await app.close(); await db.end(); }
  });

  it("rejects reuse of a shop request id with different purchase parameters", async () => {
    const { db, app, userId, token } = await createShopPlayer();
    try {
      await db.query("UPDATE player_profiles SET gold=$2, inventory=$3::jsonb WHERE user_id=$1", [userId, "100", JSON.stringify({})]);
      const first = await app.inject({ method: "POST", url: "/shop/purchase", headers: { authorization: `Bearer ${token}` }, payload: { requestId: "purchase-conflict", itemId: "resource.wood", quantity: 1 } });
      const conflict = await app.inject({ method: "POST", url: "/shop/purchase", headers: { authorization: `Bearer ${token}` }, payload: { requestId: "purchase-conflict", itemId: "resource.wood", quantity: 2 } });
      expect(first.statusCode).toBe(200);
      expect(conflict.statusCode).toBe(409);
      expect(JSON.parse(conflict.body)).toEqual({ error: "SHOP_REQUEST_CONFLICT" });
      const row = await db.query<{ gold: string; inventory: Record<string, number> }>("SELECT gold, inventory FROM player_profiles WHERE user_id=$1", [userId]);
      expect(row.rows[0]).toEqual({ gold: "90", inventory: { "resource.wood": 1 } });
    } finally { await app.close(); await db.end(); }
  });

  it("rejects insufficient gold without changing inventory or currency", async () => {
    const { db, app, userId, token } = await createShopPlayer();
    try {
      await db.query("UPDATE player_profiles SET gold=$2, inventory=$3::jsonb WHERE user_id=$1", [
        userId,
        "5",
        JSON.stringify({}),
      ]);
      const response = await app.inject({
        method: "POST",
        url: "/shop/purchase",
        headers: { authorization: `Bearer ${token}` },
        payload: { requestId: "purchase-insufficient", itemId: "resource.wood", quantity: 1 },
      });
      expect(response.statusCode).toBe(409);
      const row = await db.query<{ gold: string; inventory: Record<string, number> }>(
        "SELECT gold, inventory FROM player_profiles WHERE user_id=$1",
        [userId],
      );
      expect(row.rows[0]).toEqual({ gold: "5", inventory: {} });
    } finally {
      await app.close();
      await db.end();
    }
  });

  it("rolls back the gold deduction when inventory capacity rejects the grant", async () => {
    const { db, app, userId, token } = await createShopPlayer();
    try {
      await db.query("UPDATE player_profiles SET gold=$2, inventory=$3::jsonb WHERE user_id=$1", [
        userId,
        "100",
        JSON.stringify({ "resource.wood": MAX_ITEM_STACK }),
      ]);
      const response = await app.inject({
        method: "POST",
        url: "/shop/purchase",
        headers: { authorization: `Bearer ${token}` },
        payload: { requestId: "purchase-capacity", itemId: "resource.wood", quantity: 1 },
      });
      expect(response.statusCode).toBe(409);
      expect(JSON.parse(response.body)).toEqual({ error: "INVENTORY_LIMIT" });
      const row = await db.query<{ gold: string; inventory: Record<string, number> }>(
        "SELECT gold, inventory FROM player_profiles WHERE user_id=$1",
        [userId],
      );
      expect(row.rows[0]).toEqual({
        gold: "100",
        inventory: { "resource.wood": MAX_ITEM_STACK },
      });
    } finally {
      await app.close();
      await db.end();
    }
  });
});
