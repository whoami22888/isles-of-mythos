import { describe, expect, it } from "vitest";
import { GameState } from "./game-state.js";

describe("game foundation", () => {
  it("defines the expected state machine values", () => {
    expect(Object.values(GameState)).toEqual([
      "MENU",
      "OVERWORLD",
      "BASE_BUILD",
      "COMBAT_UI",
    ]);
  });
});
