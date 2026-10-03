export const MAX_RECIPE_COMPONENTS = 32;
export const MAX_RECIPE_QUANTITY = 1_000_000;

export type RecipeStation = "hand" | "workbench" | "forge" | "alchemy";

export interface RecipeComponent {
  readonly itemId: string;
  readonly quantity: number;
}

export interface RecipeDefinition {
  readonly id: string;
  readonly name: string;
  readonly station: RecipeStation;
  readonly craftTimeMs: number;
  readonly ingredients: readonly RecipeComponent[];
  readonly outputs: readonly RecipeComponent[];
}

const ITEM_ID_PATTERN = /^[a-z0-9]+(?:[._-][a-z0-9]+)*$/;
const RECIPE_ID_PATTERN = /^[a-z0-9]+(?:[._-][a-z0-9]+)*$/;

export function validateRecipeId(recipeId: string): void {
  if (typeof recipeId !== "string" || recipeId.length < 1 || recipeId.length > 128 || !RECIPE_ID_PATTERN.test(recipeId)) {
    throw new Error("INVALID_RECIPE_ID");
  }
}

export function validateRecipeItemId(itemId: string): void {
  if (typeof itemId !== "string" || itemId.length < 1 || itemId.length > 128 || !ITEM_ID_PATTERN.test(itemId)) {
    throw new Error("INVALID_RECIPE_ITEM_ID");
  }
}

export function validateRecipeQuantity(quantity: number): void {
  if (!Number.isSafeInteger(quantity) || quantity < 1 || quantity > MAX_RECIPE_QUANTITY) {
    throw new Error("INVALID_RECIPE_QUANTITY");
  }
}

export function validateCraftTime(craftTimeMs: number): void {
  if (!Number.isSafeInteger(craftTimeMs) || craftTimeMs < 0 || craftTimeMs > 86_400_000) {
    throw new Error("INVALID_RECIPE_CRAFT_TIME");
  }
}

export function validateRecipeComponent(component: RecipeComponent): void {
  validateRecipeItemId(component.itemId);
  validateRecipeQuantity(component.quantity);
}

export function validateRecipe(recipe: RecipeDefinition): void {
  validateRecipeId(recipe.id);

  if (typeof recipe.name !== "string" || recipe.name.trim().length < 1 || recipe.name.length > 128) {
    throw new Error("INVALID_RECIPE_NAME");
  }

  if (!["hand", "workbench", "forge", "alchemy"].includes(recipe.station)) {
    throw new Error("INVALID_RECIPE_STATION");
  }

  validateCraftTime(recipe.craftTimeMs);

  if (recipe.ingredients.length < 1 || recipe.ingredients.length > MAX_RECIPE_COMPONENTS) {
    throw new Error("INVALID_RECIPE_INGREDIENTS");
  }

  if (recipe.outputs.length < 1 || recipe.outputs.length > MAX_RECIPE_COMPONENTS) {
    throw new Error("INVALID_RECIPE_OUTPUTS");
  }

  const ingredientIds = new Set<string>();
  for (const component of recipe.ingredients) {
    validateRecipeComponent(component);
    if (ingredientIds.has(component.itemId)) throw new Error("DUPLICATE_RECIPE_INGREDIENT");
    ingredientIds.add(component.itemId);
  }

  const outputIds = new Set<string>();
  for (const component of recipe.outputs) {
    validateRecipeComponent(component);
    if (outputIds.has(component.itemId)) throw new Error("DUPLICATE_RECIPE_OUTPUT");
    outputIds.add(component.itemId);
  }
}

export function validateRecipeCatalogue(recipes: readonly RecipeDefinition[]): void {
  if (recipes.length < 1) throw new Error("EMPTY_RECIPE_CATALOGUE");

  const ids = new Set<string>();
  for (const recipe of recipes) {
    validateRecipe(recipe);
    if (ids.has(recipe.id)) throw new Error("DUPLICATE_RECIPE_ID");
    ids.add(recipe.id);
  }
}

export const RECIPE_CATALOGUE: readonly RecipeDefinition[] = Object.freeze([
  {
    id: "tool.wooden-club",
    name: "Wooden Club",
    station: "hand",
    craftTimeMs: 1_500,
    ingredients: Object.freeze([
      { itemId: "resource.wood", quantity: 8 },
    ]),
    outputs: Object.freeze([
      { itemId: "tool.wooden-club", quantity: 1 },
    ]),
  },
  {
    id: "tool.stone-axe",
    name: "Stone Axe",
    station: "workbench",
    craftTimeMs: 3_000,
    ingredients: Object.freeze([
      { itemId: "resource.wood", quantity: 6 },
      { itemId: "resource.stone", quantity: 4 },
    ]),
    outputs: Object.freeze([
      { itemId: "tool.stone-axe", quantity: 1 },
    ]),
  },
  {
    id: "tool.stone-pickaxe",
    name: "Stone Pickaxe",
    station: "workbench",
    craftTimeMs: 3_000,
    ingredients: Object.freeze([
      { itemId: "resource.wood", quantity: 6 },
      { itemId: "resource.stone", quantity: 5 },
    ]),
    outputs: Object.freeze([
      { itemId: "tool.stone-pickaxe", quantity: 1 },
    ]),
  },
  {
    id: "structure.campfire",
    name: "Campfire",
    station: "hand",
    craftTimeMs: 2_500,
    ingredients: Object.freeze([
      { itemId: "resource.wood", quantity: 8 },
      { itemId: "resource.stone", quantity: 4 },
    ]),
    outputs: Object.freeze([
      { itemId: "structure.campfire", quantity: 1 },
    ]),
  },
  {
    id: "structure.wooden-wall",
    name: "Wooden Wall",
    station: "workbench",
    craftTimeMs: 2_000,
    ingredients: Object.freeze([
      { itemId: "resource.wood", quantity: 10 },
    ]),
    outputs: Object.freeze([
      { itemId: "structure.wooden-wall", quantity: 1 },
    ]),
  },
  {
    id: "consumable.herb-bandage",
    name: "Herb Bandage",
    station: "hand",
    craftTimeMs: 1_500,
    ingredients: Object.freeze([
      { itemId: "resource.herb", quantity: 3 },
    ]),
    outputs: Object.freeze([
      { itemId: "consumable.herb-bandage", quantity: 1 },
    ]),
  },
]);

validateRecipeCatalogue(RECIPE_CATALOGUE);

const RECIPE_BY_ID = new Map(RECIPE_CATALOGUE.map((recipe) => [recipe.id, recipe]));

export function getRecipe(recipeId: string): RecipeDefinition | undefined {
  validateRecipeId(recipeId);
  return RECIPE_BY_ID.get(recipeId);
}
