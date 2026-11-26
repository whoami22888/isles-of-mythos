import { describe, expect, it } from "vitest";
import {
  GooglePlayBilling,
  PURCHASE_TOKEN_CONSUMED,
  PURCHASE_TOKEN_CONSUMED_MESSAGE,
  httpStatusForBilling,
} from "./google_play_billing.js";

describe("Google Play billing fulfillment", () => {
  it("credits pearls once and rejects a duplicate token with HTTP 400", async () => {
    const tokens = new Set<string>();
    const billing = new GooglePlayBilling(
      { verify: async () => ({ ok: true, pearls: 120 }) },
      {
        findToken: async (token) => (tokens.has(token) ? { purchaseToken: token } : null),
        fulfill: async (purchase) => { tokens.add(purchase.purchaseToken); },
      },
    );
    await expect(billing.fulfillPurchase({
      purchaseToken: "tok-1",
      productId: "pearls_120",
      userId: "user-1",
    })).resolves.toEqual({ pearls: 120 });
    try {
      await billing.fulfillPurchase({
        purchaseToken: "tok-1",
        productId: "pearls_120",
        userId: "user-1",
      });
      throw new Error("expected duplicate token to fail");
    } catch (error) {
      const billed = error as Error & { code: string; httpStatus: number };
      expect(billed.message).toBe(PURCHASE_TOKEN_CONSUMED_MESSAGE);
      expect(billed.code).toBe(PURCHASE_TOKEN_CONSUMED);
      expect(httpStatusForBilling(billed)).toBe(400);
    }
  });
});
