import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { verifyGameplayRequest } from "../auth.js";
import {
  applyInventoryDelta,
  cloneInventory,
  parseGoldDoubloons,
  subtractGoldDoubloons,
  type Inventory,
} from "../economy.js";
import type { PlayerStore } from "../player.js";
import { calculatePurchase, getShopItem } from "../shop.js";

export const INSUFFICIENT_FUNDS = "INSUFFICIENT_FUNDS";

export interface ItemReceipt {
  itemId: string;
  quantity: number;
  goldSpent: string;
  transactionId: string;
}

export interface BuyItemResult {
  balance: string;
  receipt: ItemReceipt;
}

/**
 * Atomically purchase a catalogue item with a row lock on the player's Gold Doubloons.
 * `player_profiles.gold` is the canonical gold_doubloons balance (there is no `characters` table).
 */
export async function buyItem(db: Pool, userId: string, itemId: string, quantity: number): Promise<BuyItemResult> {
  const item = getShopItem(itemId);
  if (!item) throw new Error("SHOP_ITEM_NOT_FOUND");
  const cost = calculatePurchase(item, quantity);
  if (cost === null) throw new Error("INVALID_PURCHASE_QUANTITY");

  const client = await db.connect();
  try {
    await client.query("BEGIN");
    const locked = await client.query<{ gold_doubloons: string; inventory: Inventory }>(
      "SELECT gold AS gold_doubloons, inventory FROM player_profiles WHERE user_id = $1 FOR UPDATE",
      [userId],
    );
    const row = locked.rows[0];
    if (!row) throw new Error("PLAYER_NOT_FOUND");

    const gold = parseGoldDoubloons(row.gold_doubloons);
    if (gold < cost) throw new Error(INSUFFICIENT_FUNDS);
    const nextGold = subtractGoldDoubloons(gold, cost);
    const nextInventory = applyInventoryDelta(cloneInventory(row.inventory), item.id, quantity);

    await client.query(
      "UPDATE player_profiles SET gold=$2, inventory=$3::jsonb, updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",
      [userId, nextGold.toString(), JSON.stringify(nextInventory)],
    );
    const inserted = await client.query<{ id: string }>(
      `INSERT INTO currency_transactions (user_id, item_id, quantity, gold_spent, gold_before, gold_after)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING id`,
      [userId, item.id, quantity, cost.toString(), gold.toString(), nextGold.toString()],
    );
    await client.query("COMMIT");
    return {
      balance: nextGold.toString(),
      receipt: {
        itemId: item.id,
        quantity,
        goldSpent: cost.toString(),
        transactionId: inserted.rows[0].id,
      },
    };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export function registerPurchaseRoutes(app: FastifyInstance, db: Pool, players: PlayerStore): void {
  app.post<{ Body: { itemId: string; quantity?: number } }>(
    "/api/v1/economy/buy-item",
    {
      schema: {
        tags: ["shop"],
        security: [{ bearerAuth: [] }],
        body: {
          type: "object",
          required: ["itemId"],
          additionalProperties: false,
          properties: {
            itemId: { type: "string", minLength: 1, maxLength: 64 },
            quantity: { type: "integer", minimum: 1, maximum: 100 },
          },
        },
      },
    },
    async (request, reply) => {
      if (!(await verifyGameplayRequest(request))) {
        return reply.code(401).send({ error: "UNAUTHORIZED", message: "Invalid credentials" });
      }

      const userId = request.user.sub;
      const quantity = request.body.quantity ?? 1;
      try {
        await players.loadOrCreate(userId);
        const result = await buyItem(db, userId, request.body.itemId, quantity);
        if (players.get(userId)) await players.reloadEconomy(userId);
        return result;
      } catch (error) {
        const code = error instanceof Error ? error.message : "";
        if (code === INSUFFICIENT_FUNDS || code === "INSUFFICIENT_GOLD") {
          return reply.code(400).send({ error: INSUFFICIENT_FUNDS, message: "Insufficient Funds" });
        }
        if (code === "SHOP_ITEM_NOT_FOUND" || code === "PLAYER_NOT_FOUND") {
          return reply.code(404).send({ error: code });
        }
        if (code === "INVALID_PURCHASE_QUANTITY") {
          return reply.code(400).send({ error: code });
        }
        if (code === "INVENTORY_LIMIT") {
          return reply.code(409).send({ error: code });
        }
        return reply.code(500).send({ error: "PURCHASE_FAILED" });
      }
    },
  );
}
