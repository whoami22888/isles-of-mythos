import type { FastifyInstance, FastifyRequest } from "fastify";
import type { Pool } from "pg";
import { isGameplayAccessToken } from "./auth.js";
import { addGoldDoubloons, applyInventoryDelta, cloneInventory, runEconomyMutation } from "./economy.js";
import type { PlayerStore } from "./player.js";

/**
 * Ship expeditions. The server owns the clock (returns_at is computed in SQL from
 * now()), the route catalogue and the reward. Clients send only ship, route and an
 * idempotency key; collect pays once inside a transaction that locks the player.
 */
export interface ExpeditionRoute {
  id: string;
  durationSeconds: number;
  items: Record<string, number>;
  gold: bigint;
}

export const EXPEDITION_ROUTES: Readonly<Record<string, ExpeditionRoute>> = {
  "reef.short": { id: "reef.short", durationSeconds: 120, items: { "resource.wood": 6, "resource.stone": 4 }, gold: 20n },
  "isles.long": { id: "isles.long", durationSeconds: 900, items: { "resource.wood": 20, "resource.herb": 6 }, gold: 80n },
};

interface ExpeditionRow {
  id: string;
  ship_id: string;
  route_id: string;
  request_id: string;
  started_at: Date;
  returns_at: Date;
  collected_at: Date | null;
  reward: { items: Record<string, number>; gold: string };
}

export interface ExpeditionView {
  expeditionId: string;
  shipId: string;
  routeId: string;
  startedAt: string;
  returnsAt: string;
  collectedAt: string | null;
  reward: { items: Record<string, number>; gold: string };
}

function view(row: ExpeditionRow): ExpeditionView {
  return {
    expeditionId: row.id,
    shipId: row.ship_id,
    routeId: row.route_id,
    startedAt: new Date(row.started_at).toISOString(),
    returnsAt: new Date(row.returns_at).toISOString(),
    collectedAt: row.collected_at ? new Date(row.collected_at).toISOString() : null,
    reward: row.reward,
  };
}

const COLUMNS = "id, ship_id, route_id, request_id, started_at, returns_at, collected_at, reward";

export class ExpeditionStore {
  constructor(private readonly db: Pool) {}

  async list(userId: string): Promise<ExpeditionView[]> {
    const { rows } = await this.db.query<ExpeditionRow>(
      `SELECT ${COLUMNS} FROM ship_expeditions WHERE owner_user_id=$1 AND (collected_at IS NULL OR collected_at > now() - interval '1 day') ORDER BY started_at DESC LIMIT 50`,
      [userId],
    );
    return rows.map(view);
  }

