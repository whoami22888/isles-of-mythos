import { describe, expect, it, vi } from "vitest";
import { craftRecipe } from "./crafting.js";

describe("rollback failure preserves the originating transaction error", () => {
  it("crafting preserves BEGIN failure and evicts the broken connection", async () => {
    const original = new Error("begin failed");
    const rollback = new Error("rollback failed");
    const release = vi.fn();
    const query = vi.fn().mockRejectedValueOnce(original).mockRejectedValueOnce(rollback);
    const db = { connect: vi.fn().mockResolvedValue({ query, release }) };
    await expect(craftRecipe(db as never, "player", "request", "tool.wooden-club")).rejects.toBe(original);
    expect(query.mock.calls.map((call) => call[0])).toEqual(["BEGIN", "ROLLBACK"]);
    expect(release).toHaveBeenCalledExactlyOnceWith(rollback);
  });

  it("crafting releases a healthy connection after successful rollback", async () => {
    const original = new Error("begin failed");
    const release = vi.fn();
    const query = vi.fn().mockRejectedValueOnce(original).mockResolvedValueOnce({ rows: [] });
    const db = { connect: vi.fn().mockResolvedValue({ query, release }) };
    await expect(craftRecipe(db as never, "player", "request", "tool.wooden-club")).rejects.toBe(original);
    expect(release).toHaveBeenCalledExactlyOnceWith(undefined);
  });
});
