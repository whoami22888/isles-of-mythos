import { describe, expect, it, vi } from "vitest";
import { craftRecipe } from "./crafting.js";
import { gatherResource } from "./resource-gathering.js";

const node = { id: "node-1", type: "wood", x: 0, y: 0 };

describe("rollback failure preserves the originating transaction error", () => {
  it("crafting preserves BEGIN failure and evicts the broken connection", async () => {
    const original = new Error("begin failed");
    const rollback = new Error("rollback failed");
    const release = vi.fn();
    const query = vi.fn().mockRejectedValueOnce(original).mockRejectedValueOnce(rollback);
    const db = { connect: vi.fn().mockResolvedValue({ query, release }) };
    await expect(craftRecipe(db as never, "player", "request", "tool.wooden-club")).rejects.toBe(original);
    expect(query).toHaveBeenNthCalledWith(1, "BEGIN");
    expect(query).toHaveBeenNthCalledWith(2, "ROLLBACK");
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

  it("gathering preserves a failed statement and evicts the connection when rollback fails", async () => {
    const original = new Error("statement failed");
    const rollback = new Error("rollback failed");
    const release = vi.fn();
    const query = vi.fn().mockResolvedValueOnce({ rows: [] }).mockRejectedValueOnce(original).mockRejectedValueOnce(rollback);
    const db = { connect: vi.fn().mockResolvedValue({ query, release }) };
    await expect(gatherResource(db as never, "player", "request", "gather_resource|node-1", node as never)).rejects.toBe(original);
    expect(query).toHaveBeenNthCalledWith(1, "BEGIN");
    expect(query).toHaveBeenNthCalledWith(2, expect.stringContaining("FROM resource_gather_requests"), ["player", "request"]);
    expect(query).toHaveBeenNthCalledWith(3, "ROLLBACK");
    expect(release).toHaveBeenCalledExactlyOnceWith(rollback);
  });

  it("gathering returns the connection to the pool after a successful rollback", async () => {
    const original = new Error("statement failed");
    const release = vi.fn();
    const query = vi.fn().mockResolvedValueOnce({ rows: [] }).mockRejectedValueOnce(original).mockResolvedValueOnce({ rows: [] });
    const db = { connect: vi.fn().mockResolvedValue({ query, release }) };
    await expect(gatherResource(db as never, "player", "request", "gather_resource|node-1", node as never)).rejects.toBe(original);
    expect(query).toHaveBeenNthCalledWith(3, "ROLLBACK");
    expect(release).toHaveBeenCalledExactlyOnceWith(undefined);
  });
});
