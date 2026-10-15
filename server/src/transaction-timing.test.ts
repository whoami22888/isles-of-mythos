import { describe, expect, it } from "vitest";
import type { Pool } from "pg";
import { craftRecipe } from "./crafting.js";
import { gatherResource, resourceGatherFingerprint } from "./resource-gathering.js";
import { createMutationTiming } from "./mutation-timing.js";

// Execute the real mutation control flow; only the PostgreSQL transport is fake.
function database(failAt?: string) {
  const error = new Error("DATABASE_FAILURE");
  const calls: string[] = [];
  let released = false;
  const client = {
    query(sql: string) {
      calls.push(sql);
      if (sql === failAt) return Promise.reject(error);
      if (sql.includes("SELECT gold")) return Promise.resolve({ rows: [{ gold: "0", triumph_badges: "0", inventory: { "resource.wood": 8 } }], rowCount: 1 });
      if (sql.startsWith("SELECT 1")) return Promise.resolve({ rows: [{}], rowCount: 1 });
      if (sql.startsWith("SELECT fingerprint")) return Promise.resolve({ rows: [], rowCount: 0 });
      if (sql.startsWith("SELECT node_id")) return Promise.resolve({ rows: [{ node_id: "wood:1:1", type: "wood", x: 1, y: 1, depleted_until: null }], rowCount: 1 });
      if (sql.startsWith("UPDATE world_resource_nodes")) return Promise.resolve({ rows: [{ depleted_until: "2030-01-01T00:00:00Z" }], rowCount: 1 });
      return Promise.resolve({ rows: [{ transaction_id: "test-transaction" }], rowCount: 1 });
    },
    release() { released = true; },
  };
  const pool = { connect() { return failAt === "connect" ? Promise.reject(error) : Promise.resolve(client); } } as unknown as Pool;
  return { pool, error, calls, released: () => released };
}

const actions = {
  craft: (db: Pool, timing?: ReturnType<typeof createMutationTiming>) => craftRecipe(db, "test-user", "test-request", "tool.wooden-club", timing),
  gather: (db: Pool, timing?: ReturnType<typeof createMutationTiming>) => gatherResource(db, "test-user", "test-request", resourceGatherFingerprint("wood:1:1"), { id: "wood:1:1", type: "wood", x: 1, y: 1 }, timing),
};

for (const [name, action] of Object.entries(actions)) {
  describe(name + " transaction timing", () => {
    it("records successful transaction phases without changing the result", async () => {
      const db = database();
      const timing = createMutationTiming();
      const result = await action(db.pool, timing);
      expect(result.transactionId).toBe("test-transaction");
      expect(Object.keys(timing.stages).sort()).toEqual(["beginMs", "commitMs", "poolAcquireMs"]);
      expect(Object.values(timing.stages).every(value => value >= 0)).toBe(true);
      expect(db.calls.at(-1)).toBe("COMMIT");
      expect(db.released()).toBe(true);
    });

    for (const phase of ["connect", "BEGIN", "COMMIT"]) {
      it("records failed " + phase + " and preserves rejection/cleanup", async () => {
        const db = database(phase);
        const timing = createMutationTiming();
        await expect(action(db.pool, timing)).rejects.toBe(db.error);
        expect(timing.stages.poolAcquireMs).toBeGreaterThanOrEqual(0);
        if (phase === "connect") {
          expect(db.calls).toEqual([]);
          expect(db.released()).toBe(false);
        } else {
          expect(timing.stages.beginMs).toBeGreaterThanOrEqual(0);
          if (phase === "COMMIT") expect(timing.stages.commitMs).toBeGreaterThanOrEqual(0);
          expect(timing.stages.rollbackMs).toBeGreaterThanOrEqual(0);
          expect(db.calls.at(-1)).toBe("ROLLBACK");
          expect(db.released()).toBe(true);
        }
      });
    }

    it("preserves the existing call signature without diagnostics", async () => {
      const db = database();
      expect((await action(db.pool)).transactionId).toBe("test-transaction");
      expect(db.released()).toBe(true);
    });
  });
}
