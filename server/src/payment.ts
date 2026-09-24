export type PaymentProvider = "paypal" | "google_pay" | "card";
export type PaymentStatus =
  | "created"
  | "pending"
  | "authorized"
  | "captured"
  | "failed"
  | "voided"
  | "refunded"
  | "disputed";

export interface PaymentOrder {
  id: string;
  userId: string;
  provider: PaymentProvider;
  amountMinor: bigint;
  currency: string;
  status: PaymentStatus;
  idempotencyKey: string;
  providerOrderId?: string;
  providerPaymentId?: string;
}

export interface SavedPaymentMethod {
  id: string;
  userId: string;
  provider: PaymentProvider;
  providerTokenId: string;
  brand?: string;
  last4?: string;
  expiryMonth?: number;
  expiryYear?: number;
}

/** Payment providers must use tokenized/hosted collection. Raw card credentials never enter the game server. */
export interface PaymentProviderAdapter {
  createOrder(order: PaymentOrder): Promise<{ providerOrderId: string }>;
  captureOrder(providerOrderId: string): Promise<{ providerPaymentId: string; status: PaymentStatus }>;
  refund(providerPaymentId: string, amountMinor?: bigint): Promise<void>;
  verifyWebhookSignature(rawBody: string, signature: string): boolean;
}
