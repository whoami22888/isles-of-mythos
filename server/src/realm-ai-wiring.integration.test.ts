import { afterEach, describe, expect, it, vi } from "vitest";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";
import { RealmStore } from "./realm.js";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// Vitest runs each test file in its own worker, so a spy on the prototype only sees this file's apps.
// Counting calls (not DB rows) keeps this test independent of other files that also write realm_ai_events.
describe("realm AI is server-scheduled (NET-04 slice 2b)", () => {
  afterEach(() => vi.restoreAllMocks());

  it("ticks on the server timer after listen and stops ticking after close", async () => {
    const calls = vi.spyOn(RealmStore.prototype, "tickAI");
    const db = createDbPool();
    const app = await buildApp({ db, realmAiTickMs: 100 });
    try {
      await app.listen({ host: "127.0.0.1", port: 0 });
      for (let i = 0; i < 100 && calls.mock.calls.length === 0; i++) await sleep(100);
      expect(calls.mock.calls.length, "server scheduler called tickAI without any client message").toBeGreaterThan(0);
    } finally {
      await app.close();
    }
    const afterClose = calls.mock.calls.length;
    await sleep(500);
    expect(calls.mock.calls.length).toBe(afterClose);
    await db.end();
  }, 30_000);
});
