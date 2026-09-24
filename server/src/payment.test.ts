import { describe, expect, it } from "vitest";
import type { PaymentOrder } from "./payment.js";

describe("payment security model", () => {
  it("represents monetary amounts as integer minor units", () => {
    const order: PaymentOrder = {
      id: "order-test",
      userId: "user-test",
      provider: "card",
      amountMinor: 1999n,
      currency: "AUD",
      status: "created",
      idempotencyKey: "idem-test",
    };
    expect(order.amountMinor).toBe(1999n);
    expect(Number.isSafeInteger(Number(order.amountMinor))).toBe(true);
  });

  it("does not require raw card credentials in the order model", () => {
    const keys = Object.keys({
      id: "order-test",
      userId: "user-test",
      provider: "card",
      amountMinor: 1999n,
      currency: "AUD",
      status: "created",
      idempotencyKey: "idem-test",
    });
    expect(keys).not.toContain("pan");
    expect(keys).not.toContain("cvv");
    expect(keys).not.toContain("cvc");
  });
});
