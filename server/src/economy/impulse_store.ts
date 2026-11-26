/**
 * Fair catalog windows. Offers are scheduled, published, and identical for every player.
 * They are never generated from frustration index or the Citadel L15 soft wall.
 */

export const OFFER_EXPIRED = "OFFER_EXPIRED";
export const OFFER_NOT_ACTIVE = "OFFER_NOT_ACTIVE";
export const OFFER_UNKNOWN = "OFFER_UNKNOWN";

export interface PublishedCatalogOffer {
  sku: string;
  name: string;
  priceUsd: string;
  startsAtMs: number;
  endsAtMs: number;
}

export interface PurchaseReceipt {
  sku: string;
  purchasedAtMs: number;
}

export class ImpulseStore {
  constructor(private readonly catalog: readonly PublishedCatalogOffer[] = []) {}

  /** Catalog entries currently inside their published global window. */
  activeOffers(nowMs: number): PublishedCatalogOffer[] {
    return this.catalog.filter((offer) => nowMs >= offer.startsAtMs && nowMs <= offer.endsAtMs);
  }

  purchase(sku: string, nowMs: number): PurchaseReceipt {
    const offer = this.catalog.find((entry) => entry.sku === sku);
    if (!offer) throw new Error(OFFER_UNKNOWN);
    if (nowMs < offer.startsAtMs) throw new Error(OFFER_NOT_ACTIVE);
    if (nowMs > offer.endsAtMs) throw new Error(OFFER_EXPIRED);
    return { sku: offer.sku, purchasedAtMs: nowMs };
  }
}

/** Example of a public 15-minute calendar window, not a personal pressure timer. */
export function publishedWindow(sku: string, startsAtMs: number, durationMs = 15 * 60 * 1000): PublishedCatalogOffer {
  return {
    sku,
    name: "Seasonal Supply Crate",
    priceUsd: "0.99",
    startsAtMs,
    endsAtMs: startsAtMs + durationMs,
  };
}