  async start(userId: string, shipId: string, routeId: string, requestId: string): Promise<ExpeditionView & { replayed: boolean }> {
    const route = EXPEDITION_ROUTES[routeId];
    if (!route) throw new Error("EXPEDITION_ROUTE_NOT_FOUND");
    const client = await this.db.connect();
    try {
      await client.query("BEGIN");
      const ship = await client.query<{ status: string }>("SELECT status FROM player_ships WHERE id=$1 AND owner_user_id=$2 FOR UPDATE", [shipId, userId]);
      if (!ship.rows[0]) throw new Error("SHIP_NOT_FOUND");
      // Replays are checked after the ship lock so a concurrent duplicate sees the winner's row.
      const prior = await client.query<ExpeditionRow>(`SELECT ${COLUMNS} FROM ship_expeditions WHERE owner_user_id=$1 AND request_id=$2`, [userId, requestId]);
      if (prior.rows[0]) {
        if (prior.rows[0].ship_id !== shipId || prior.rows[0].route_id !== routeId) throw new Error("EXPEDITION_REQUEST_CONFLICT");
        await client.query("COMMIT");
        return { ...view(prior.rows[0]), replayed: true };
      }
      if (ship.rows[0].status !== "active") throw new Error("SHIP_NOT_ACTIVE");
      const reward = { items: route.items, gold: route.gold.toString() };
      const inserted = await client.query<ExpeditionRow>(
        `INSERT INTO ship_expeditions(owner_user_id, ship_id, route_id, request_id, returns_at, reward) VALUES($1,$2,$3,$4, now() + ($5 * interval '1 second'), $6::jsonb) RETURNING ${COLUMNS}`,
        [userId, shipId, route.id, requestId, route.durationSeconds, JSON.stringify(reward)],
      );
      await client.query("UPDATE player_ships SET status='docked', updated_at=CURRENT_TIMESTAMP WHERE id=$1", [shipId]);
      await client.query("COMMIT");
      return { ...view(inserted.rows[0]), replayed: false };
    } catch (error) {
      await client.query("ROLLBACK").catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  async collect(userId: string, expeditionId: string): Promise<ExpeditionView & { replayed: boolean }> {
    const client = await this.db.connect();
    try {
      await client.query("BEGIN");
      // Lock order matches economy mutations: player row first, then the expedition.
      const player = await client.query("SELECT 1 FROM player_profiles WHERE user_id=$1 FOR UPDATE", [userId]);
      if (!player.rows[0]) throw new Error("PLAYER_NOT_FOUND");
      const found = await client.query<ExpeditionRow & { returned: boolean }>(
        `SELECT ${COLUMNS}, returns_at <= now() AS returned FROM ship_expeditions WHERE id=$1 AND owner_user_id=$2 FOR UPDATE`,
        [expeditionId, userId],
      );
      const row = found.rows[0];
      if (!row) throw new Error("EXPEDITION_NOT_FOUND");
      if (row.collected_at) {
        // Replay: no economy write, so the audit trail records only the real payout.
        await client.query("COMMIT");
        return { ...view(row), replayed: true };
      }
      if (!row.returned) throw new Error("EXPEDITION_IN_PROGRESS");
      const result = await runEconomyMutation(client, userId, async (draft) => {
        let inventory = cloneInventory(draft.inventory);
        for (const [itemId, quantity] of Object.entries(row.reward.items)) inventory = applyInventoryDelta(inventory, itemId, quantity);
        const updated = await client.query<ExpeditionRow>(`UPDATE ship_expeditions SET collected_at=now() WHERE id=$1 RETURNING ${COLUMNS}`, [row.id]);
        await client.query("UPDATE player_ships SET status='active', updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND status='docked'", [row.ship_id]);
        return { gold: addGoldDoubloons(draft.gold, BigInt(row.reward.gold)), inventory, value: { ...view(updated.rows[0]), replayed: false } };
      }, "ship_expedition_collect");
      await client.query("COMMIT");
      return result;
    } catch (error) {
      await client.query("ROLLBACK").catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
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

const ERRORS: Record<string, number> = {
  EXPEDITION_ROUTE_NOT_FOUND: 404,
  SHIP_NOT_FOUND: 404,
  EXPEDITION_NOT_FOUND: 404,
  PLAYER_NOT_FOUND: 404,
  SHIP_NOT_ACTIVE: 409,
  EXPEDITION_IN_PROGRESS: 409,
  EXPEDITION_REQUEST_CONFLICT: 409,
};
const UUID = "^[0-9a-fA-F-]{36}$";

// `onEconomyChanged` lets the WebSocket layer push the refreshed player_state to an in-world
// player, so the HUD shows the reward at once instead of on the next move.
export function registerExpeditionRoutes(app: FastifyInstance, db: Pool, players: PlayerStore, onEconomyChanged?: (userId: string) => void): void {
  const store = new ExpeditionStore(db);
  const fail = (error: unknown): { code: number; error: string } | null => {
    const code = error instanceof Error ? error.message : "";
    if (code in ERRORS) return { code: ERRORS[code], error: code };
    // A second open expedition for the same ship loses the partial unique index race.
    if (typeof error === "object" && error !== null && (error as { code?: string }).code === "23505") return { code: 409, error: "SHIP_NOT_ACTIVE" };
    return null;
  };

  app.get("/expeditions", {
    schema: { tags: ["naval"], security: [{ bearerAuth: [] }] },
    config: { rateLimit: { max: 60, timeWindow: "1 minute" } },
  }, async (request, reply) => {
    const userId = await verifyPlayer(request);
    if (!userId) return reply.code(401).send({ error: "UNAUTHORIZED" });
    // Only the caller's own ships, and only what the expedition picker needs.
    const ships = await db.query<{ id: string; name: string; status: string }>(
      "SELECT id, name, status FROM player_ships WHERE owner_user_id=$1 AND status IN ('active','docked') ORDER BY created_at, id",
      [userId],
    );
    return {
      routes: Object.values(EXPEDITION_ROUTES).map((r) => ({ routeId: r.id, durationSeconds: r.durationSeconds, items: r.items, gold: r.gold.toString() })),
      ships: ships.rows.map((row) => ({ shipId: row.id, name: row.name, status: row.status })),
      expeditions: await store.list(userId),
    };
  });

  app.post<{ Body: { shipId: string; routeId: string; requestId: string } }>("/expeditions/start", {
    schema: {
      tags: ["naval"],
      security: [{ bearerAuth: [] }],
      body: {
        type: "object", additionalProperties: false, required: ["shipId", "routeId", "requestId"],
        properties: {
          shipId: { type: "string", pattern: UUID },
          routeId: { type: "string", minLength: 1, maxLength: 32, pattern: "^[a-z]+\\.[a-z]+$" },
          requestId: { type: "string", minLength: 8, maxLength: 64, pattern: "^[A-Za-z0-9_-]+$" },
        },
      },
    },
    config: { rateLimit: { max: 30, timeWindow: "1 minute" } },
  }, async (request, reply) => {
    const userId = await verifyPlayer(request);
    if (!userId) return reply.code(401).send({ error: "UNAUTHORIZED" });
    try {
      return await store.start(userId, request.body.shipId, request.body.routeId, request.body.requestId);
    } catch (error) {
      const mapped = fail(error);
      if (mapped) return reply.code(mapped.code).send({ error: mapped.error });
      throw error;
    }
  });

  app.post<{ Body: { expeditionId: string } }>("/expeditions/collect", {
    schema: {
      tags: ["naval"],
      security: [{ bearerAuth: [] }],
      body: { type: "object", additionalProperties: false, required: ["expeditionId"], properties: { expeditionId: { type: "string", pattern: UUID } } },
    },
    config: { rateLimit: { max: 30, timeWindow: "1 minute" } },
  }, async (request, reply) => {
    const userId = await verifyPlayer(request);
    if (!userId) return reply.code(401).send({ error: "UNAUTHORIZED" });
    try {
      return await players.runExclusive(userId, async () => {
        await players.ensureProfile(userId);
        const result = await store.collect(userId, request.body.expeditionId);
        if (players.get(userId)) {
          await players.reloadEconomy(userId);
          onEconomyChanged?.(userId);
        }
        return result;
      });
    } catch (error) {
      const mapped = fail(error);
      if (mapped) return reply.code(mapped.code).send({ error: mapped.error });
      throw error;
    }
  });
}
