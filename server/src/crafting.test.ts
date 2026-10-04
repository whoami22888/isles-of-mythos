import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";
import { MAX_ITEM_STACK } from "./economy.js";
import { PlayerStore } from "./player.js";
import { craftRecipe } from "./crafting.js";

async function createPlayer() {
  const db = createDbPool();
  const app = await buildApp({ db });
  const unique = randomUUID().replace(/-/g, "");
  const response = await app.inject({
    method: "POST",
    url: "/auth/register",
    payload: {
      username: `craft_${unique}`,
      email: `craft_${unique}@example.com`,
      password: "Correct-Horse-Battery-9",
    },
  });
  expect(response.statusCode).toBe(201);
  const body = JSON.parse(response.body) as { user: { id: string } };
  const userId = body.user.id;
  await new PlayerStore(db).loadOrCreate(userId);
  return { db, app, userId };
}

describe("crafting transactions", () => {
  it("atomically consumes ingredients and produces outputs", async () => {
    const { db, app, userId } = await createPlayer();
    try {
      await db.query(
        "UPDATE player_profiles SET inventory=$2::jsonb WHERE user_id=$1",
        [userId, JSON.stringify({ "resource.wood": 8 })],
      );

      const result = await craftRecipe(db, userId, "tool.wooden-club");
      expect(result.inventory).toEqual({
        "resource.wood": 0,
        "tool.wooden-club": 1,
      });

      const row = await db.query<{ inventory: Record<string, number> }>(
        "SELECT inventory FROM player_profiles WHERE user_id=$1",
        [userId],
      );
      expect(row.rows[0]?.inventory).toEqual(result.inventory);
    } finally {
      await app.close();
      await db.end();
    }
  });

  it("rejects insufficient ingredients without mutating inventory", async () => {
    const { db, app, userId } = await createPlayer();
    try {
      await db.query(
        "UPDATE player_profiles SET inventory=$2::jsonb WHERE user_id=$1",
        [userId, JSON.stringify({ "resource.wood": 7 })],
      );

      await expect(craftRecipe(db, userId, "tool.wooden-club")).rejects.toThrow(
        "INSUFFICIENT_INVENTORY",
      );

      const row = await db.query<{ inventory: Record<string, number> }>(
        "SELECT inventory FROM player_profiles WHERE user_id=$1",
        [userId],
      );
      expect(row.rows[0]?.inventory).toEqual({ "resource.wood": 7 });
    } finally {
      await app.close();
      await db.end();
    }
  });

  it("rolls back consumed ingredients when an output would overflow", async () => {
    const { db, app, userId } = await createPlayer();
    try {
      await db.query(
        "UPDATE player_profiles SET inventory=$2::jsonb WHERE user_id=$1",
        [
          userId,
          JSON.stringify({
            "resource.wood": 8,
            "tool.wooden-club": MAX_ITEM_STACK,
          }),
        ],
      );

      await expect(craftRecipe(db, userId, "tool.wooden-club")).rejects.toThrow(
        "INVENTORY_LIMIT",
      );

      const row = await db.query<{ inventory: Record<string, number> }>(
        "SELECT inventory FROM player_profiles WHERE user_id=$1",
        [userId],
      );
      expect(row.rows[0]?.inventory).toEqual({
        "resource.wood": 8,
        "tool.wooden-club": MAX_ITEM_STACK,
      });
    } finally {
      await app.close();
      await db.end();
    }
  });

  it("serializes concurrent crafts against one authoritative inventory row", async () => {
    const { db, app, userId } = await createPlayer();
    try {
      await db.query(
        "UPDATE player_profiles SET inventory=$2::jsonb WHERE user_id=$1",
        [userId, JSON.stringify({ "resource.wood": 32 })],
      );

      const results = await Promise.all(
        Array.from({ length: 4 }, () => craftRecipe(db, userId, "tool.wooden-club")),
      );
      expect(results).toHaveLength(4);

      const row = await db.query<{ inventory: Record<string, number> }>(
        "SELECT inventory FROM player_profiles WHERE user_id=$1",
        [userId],
      );
      expect(row.rows[0]?.inventory).toEqual({
        "resource.wood": 0,
        "tool.wooden-club": 4,
      });
    } finally {
      await app.close();
      await db.end();
    }
  });
});
