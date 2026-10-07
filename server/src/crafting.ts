import { randomUUID } from "node:crypto";
import type { Pool } from "pg";
import { applyInventoryDelta, cloneInventory, runEconomyMutation, type Inventory } from "./economy.js";
import { getRecipe } from "./recipe.js";

export interface CraftResult {
  recipeId: string;
  transactionId: string;
  inventory: Inventory;
}

export async function craftRecipe(
  db: Pool,
  userId: string,
  requestId: string,
  recipeId: string,
): Promise<CraftResult> {
  if (!requestId || requestId.length > 64) throw new Error("INVALID_REQUEST_ID");
  const recipe = getRecipe(recipeId);
  if (!recipe) throw new Error("RECIPE_NOT_FOUND");

  const requestKey = userId + ":" + requestId;
  const fingerprint = recipe.id;
  const client = await db.connect();
  try {
    await client.query("BEGIN");

    const inserted = await client.query<{ transaction_id: string }>(
      "INSERT INTO craft_requests(request_key,user_id,fingerprint,response) VALUES($1,$2,$3,'{}'::jsonb) ON CONFLICT(request_key) DO NOTHING RETURNING transaction_id",
      [requestKey, userId, fingerprint],
    );

    if (inserted.rowCount === 0) {
      const existing = await client.query<{ transaction_id: string; fingerprint: string; response: { recipeId: string; inventory: Inventory } }>(
        "SELECT transaction_id,fingerprint,response FROM craft_requests WHERE request_key=$1 FOR UPDATE",
        [requestKey],
      );
      const row = existing.rows[0];
      if (!row) throw new Error("CRAFT_REQUEST_NOT_FOUND");
      if (row.fingerprint !== fingerprint) throw new Error("CRAFT_REQUEST_CONFLICT");
      await client.query("COMMIT");
      return { recipeId: row.response.recipeId, transactionId: row.transaction_id, inventory: cloneInventory(row.response.inventory) };
    }

    const transactionId = inserted.rows[0]?.transaction_id;
    if (!transactionId) throw new Error("CRAFT_TRANSACTION_ID_MISSING");

    const result = await runEconomyMutation(client, userId, ({ gold, inventory }) => {
      let nextInventory = cloneInventory(inventory);
      for (const ingredient of recipe.ingredients) {
        nextInventory = applyInventoryDelta(nextInventory, ingredient.itemId, -ingredient.quantity);
      }
      for (const output of recipe.outputs) {
        nextInventory = applyInventoryDelta(nextInventory, output.itemId, output.quantity);
      }
      return { gold, inventory: nextInventory, value: { recipeId: recipe.id, inventory: nextInventory } };
    });

    await client.query(
      "UPDATE craft_requests SET response=$2::jsonb WHERE request_key=$1",
      [requestKey, JSON.stringify(result.value)],
    );
    await client.query("COMMIT");
    return { ...result.value, transactionId };
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}
