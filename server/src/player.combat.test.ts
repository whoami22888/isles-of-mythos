import { describe, expect, it } from "vitest";
import { createDefaultPlayer, meleeHitbox, playerHitbox } from "./player.js";

describe("server player combat geometry", () => {
  it("creates a centered player hitbox", () => {
    const hitbox = playerHitbox({ x: 10, y: 20 });
    expect(hitbox).toEqual({
      x: 9.65,
      y: 19.65,
      width: 0.7,
      height: 0.7,
    });
  });

  it("creates a directional melee hitbox without changing its authoritative size", () => {
    const hitbox = meleeHitbox({ x: 10, y: 20 }, 1, 0);
    expect(hitbox.width).toBe(1.5);
    expect(hitbox.height).toBe(1.5);
    expect(hitbox.x).toBe(10);
    expect(hitbox.y).toBe(19.25);
  });

  it("uses the server-defined starting combat loadout", () => {
    const player = createDefaultPlayer("player-1");
    expect(player.hotbar[0]).toBe("cutlass");
    expect(player.hotbar[1]).toBe("flintlock");
    expect(player.selectedHotbarSlot).toBe(0);
  });
});
