export const PURCHASE_TOKEN_CONSUMED = "PURCHASE_TOKEN_ALREADY_CONSUMED";
export const PURCHASE_TOKEN_CONSUMED_MESSAGE = "Purchase Token Already Consumed";
export const INVALID_PURCHASE_TOKEN = "INVALID_PURCHASE_TOKEN";

export interface PlayPurchase {
  purchaseToken: string;
  productId: string;
  pearls: number;
  userId: string;
}

export interface PlayVerifier {
  verify(purchaseToken: string, productId: string): Promise<{ ok: boolean; pearls: number }>;
}

export interface BillingStore {
  findToken(purchaseToken: string): Promise<{ purchaseToken: string } | null>;
  fulfill(purchase: PlayPurchase): Promise<void>;
}

export class GooglePlayBilling {
  constructor(private readonly verifier: PlayVerifier, private readonly store: BillingStore) {}

  async fulfillPurchase(input: { purchaseToken: string; productId: string; userId: string }): Promise<{ pearls: number }> {
    const existing = await this.store.findToken(input.purchaseToken);
    if (existing) {
      const error = new Error(PURCHASE_TOKEN_CONSUMED_MESSAGE);
      (error as Error & { code: string; httpStatus: number }).code = PURCHASE_TOKEN_CONSUMED;
      (error as Error & { code: string; httpStatus: number }).httpStatus = 400;
      throw error;
    }
    const verified = await this.verifier.verify(input.purchaseToken, input.productId);
    if (!verified.ok) {
      const error = new Error("Invalid purchase token");
      (error as Error & { code: string }).code = INVALID_PURCHASE_TOKEN;
      throw error;
    }
    await this.store.fulfill({
      purchaseToken: input.purchaseToken,
      productId: input.productId,
      pearls: verified.pearls,
      userId: input.userId,
    });
    return { pearls: verified.pearls };
  }
}

export function httpStatusForBilling(error: { code?: string; httpStatus?: number }): number {
  return error.httpStatus ?? (error.code === PURCHASE_TOKEN_CONSUMED ? 400 : 500);
}
