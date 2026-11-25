import type { FastifyInstance, FastifyRequest } from "fastify";
import type { Pool, PoolClient } from "pg";
import { isGameplayAccessToken } from "./auth.js";
import type { BaseStore } from "./base.js";
import { runEconomyMutation, subtractTriumphBadges } from "./economy.js";
import type { PlayerStore } from "./player.js";

/** Citadel is a distinct 1–20 track. Ordinary buildings stay on MAX_BUILDING_LEVEL=7. */
export const CITADEL_MIN_LEVEL = 1;
export const CITADEL_MAX_LEVEL = 20;
export const CITADEL_SOFT_WALL_FROM_LEVEL = 15;
export const CITADEL_SOFT_WALL_TARGET_LEVEL = 16;
export const CITADEL_SOFT_WALL_WOOD = 5_000_000;
export const CITADEL_SOFT_WALL_STEEL = 5_000_000;
export const CITADEL_SOFT_WALL_FOOD = 1_000_000;
export const CITADEL_SOFT_WALL_BADGES = 500;
export const CITADEL_SECOND_QUEUE_UNLOCK_LEVEL = 10;
export const CITADEL_DEFAULT_GUILD_HELP_SECONDS = 60;
export const CITADEL_MAX_GUILD_HELP_SECONDS = 86_400;

export type CitadelPaymentPath = "resources" | "badges";

export interface CitadelUpgradeCost {
  wood: number;
  steel: number;
  food: number;
  badge_alternative: number;
}

export interface CitadelQueueFlags {
  primary_busy: boolean;
  second_queue_enabled: boolean;
  secondary_busy: boolean;
}

export interface CitadelSnapshot {
  citadel_level: number;
  upgrade_started_at_unix: number;
  upgrade_completes_at_unix: number;
  upgrade_target_level: number;
  server_now_unix: number;
  guild_help_seconds_applied: number;
  queue_flags: CitadelQueueFlags;
  upgrade_costs: Record<string, CitadelUpgradeCost>;
}

export interface CitadelClock {
  nowUnix: () => number;
}

const DEFAULT_CLOCK: CitadelClock = {
  nowUnix: () => Math.floor(Date.now() / 1000),
};

// Explicit server-authoritative costs for every target level 2–20.
// Level 16 is the frozen soft-wall contract and must not drift.
const CITADEL_UPGRADE_COSTS: Record<number, CitadelUpgradeCost> = {
  2: { wood: 200, steel: 80, food: 40, badge_alternative: 0 },
  3: { wood: 400, steel: 160, food: 80, badge_alternative: 0 },
  4: { wood: 800, steel: 320, food: 160, badge_alternative: 0 },
  5: { wood: 1_600, steel: 640, food: 320, badge_alternative: 10 },
  6: { wood: 3_200, steel: 1_280, food: 640, badge_alternative: 15 },
  7: { wood: 6_400, steel: 2_560, food: 1_280, badge_alternative: 25 },
  8: { wood: 12_000, steel: 5_000, food: 2_500, badge_alternative: 40 },
  9: { wood: 24_000, steel: 10_000, food: 5_000, badge_alternative: 60 },
  10: { wood: 48_000, steel: 20_000, food: 10_000, badge_alternative: 90 },
  11: { wood: 90_000, steel: 40_000, food: 20_000, badge_alternative: 120 },
  12: { wood: 160_000, steel: 80_000, food: 40_000, badge_alternative: 160 },
  13: { wood: 300_000, steel: 150_000, food: 75_000, badge_alternative: 220 },
  14: { wood: 600_000, steel: 300_000, food: 150_000, badge_alternative: 300 },
  15: { wood: 1_200_000, steel: 600_000, food: 300_000, badge_alternative: 400 },
  16: {
    wood: CITADEL_SOFT_WALL_WOOD,
    steel: CITADEL_SOFT_WALL_STEEL,
    food: CITADEL_SOFT_WALL_FOOD,
    badge_alternative: CITADEL_SOFT_WALL_BADGES,
  },
  17: { wood: 2_500_000, steel: 1_250_000, food: 600_000, badge_alternative: 650 },
  18: { wood: 4_000_000, steel: 2_000_000, food: 1_000_000, badge_alternative: 850 },
  19: { wood: 6_500_000, steel: 3_250_000, food: 1_600_000, badge_alternative: 1_100 },
  20: { wood: 10_000_000, steel: 5_000_000, food: 2_500_000, badge_alternative: 1_500 },
};

