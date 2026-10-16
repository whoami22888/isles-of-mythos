import { describe, expect, it } from "vitest";
import { createDbPool } from "./db.js";

describe("database pool capacity", () => {
  it("defaults to the concurrency needed by the gameplay acceptance workload", async () => {
    const pool = createDbPool();
    try {
      expect(pool.options.max).toBe(50);
    } finally {
      await pool.end();
    }
  });
});
