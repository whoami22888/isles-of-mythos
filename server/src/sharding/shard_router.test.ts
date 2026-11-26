import { describe, expect, it } from "vitest";
import { GLOBAL_CURRENCY_LEDGER, ShardRouter } from "./shard_router.js";

describe("shard router", () => {
  it("routes an AU player to the AU spatial shard and issues a verifiable session token", () => {
    const router = new ShardRouter("test-secret");
    const session = router.route({
      userId: "player-au-1",
      country: "AU",
      pingMs: { AU: 28, US: 180, EU: 240 },
    }, 1_700_000_000_000);
    expect(session.region).toBe("AU");
    expect(session.spatialNode).toContain("au-east");
    expect(session.currencyLedger).toBe(GLOBAL_CURRENCY_LEDGER);
    const verified = router.verify(session.sessionToken);
    expect(verified).toEqual({ userId: "player-au-1", region: "AU", issuedAtMs: 1_700_000_000_000 });
  });

  it("falls back to the lowest ping when no geo hint is provided", () => {
    const session = new ShardRouter().route({ userId: "ping-eu", pingMs: { AU: 300, US: 120, EU: 40 } });
    expect(session.region).toBe("EU");
  });
});