const CITADEL_UPGRADE_DURATION_SECONDS: Record<number, number> = {
  2: 60,
  3: 120,
  4: 180,
  5: 300,
  6: 480,
  7: 720,
  8: 1_200,
  9: 1_800,
  10: 2_700,
  11: 3_600,
  12: 5_400,
  13: 7_200,
  14: 10_800,
  15: 14_400,
  16: 28_800,
  17: 36_000,
  18: 43_200,
  19: 54_000,
  20: 64_800,
};

interface CitadelRow {
  base_id: string;
  owner_user_id: string;
  citadel_level: number;
  upgrade_started_at_unix: string | number;
  upgrade_completes_at_unix: string | number;
  upgrade_target_level: number;
  guild_help_seconds_applied: number;
  payment_path: CitadelPaymentPath | null;
}

function toUnix(value: string | number): number {
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isSafeInteger(n) || n < 0) throw new Error("INVALID_CITADEL_TIMESTAMP");
  return n;
}

export function citadelUpgradeCostMatrix(): Record<string, CitadelUpgradeCost> {
  const matrix: Record<string, CitadelUpgradeCost> = {};
  for (let level = CITADEL_MIN_LEVEL + 1; level <= CITADEL_MAX_LEVEL; level += 1) {
    const cost = CITADEL_UPGRADE_COSTS[level];
    if (!cost) throw new Error("CITADEL_COST_MATRIX_INCOMPLETE");
    matrix[String(level)] = { ...cost };
  }
  return matrix;
}

export function getCitadelUpgradeCost(targetLevel: number): CitadelUpgradeCost {
  if (!Number.isSafeInteger(targetLevel) || targetLevel < 2 || targetLevel > CITADEL_MAX_LEVEL) {
    throw new Error("INVALID_CITADEL_LEVEL");
  }
  const cost = CITADEL_UPGRADE_COSTS[targetLevel];
  if (!cost) throw new Error("CITADEL_COST_MATRIX_INCOMPLETE");
  return { ...cost };
}

export function getCitadelUpgradeDurationSeconds(targetLevel: number): number {
  if (!Number.isSafeInteger(targetLevel) || targetLevel < 2 || targetLevel > CITADEL_MAX_LEVEL) {
    throw new Error("INVALID_CITADEL_LEVEL");
  }
  const duration = CITADEL_UPGRADE_DURATION_SECONDS[targetLevel];
  if (!Number.isSafeInteger(duration) || duration <= 0) throw new Error("CITADEL_DURATION_MISSING");
  return duration;
}

export function canAffordCitadelResources(
  storage: Record<string, number>,
  cost: CitadelUpgradeCost,
): boolean {
  return (
    (storage.wood ?? 0) >= cost.wood
    && (storage.steel ?? 0) >= cost.steel
    && (storage.food ?? 0) >= cost.food
    && (cost.wood > 0 || cost.steel > 0 || cost.food > 0)
  );
}

export function canAffordCitadelBadges(badges: bigint, cost: CitadelUpgradeCost): boolean {
  return cost.badge_alternative > 0 && badges >= BigInt(cost.badge_alternative);
}

export function resolveCitadelPayment(
  targetLevel: number,
  storage: Record<string, number>,
  badges: bigint,
  requested?: CitadelPaymentPath,
): CitadelPaymentPath {
  const cost = getCitadelUpgradeCost(targetLevel);
  const resources = canAffordCitadelResources(storage, cost);
  const badgePath = canAffordCitadelBadges(badges, cost);
  if (requested === "resources") {
    if (!resources) {
      throw new Error(targetLevel === CITADEL_SOFT_WALL_TARGET_LEVEL ? "CITADEL_SOFT_WALL_BLOCKED" : "INSUFFICIENT_CITADEL_RESOURCES");
    }
    return "resources";
  }
  if (requested === "badges") {
    if (cost.badge_alternative <= 0) throw new Error("INVALID_CITADEL_PAYMENT");
    if (!badgePath) {
      throw new Error(targetLevel === CITADEL_SOFT_WALL_TARGET_LEVEL ? "CITADEL_SOFT_WALL_BLOCKED" : "INSUFFICIENT_TRIUMPH_BADGES");
    }
    return "badges";
  }
  if (resources) return "resources";
  if (badgePath) return "badges";
  throw new Error(targetLevel === CITADEL_SOFT_WALL_TARGET_LEVEL ? "CITADEL_SOFT_WALL_BLOCKED" : "INSUFFICIENT_CITADEL_RESOURCES");
}

