import { afterEach, describe, expect, it, vi } from "vitest";
import type { Pool } from "pg";
import { buildApp } from "./app.js";
import * as logger from "./logger.js";

afterEach(() => vi.restoreAllMocks());

describe("world chunk diagnostic coverage", () => {
  it("includes response hooks and emits only after response completion", async () => {
    let responseHookCompleted = false;
    const records: Array<{ data: Record<string, unknown>; completed: boolean }> = [];
    vi.spyOn(logger, "log").mockImplementation((event, data = {}) => {
      if (event === "world_chunk_slow_request") records.push({ data, completed: responseHookCompleted });
    });
    const db = { query: () => Promise.resolve({ rows: [] }) } as unknown as Pool;
    const app = await buildApp({ db });
    app.addHook("onSend", async (_request, _reply, payload) => {
      await new Promise(resolve => setTimeout(resolve, 40));
      responseHookCompleted = true;
      return payload;
    });
    try {
      const response = await app.inject({ method: "GET", url: "/world/chunks/0/0" });
      expect(response.statusCode).toBe(200);
      expect(records).toHaveLength(1);
      expect(records[0].completed).toBe(true);
      expect(records[0].data.totalMs).toBeGreaterThanOrEqual(25);
      expect(Object.keys(records[0].data).sort()).toEqual(
        ["captureLoadMs", "generationMs", "resourceQueryMs", "totalMs"].sort(),
      );
      expect(records[0].data.generationMs).toEqual(expect.any(Number));
      expect(records[0].data.resourceQueryMs).toEqual(expect.any(Number));
    } finally { await app.close(); }
  });

  it("retains slow failed capture-load timing without changing the error response", async () => {
    const records: Record<string, unknown>[] = [];
    vi.spyOn(logger, "log").mockImplementation((event, data = {}) => {
      if (event === "world_chunk_slow_request") records.push(data);
    });
    const db = { query: async () => {
      await new Promise(resolve => setTimeout(resolve, 40));
      throw new Error("DATABASE_UNAVAILABLE");
    } } as unknown as Pool;
    const app = await buildApp({ db });
    try {
      const response = await app.inject({ method: "GET", url: "/world/chunks/0/0" });
      expect(response.statusCode).toBe(500);
      expect(records).toHaveLength(1);
      expect(records[0].captureLoadMs).toBeGreaterThanOrEqual(25);
      expect(records[0].generationMs).toBeNull();
      expect(records[0].resourceQueryMs).toBeNull();
    } finally { await app.close(); }
  });
});
