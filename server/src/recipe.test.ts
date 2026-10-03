import { describe, expect, it } from "vitest";
import {
  RECIPE_CATALOGUE,
  getRecipe,
  validateRecipe,
  validateRecipeCatalogue,
} from "./recipe.js";

describe("recipe catalogue", () => {
  it("contains data-driven recipes with valid ingredients and outputs", () => {
    expect(RECIPE_CATALOGUE.length).toBeGreaterThan(0);

    for (const recipe of RECIPE_CATALOGUE) {
      expect(recipe.id).toBeTruthy();
      expect(recipe.ingredients.length).toBeGreaterThan(0);
      expect(recipe.outputs.length).toBeGreaterThan(0);
    }
  });

  it("retrieves recipes by stable server-side id", () => {
    expect(getRecipe("tool.stone-axe")?.name).toBe("Stone Axe");
    expect(getRecipe("missing.recipe")).toBeUndefined();
  });

  it("rejects duplicate recipe ids", () => {
    const recipe = RECIPE_CATALOGUE[0];
    expect(() => validateRecipeCatalogue([recipe, recipe])).toThrow("DUPLICATE_RECIPE_ID");
  });

  it("rejects duplicate ingredients and outputs", () => {
    const recipe = {
      ...RECIPE_CATALOGUE[0],
      ingredients: [
        { itemId: "resource.wood", quantity: 1 },
        { itemId: "resource.wood", quantity: 2 },
      ],
    };
    expect(() => validateRecipe(recipe)).toThrow("DUPLICATE_RECIPE_INGREDIENT");

    const outputRecipe = {
      ...RECIPE_CATALOGUE[0],
      outputs: [
        { itemId: "tool.wooden-club", quantity: 1 },
        { itemId: "tool.wooden-club", quantity: 2 },
      ],
    };
    expect(() => validateRecipe(outputRecipe)).toThrow("DUPLICATE_RECIPE_OUTPUT");
  });

  it("rejects unsafe quantities and malformed item ids", () => {
    const recipe = {
      ...RECIPE_CATALOGUE[0],
      ingredients: [{ itemId: "resource.wood", quantity: 0 }],
    };
    expect(() => validateRecipe(recipe)).toThrow("INVALID_RECIPE_QUANTITY");

    const invalidIdRecipe = {
      ...RECIPE_CATALOGUE[0],
      outputs: [{ itemId: "Resource/Wood", quantity: 1 }],
    };
    expect(() => validateRecipe(invalidIdRecipe)).toThrow("INVALID_RECIPE_ITEM_ID");
  });

  it("rejects empty component lists", () => {
    const recipe = {
      ...RECIPE_CATALOGUE[0],
      ingredients: [],
    };
    expect(() => validateRecipe(recipe)).toThrow("INVALID_RECIPE_INGREDIENTS");
  });
});