function queueFlags(level: number, upgrading: boolean): CitadelQueueFlags {
  return {
    primary_busy: upgrading,
    second_queue_enabled: level >= CITADEL_SECOND_QUEUE_UNLOCK_LEVEL,
    secondary_busy: false,
  };
}

function toSnapshot(row: CitadelRow, nowUnix: number): CitadelSnapshot {
  const started = toUnix(row.upgrade_started_at_unix);
  return {
    citadel_level: row.citadel_level,
    upgrade_started_at_unix: started,
    upgrade_completes_at_unix: toUnix(row.upgrade_completes_at_unix),
    upgrade_target_level: row.upgrade_target_level,
    server_now_unix: nowUnix,
    guild_help_seconds_applied: row.guild_help_seconds_applied,
    queue_flags: queueFlags(row.citadel_level, started > 0),
    upgrade_costs: citadelUpgradeCostMatrix(),
  };
}

async function loadStorage(client: Pick<Pool | PoolClient, "query">, baseId: string): Promise<Record<string, number>> {
  const result = await client.query<{ resource_key: string; quantity: string }>(
    "SELECT resource_key, quantity FROM base_storage WHERE base_id=$1",
    [baseId],
  );
  return Object.fromEntries(result.rows.map((row) => [row.resource_key, Number(row.quantity)]));
}

async function deductResources(client: PoolClient, baseId: string, cost: CitadelUpgradeCost): Promise<void> {
  for (const resource of ["wood", "steel", "food"] as const) {
    const quantity = cost[resource];
    if (quantity <= 0) continue;
    const locked = await client.query<{ quantity: string }>(
      "SELECT quantity FROM base_storage WHERE base_id=$1 AND resource_key=$2 FOR UPDATE",
      [baseId, resource],
    );
    if (Number(locked.rows[0]?.quantity ?? 0) < quantity) throw new Error("INSUFFICIENT_CITADEL_RESOURCES");
    await client.query(
      "UPDATE base_storage SET quantity=quantity-$3, updated_at=CURRENT_TIMESTAMP WHERE base_id=$1 AND resource_key=$2",
      [baseId, resource, quantity],
    );
  }
}

export class CitadelStore {
  constructor(
    private readonly db: Pool,
    private readonly clock: CitadelClock = DEFAULT_CLOCK,
  ) {}

  async snapshot(userId: string): Promise<CitadelSnapshot> {
    const row = await this.ensureRow(userId);
    return toSnapshot(row, this.clock.nowUnix());
  }

