import { createHmac } from "node:crypto";

export const SHARD_REGIONS = ["AU", "US", "EU"] as const;
export type ShardRegion = (typeof SHARD_REGIONS)[number];
export const GLOBAL_CURRENCY_LEDGER = "global-postgres";

export interface ShardDefinition {
  region: ShardRegion;
  spatialNode: string;
}

export const SHARDS: Readonly<Record<ShardRegion, ShardDefinition>> = {
  AU: { region: "AU", spatialNode: "enet://au-east.spatial.internal:7777" },
  US: { region: "US", spatialNode: "enet://us-west.spatial.internal:7777" },
  EU: { region: "EU", spatialNode: "enet://eu-central.spatial.internal:7777" },
};

export interface RouteInput {
  userId: string;
  regionHint?: string;
  country?: string;
  pingMs?: Partial<Record<ShardRegion, number>>;
}

export interface RoutedSession {
  userId: string;
  region: ShardRegion;
  spatialNode: string;
  currencyLedger: typeof GLOBAL_CURRENCY_LEDGER;
  sessionToken: string;
  issuedAtMs: number;
}

const COUNTRY_TO_REGION: Readonly<Record<string, ShardRegion>> = {
  AU: "AU", AUS: "AU", NZ: "AU", NZL: "AU",
  US: "US", USA: "US", CA: "US", CAN: "US",
  GB: "EU", UK: "EU", DE: "EU", FR: "EU", NL: "EU", IE: "EU", ES: "EU", IT: "EU",
};

export class ShardRouter {
  constructor(private readonly tokenSecret = "dev-shard-router") {}

  route(input: RouteInput, nowMs = Date.now()): RoutedSession {
    const region = this.selectRegion(input);
    const shard = SHARDS[region];
    const issuedAtMs = nowMs;
    const sessionToken = this.issueToken(input.userId, region, issuedAtMs);
    return {
      userId: input.userId,
      region,
      spatialNode: shard.spatialNode,
      currencyLedger: GLOBAL_CURRENCY_LEDGER,
      sessionToken,
      issuedAtMs,
    };
  }

  verify(token: string): { userId: string; region: ShardRegion; issuedAtMs: number } | null {
    const [payload, signature] = splitToken(token);
    if (!payload || !signature) return null;
    const expected = sign(payload, this.tokenSecret);
    if (expected !== signature) return null;
    const [version, userId, region, issued] = payload.split(":");
    if (version !== "iom1" || !userId) return null;
    if (!SHARD_REGIONS.includes(region as ShardRegion)) return null;
    const issuedAtMs = Number(issued);
    if (!Number.isFinite(issuedAtMs)) return null;
    return { userId, region: region as ShardRegion, issuedAtMs };
  }

  private selectRegion(input: RouteInput): ShardRegion {
    const hinted = normalizeRegion(input.regionHint) ?? countryRegion(input.country);
    if (hinted) return hinted;
    if (input.pingMs) {
      let best: ShardRegion | null = null;
      let bestPing = Number.POSITIVE_INFINITY;
      for (const region of SHARD_REGIONS) {
        const ping = input.pingMs[region];
        if (typeof ping === "number" && Number.isFinite(ping) && ping < bestPing) {
          best = region;
          bestPing = ping;
        }
      }
      if (best) return best;
    }
    return "US";
  }

  private issueToken(userId: string, region: ShardRegion, issuedAtMs: number): string {
    const payload = `iom1:${userId}:${region}:${issuedAtMs}`;
    return `${payload}.${sign(payload, this.tokenSecret)}`;
  }
}

function normalizeRegion(value: string | undefined): ShardRegion | null {
  if (!value) return null;
  const upper = value.trim().toUpperCase();
  return SHARD_REGIONS.includes(upper as ShardRegion) ? (upper as ShardRegion) : null;
}

function countryRegion(country: string | undefined): ShardRegion | null {
  if (!country) return null;
  return COUNTRY_TO_REGION[country.trim().toUpperCase()] ?? null;
}

function sign(payload: string, secret: string): string {
  return createHmac("sha256", secret).update(payload).digest("base64url");
}

function splitToken(token: string): [string | null, string | null] {
  const index = token.lastIndexOf(".");
  if (index <= 0 || index === token.length - 1) return [null, null];
  return [token.slice(0, index), token.slice(index + 1)];
}

