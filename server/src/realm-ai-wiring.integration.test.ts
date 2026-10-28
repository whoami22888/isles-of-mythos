import { describe, expect, it } from "vitest";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

describe("realm AI is server-scheduled (NET-04 slice 2b)", () => {
  it("ticks on the server timer after listen and stops ticking after close", async () => {
    const db = createDbPool();
    await db.query("DELETE FROM realm_ai_events WHERE event_type='tick'");
    const app = await buildApp({ db, realmAiTickMs: 100 });
    try {
      await app.listen({ host: "127.0.0.1", port: 0 });
      let count = 0;
      for (let i = 0; i < 40 && count === 0; i++) {
        await sleep(100);
        count = Number((await db.query<{ c: string }>("SELECT COUNT(*)::text c FROM realm_ai_events WHERE event_type='tick'")).rows[0].c);
      }
      expect(count, "server scheduler produced a realm tick without any client message").toBeGreaterThan(0);
    } finally {
      await app.close();
    }
    const after = Number((await db.query<{ c: string }>("SELECT COUNT(*)::text c FROM realm_ai_events WHERE event_type='tick'")).rows[0].c);
    await sleep(500);
    const later = Number((await db.query<{ c: string }>("SELECT COUNT(*)::text c FROM realm_ai_events WHERE event_type='tick'")).rows[0].c);
    expect(later).toBe(after);
    await db.end();
  }, 20_000);

  it("does not start a scheduler when disabled", async () => {
    const db = createDbPool();
    await db.query("DELETE FROM realm_ai_events WHERE event_type='tick'");
    const app = await buildApp({ db, realmAiTickMs: 0 });
    try {
      await app.listen({ host: "127.0.0.1", port: 0 });
      await sleep(400);
      const c = Number((await db.query<{ c: string }>("SELECT COUNT(*)::text c FROM realm_ai_events WHERE event_type='tick'")).rows[0].c);
      expect(c).toBe(0);
    } finally {
      await app.close();
    }
    await db.end();
  }, 20_000);
});
