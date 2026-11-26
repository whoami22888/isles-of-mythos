import { describe, expect, it } from "vitest";
import { RemoteConfig } from "./remote_config.js";

describe("remote MessagePack config", () => {
  it("hot-patches drop rates and serves the new versioned sheet to a subsequent fetch", () => {
    const config = new RemoteConfig();
    config.publish({ dropRates: { wood: 0.2 }, prices: { crate: 10 }, events: {} });
    const updated = config.publish({ dropRates: { wood: 0.35 }, prices: { crate: 8 }, events: { weekend_boost: true } });
    expect(updated.version).toBe(2);
    expect(RemoteConfig.fromPayload(config.payload())).toEqual({
      version: 2,
      dropRates: { wood: 0.35 },
      prices: { crate: 8 },
      events: { weekend_boost: true },
    });
  });
});
