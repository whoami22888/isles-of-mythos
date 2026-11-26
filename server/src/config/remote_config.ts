import { decodeMsgpack, encodeMsgpack } from "./msgpack.js";

export interface BalanceSheet {
  version: number;
  dropRates: Record<string, number>;
  prices: Record<string, number>;
  events: Record<string, unknown>;
}

export class RemoteConfig {
  private version = 0;
  private sheet: BalanceSheet = { version: 0, dropRates: {}, prices: {}, events: {} };

  publish(next: Omit<BalanceSheet, "version">): BalanceSheet {
    this.version += 1;
    this.sheet = { version: this.version, ...next };
    return this.sheet;
  }

  current(): BalanceSheet {
    return this.sheet;
  }

  payload(): Uint8Array {
    return encodeMsgpack(this.sheet);
  }

  static fromPayload(payload: Uint8Array): BalanceSheet {
    return decodeMsgpack(payload) as BalanceSheet;
  }
}