  async requestUpgrade(
    userId: string,
    queueSlot: number,
    payment?: CitadelPaymentPath,
  ): Promise<CitadelSnapshot> {
    if (queueSlot !== 1 && queueSlot !== 2) throw new Error("INVALID_CITADEL_QUEUE_SLOT");
    const client = await this.db.connect();
    try {
      await client.query("BEGIN");
      const row = await this.lockRow(client, userId);
      if (row.upgrade_target_level > 0) throw new Error("CITADEL_UPGRADE_IN_PROGRESS");
      if (row.citadel_level >= CITADEL_MAX_LEVEL) throw new Error("CITADEL_MAX_LEVEL");
      const flags = queueFlags(row.citadel_level, false);
      if (queueSlot === 1 && flags.primary_busy) throw new Error("CITADEL_QUEUE_BUSY");
      if (queueSlot === 2 && !flags.second_queue_enabled) throw new Error("CITADEL_SECOND_QUEUE_LOCKED");
      if (queueSlot === 2 && flags.secondary_busy) throw new Error("CITADEL_QUEUE_BUSY");

      const targetLevel = row.citadel_level + 1;
      if (targetLevel === CITADEL_SOFT_WALL_TARGET_LEVEL && row.citadel_level !== CITADEL_SOFT_WALL_FROM_LEVEL) {
        throw new Error("CITADEL_SOFT_WALL_BLOCKED");
      }
      const cost = getCitadelUpgradeCost(targetLevel);
      const storage = await loadStorage(client, row.base_id);
      const profile = await client.query<{ triumph_badges: string }>(
        "SELECT triumph_badges FROM player_profiles WHERE user_id=$1 FOR UPDATE",
        [userId],
      );
      if (!profile.rows[0]) throw new Error("PLAYER_NOT_FOUND");
      const badges = BigInt(profile.rows[0].triumph_badges);
      const path = resolveCitadelPayment(targetLevel, storage, badges, payment);

      if (path === "resources") {
        await deductResources(client, row.base_id, cost);
      } else {
        await runEconomyMutation(client, userId, (draft) => ({
          gold: draft.gold,
          triumphBadges: subtractTriumphBadges(draft.triumphBadges, BigInt(cost.badge_alternative)),
          inventory: draft.inventory,
          value: undefined,
        }), "citadel_upgrade_badges");
      }

      const started = this.clock.nowUnix();
      const completes = started + getCitadelUpgradeDurationSeconds(targetLevel);
      const updated = await client.query<CitadelRow>(
        `UPDATE player_citadels
         SET upgrade_started_at_unix=$2,
             upgrade_completes_at_unix=$3,
             upgrade_target_level=$4,
             guild_help_seconds_applied=0,
             payment_path=$5,
             updated_at=CURRENT_TIMESTAMP
         WHERE base_id=$1
         RETURNING base_id, owner_user_id, citadel_level, upgrade_started_at_unix, upgrade_completes_at_unix, upgrade_target_level, guild_help_seconds_applied, payment_path`,
        [row.base_id, started, completes, targetLevel, path],
      );
      await client.query("COMMIT");
      return toSnapshot(updated.rows[0], started);
    } catch (error) {
      await client.query("ROLLBACK").catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  async completeUpgrade(userId: string): Promise<CitadelSnapshot> {
    const client = await this.db.connect();
    try {
      await client.query("BEGIN");
      const row = await this.lockRow(client, userId);
      if (row.upgrade_target_level <= 0) throw new Error("CITADEL_NO_UPGRADE");
      const now = this.clock.nowUnix();
      if (now < toUnix(row.upgrade_completes_at_unix)) throw new Error("CITADEL_UPGRADE_INCOMPLETE");
      const updated = await client.query<CitadelRow>(
        `UPDATE player_citadels
         SET citadel_level=$2,
             upgrade_started_at_unix=0,
             upgrade_completes_at_unix=0,
             upgrade_target_level=0,
             guild_help_seconds_applied=0,
             payment_path=NULL,
             updated_at=CURRENT_TIMESTAMP
         WHERE base_id=$1
         RETURNING base_id, owner_user_id, citadel_level, upgrade_started_at_unix, upgrade_completes_at_unix, upgrade_target_level, guild_help_seconds_applied, payment_path`,
        [row.base_id, row.upgrade_target_level],
      );
      await client.query("COMMIT");
      return toSnapshot(updated.rows[0], now);
    } catch (error) {
      await client.query("ROLLBACK").catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  async applyGuildHelp(userId: string, seconds = CITADEL_DEFAULT_GUILD_HELP_SECONDS): Promise<CitadelSnapshot> {
    if (!Number.isSafeInteger(seconds) || seconds <= 0 || seconds > CITADEL_MAX_GUILD_HELP_SECONDS) {
      throw new Error("INVALID_CITADEL_GUILD_HELP");
    }
    const client = await this.db.connect();
    try {
      await client.query("BEGIN");
      const row = await this.lockRow(client, userId);
      if (row.upgrade_target_level <= 0) throw new Error("CITADEL_NO_UPGRADE");
      const started = toUnix(row.upgrade_started_at_unix);
      const completes = toUnix(row.upgrade_completes_at_unix);
      const reduced = Math.max(started + 1, completes - seconds);
      if (reduced >= completes) throw new Error("INVALID_CITADEL_GUILD_HELP");
      const applied = row.guild_help_seconds_applied + (completes - reduced);
      const now = this.clock.nowUnix();
      const updated = await client.query<CitadelRow>(
        `UPDATE player_citadels
         SET upgrade_completes_at_unix=$2,
             guild_help_seconds_applied=$3,
             updated_at=CURRENT_TIMESTAMP
         WHERE base_id=$1
         RETURNING base_id, owner_user_id, citadel_level, upgrade_started_at_unix, upgrade_completes_at_unix, upgrade_target_level, guild_help_seconds_applied, payment_path`,
        [row.base_id, reduced, applied],
      );
      await client.query("COMMIT");
      return toSnapshot(updated.rows[0], now);
    } catch (error) {
      await client.query("ROLLBACK").catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  private async ensureRow(userId: string): Promise<CitadelRow> {
    const existing = await this.db.query<CitadelRow>(
      "SELECT base_id, owner_user_id, citadel_level, upgrade_started_at_unix, upgrade_completes_at_unix, upgrade_target_level, guild_help_seconds_applied, payment_path FROM player_citadels WHERE owner_user_id=$1",
      [userId],
    );
    if (existing.rows[0]) return existing.rows[0];
    const base = await this.db.query<{ id: string }>("SELECT id FROM player_bases WHERE owner_user_id=$1", [userId]);
    if (!base.rows[0]) throw new Error("BASE_NOT_FOUND");
    const inserted = await this.db.query<CitadelRow>(
      `INSERT INTO player_citadels(base_id, owner_user_id, citadel_level)
       VALUES($1,$2,1)
       ON CONFLICT (owner_user_id) DO UPDATE SET owner_user_id=EXCLUDED.owner_user_id
       RETURNING base_id, owner_user_id, citadel_level, upgrade_started_at_unix, upgrade_completes_at_unix, upgrade_target_level, guild_help_seconds_applied, payment_path`,
      [base.rows[0].id, userId],
    );
    if (!inserted.rows[0]) throw new Error("CITADEL_LOAD_FAILED");
    return inserted.rows[0];
  }

  private async lockRow(client: PoolClient, userId: string): Promise<CitadelRow> {
    const base = await client.query<{ id: string }>(
      "SELECT id FROM player_bases WHERE owner_user_id=$1 FOR UPDATE",
      [userId],
    );
    if (!base.rows[0]) throw new Error("BASE_NOT_FOUND");
    const existing = await client.query<CitadelRow>(
      "SELECT base_id, owner_user_id, citadel_level, upgrade_started_at_unix, upgrade_completes_at_unix, upgrade_target_level, guild_help_seconds_applied, payment_path FROM player_citadels WHERE owner_user_id=$1 FOR UPDATE",
      [userId],
    );
    if (existing.rows[0]) return existing.rows[0];
    const inserted = await client.query<CitadelRow>(
      `INSERT INTO player_citadels(base_id, owner_user_id, citadel_level)
       VALUES($1,$2,1)
       RETURNING base_id, owner_user_id, citadel_level, upgrade_started_at_unix, upgrade_completes_at_unix, upgrade_target_level, guild_help_seconds_applied, payment_path`,
      [base.rows[0].id, userId],
    );
    if (!inserted.rows[0]) throw new Error("CITADEL_LOAD_FAILED");
    return inserted.rows[0];
  }
}

async function verifyPlayer(request: FastifyRequest): Promise<string | null> {
  try {
    await request.jwtVerify();
  } catch {
    return null;
  }
  const userId = request.user.sub;
  return isGameplayAccessToken(request.user) && typeof userId === "string" && userId.length > 0 ? userId : null;
}

function httpStatusFor(code: string): number {
  if (code === "UNAUTHORIZED") return 401;
  if (code === "BASE_NOT_FOUND" || code === "PLAYER_NOT_FOUND") return 404;
  if (
    code === "CITADEL_SOFT_WALL_BLOCKED"
    || code === "INSUFFICIENT_CITADEL_RESOURCES"
    || code === "INSUFFICIENT_TRIUMPH_BADGES"
    || code === "CITADEL_QUEUE_BUSY"
    || code === "CITADEL_UPGRADE_IN_PROGRESS"
    || code === "CITADEL_MAX_LEVEL"
    || code === "CITADEL_NO_UPGRADE"
    || code === "CITADEL_UPGRADE_INCOMPLETE"
    || code === "CITADEL_SECOND_QUEUE_LOCKED"
    || code === "INVALID_CITADEL_PAYMENT"
    || code === "INVALID_CITADEL_QUEUE_SLOT"
    || code === "INVALID_CITADEL_GUILD_HELP"
  ) return 409;
  return 500;
}

export function registerCitadelRoutes(
  app: FastifyInstance,
  db: Pool,
  players: PlayerStore,
  bases?: BaseStore,
  onEconomyChanged?: (userId: string) => void,
  clock: CitadelClock = DEFAULT_CLOCK,
): CitadelStore {
  const store = new CitadelStore(db, clock);

  const afterMutation = async (userId: string): Promise<void> => {
    if (bases?.get(userId)) await bases.load(userId);
    if (players.get(userId)) {
      await players.reloadEconomy(userId);
      onEconomyChanged?.(userId);
    }
  };

  app.get("/citadel", {
    schema: { tags: ["progression"], security: [{ bearerAuth: [] }] },
    config: { rateLimit: { max: 60, timeWindow: "1 minute" } },
  }, async (request, reply) => {
    const userId = await verifyPlayer(request);
    if (!userId) return reply.code(401).send({ error: "UNAUTHORIZED" });
    try {
      await players.ensureProfile(userId);
      return await store.snapshot(userId);
    } catch (error) {
      const code = error instanceof Error ? error.message : "";
      const status = httpStatusFor(code);
      if (status < 500) return reply.code(status).send({ error: code });
      throw error;
    }
  });

  app.post<{ Body: { queue_slot?: number; payment?: CitadelPaymentPath } }>("/citadel/upgrade", {
    schema: {
      tags: ["progression"],
      security: [{ bearerAuth: [] }],
      body: {
        type: "object",
        additionalProperties: false,
        properties: {
          queue_slot: { type: "integer", minimum: 1, maximum: 2 },
          payment: { type: "string", enum: ["resources", "badges"] },
        },
      },
    },
    config: { rateLimit: { max: 30, timeWindow: "1 minute" } },
  }, async (request, reply) => {
    const userId = await verifyPlayer(request);
    if (!userId) return reply.code(401).send({ error: "UNAUTHORIZED" });
    try {
      return await players.runExclusive(userId, async () => {
        await players.ensureProfile(userId);
        const result = await store.requestUpgrade(userId, request.body?.queue_slot ?? 1, request.body?.payment);
        await afterMutation(userId);
        return result;
      });
    } catch (error) {
      const code = error instanceof Error ? error.message : "";
      const status = httpStatusFor(code);
      if (status < 500) return reply.code(status).send({ error: code });
      throw error;
    }
  });

  app.post("/citadel/complete", {
    schema: { tags: ["progression"], security: [{ bearerAuth: [] }] },
    config: { rateLimit: { max: 30, timeWindow: "1 minute" } },
  }, async (request, reply) => {
    const userId = await verifyPlayer(request);
    if (!userId) return reply.code(401).send({ error: "UNAUTHORIZED" });
    try {
      return await players.runExclusive(userId, async () => {
        await players.ensureProfile(userId);
        return store.completeUpgrade(userId);
      });
    } catch (error) {
      const code = error instanceof Error ? error.message : "";
      const status = httpStatusFor(code);
      if (status < 500) return reply.code(status).send({ error: code });
      throw error;
    }
  });

  app.post<{ Body: { seconds?: number } }>("/citadel/guild-help", {
    schema: {
      tags: ["progression"],
      security: [{ bearerAuth: [] }],
      body: {
        type: "object",
        additionalProperties: false,
        properties: { seconds: { type: "integer", minimum: 1, maximum: CITADEL_MAX_GUILD_HELP_SECONDS } },
      },
    },
    config: { rateLimit: { max: 30, timeWindow: "1 minute" } },
  }, async (request, reply) => {
    const userId = await verifyPlayer(request);
    if (!userId) return reply.code(401).send({ error: "UNAUTHORIZED" });
    try {
      return await players.runExclusive(userId, async () => {
        await players.ensureProfile(userId);
        return store.applyGuildHelp(userId, request.body?.seconds ?? CITADEL_DEFAULT_GUILD_HELP_SECONDS);
      });
    } catch (error) {
      const code = error instanceof Error ? error.message : "";
      const status = httpStatusFor(code);
      if (status < 500) return reply.code(status).send({ error: code });
      throw error;
    }
  });

  return store;
}
