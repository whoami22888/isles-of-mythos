import { describe, expect, it } from "vitest";
import { ImpulseStore, OFFER_EXPIRED, publishedWindow } from "./impulse_store.js";

describe("fair published catalog windows", () => {
  it("rejects a purchase 16 minutes after a published 15-minute global window starts", () => {
    const startsAt = 1_700_000_000_000;
    const store = new ImpulseStore([publishedWindow("seasonal.supply-crate", startsAt)]);
    expect(store.purchase("seasonal.supply-crate", startsAt + 60_000)).toEqual({
      sku: "seasonal.supply-crate",
      purchasedAtMs: startsAt + 60_000,
    });
    expect(() => store.purchase("seasonal.supply-crate", startsAt + 16 * 60 * 1000)).toThrow(OFFER_EXPIRED);
  });

  it("does not create personal offers from frustration or the citadel soft wall", () => {
    const store = new ImpulseStore([]);
    expect(store.activeOffers(Date.now())).toEqual([]);
    expect(() => store.purchase("barrier-buster", Date.now())).toThrow("OFFER_UNKNOWN");
  });
});
