import type { Pool } from "pg";
import { applyInventoryDelta, cloneInventory, runEconomyTransaction, type Inventory } from "./economy.js";
import { getRecipe } from "./recipe.js";

export interface CraftResult {
  recipeId: string;
  inventory: Inventory;
}

export async function craftRecipe(
  db: Pool,
  userId: string,
  recipeId: string,
): Promise<CraftResult> {
  const recipe = getRecipe(recipeId);
  if (!recipe) throw new Error("RECIPE_NOT_FOUND");

  return runEconomyTransaction(db, userId, ({ gold, inventory }) => {
    let nextInventory = cloneInventory(inventory);

    for (const ingredient of recipe.ingredients) {
      nextInventory = applyInventoryDelta(nextInventory, ingredient.itemId, -ingredient.quantity);
    }

    for (const output of recipe.outputs) {
      nextInventory = applyInventoryDelta(nextInventory, output.itemId, output.quantity);
    }

    return {
      gold,
      inventory: nextInventory,
      value: {
        recipeId: recipe.id,
        inventory: nextInventory,
      },
    };
  });
}
