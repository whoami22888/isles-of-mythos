import type { FastifyInstance, FastifyRequest } from "fastify";
import type { Pool, PoolClient } from "pg";
import { isGameplayAccessToken } from "./auth.js";
import { addGoldDoubloons, runEconomyMutation } from "./economy.js";
import type { PlayerStore } from "./player.js";

/**
 * Daily objectives. Progress is never client-reported: it is summed from the
 * authoritative gather and craft ledgers for the current UTC day, and a reward
 * can be claimed once per objective per day inside one locked transaction.
 */
export type DailyObjective =
  | { id: string; kind: "gather"; itemId: string; target: number; rewardGold: bigint }
  | { id: string; kind: "craft"; target: number; rewardGold: bigint };

export const DAILY_OBJECTIVES: readonly DailyObjective[] = [
  { id: "gather.wood", kind: "gather", itemId: "resource.wood", target: 10, rewardGold: 50n },
  { id: "gather.stone", kind: "gather", itemId: "resource.stone", target: 6, rewardGold: 40n },
  { id: "craft.any", kind: "craft", target: 2, rewardGold: 60n },
];

export interface DailyObjectiveView {
  objectiveId: string;
  kind: DailyObjective["kind"];
  itemId?: string;
  target: number;
  progress: number;
  complete: boolean;
  claimed: boolean;
  rewardGold: string;
}

export interface DailyClaimResult {
  objectiveId: string;
  day: string;
  transactionId: string;
  rewardGold: string;
  replayed: boolean;
}

export function utcDay(now: Date): string {
  return now.toISOString().slice(0, 10);
}

type Queryable = Pick<Pool | PoolClient, "query">;

async function progressFor(db: Queryable, userId: string, objective: DailyObjective, day: string): Promise<number> {
  if (objective.kind === "gather") {
    const { rows } = await db.query<{ total: string | null }>(
      "SELECT COALESCE(SUM(quantity),0)::bigint AS total FROM resource_gather_requests WHERE user_id=$1 AND item_id=$2 AND created_at >= $3::date AND created_at < ($3::date + 1)",
      [userId, objective.itemId, day],
    );
    return Number(rows[0]?.total ?? 0);
  }
  const { rows } = await db.query<{ total: string }>(
    "SELECT COUNT(*)::bigint AS total FROM craft_requests WHERE user_id=$1 AND created_at >= $2::date AND created_at < ($2::date + 1)",
    [userId, day],
  );
  return Number(rows[0]?.total ?? 0);
}

export class DailyObjectiveStore {
  constructor(private readonly db: Pool) {}

  async list(userId: string, now = new Date()): Promise<{ day: string; objectives: DailyObjectiveView[] }> {
    const day = utcDay(now);
    const claims = await this.db.query<{ objective_id: string }>(
      "SELECT objective_id FROM daily_objective_claims WHERE user_id=$1 AND objective_day=$2::date",
      [userId, day],
    );
    const claimed = new Set(claims.rows.map((row) => row.objective_id));
    const objectives = await Promise.all(DAILY_OBJECTIVES.map(async (objective) => {
      const progress = await progressFor(this.db, userId, objective, day);
      return {
        objectiveId: objective.id,
        kind: objective.kind,
        ...(objective.kind === "gather" ? { itemId: objective.itemId } : {}),
        target: objective.target,
        progress: Math.min(progress, objective.target),
        complete: progress >= objective.target,
        claimed: claimed.has(objective.id),
        rewardGold: objective.rewardGold.toString(),
      };
    }));
    return { day, objectives };
  }

  async claim(userId: string, objectiveId: string, now = new Date()): Promise<DailyClaimResult> {
    const objective = DAILY_OBJECTIVES.find((candidate) => candidate.id === objectiveId);
    if (!objective) throw new Error("DAILY_OBJECTIVE_NOT_FOUND");
    const day = utcDay(now);
    const client = await this.db.connect();
    try {
      await client.query("BEGIN");
      // Lock the player row first so concurrent claims for the same player serialize.
      const player = await client.query("SELECT 1 FROM player_profiles WHERE user_id=$1 FOR UPDATE", [userId]);
      if (!player.rows[0]) throw new Error("PLAYER_NOT_FOUND");
      const existing = await client.query<{ transaction_id: string; reward_gold: string }>(
        "SELECT transaction_id, reward_gold FROM daily_objective_claims WHERE user_id=$1 AND objective_day=$2::date AND objective_id=$3",
        [userId, day, objective.id],
      );
      const prior = existing.rows[0];
      if (prior) {
        // Replay: no economy write, so the audit trail records only the real payout.
        await client.query("COMMIT");
        return { objectiveId: objective.id, day, transactionId: prior.transaction_id, rewardGold: prior.reward_gold, replayed: true };
      }
      const result = await runEconomyMutation(client, userId, async (draft) => {
        const progress = await progressFor(client, userId, objective, day);
        if (progress < objective.target) throw new Error("DAILY_OBJECTIVE_INCOMPLETE");
        const inserted = await client.query<{ transaction_id: string }>(
          "INSERT INTO daily_objective_claims(user_id, objective_day, objective_id, reward_gold) VALUES($1,$2::date,$3,$4) RETURNING transaction_id",
          [userId, day, objective.id, objective.rewardGold.toString()],
        );
        const transactionId = inserted.rows[0]?.transaction_id;
        if (!transactionId) throw new Error("DAILY_OBJECTIVE_TRANSACTION_MISSING");
        return {
          gold: addGoldDoubloons(draft.gold, objective.rewardGold),
          inventory: draft.inventory,
          value: { objectiveId: objective.id, day, transactionId, rewardGold: objective.rewardGold.toString(), replayed: false },
        };
      }, "daily_objective_claim");
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

async function verifyPlayer(request: FastifyRequest): Promise<boolean> {
  try {
    await request.jwtVerify();
  } catch {
    return false;
  }
  return isGameplayAccessToken(request.user);
}

export function registerDailyObjectiveRoutes(app: FastifyInstance, db: Pool, players: PlayerStore): void {
  const store = new DailyObjectiveStore(db);

  app.get("/daily-objectives", {
    schema: { tags: ["progression"], security: [{ bearerAuth: [] }] },
    config: { rateLimit: { max: 60, timeWindow: "1 minute" } },
  }, async (request, reply) => {
    if (!(await verifyPlayer(request))) return reply.code(401).send({ error: "UNAUTHORIZED" });
    const userId = request.user.sub;
    await players.ensureProfile(userId);
    return store.list(userId);
  });

  app.post<{ Body: { objectiveId: string } }>("/daily-objectives/claim", {
    schema: {
      tags: ["progression"],
      security: [{ bearerAuth: [] }],
      body: {
        type: "object",
        additionalProperties: false,
        required: ["objectiveId"],
        properties: { objectiveId: { type: "string", minLength: 1, maxLength: 64, pattern: "^[a-z]+\\.[a-z]+$" } },
      },
    },
    config: { rateLimit: { max: 30, timeWindow: "1 minute" } },
  }, async (request, reply) => {
    if (!(await verifyPlayer(request))) return reply.code(401).send({ error: "UNAUTHORIZED" });
    const userId = request.user.sub;
    try {
      return await players.runExclusive(userId, async () => {
        await players.ensureProfile(userId);
        const result = await store.claim(userId, request.body.objectiveId);
        // Keep an in-world player's cached gold in step with the committed reward.
        if (players.get(userId)) await players.reloadEconomy(userId);
        return result;
      });
    } catch (error) {
      const code = error instanceof Error ? error.message : "";
      if (code === "DAILY_OBJECTIVE_NOT_FOUND") return reply.code(404).send({ error: code });
      if (code === "DAILY_OBJECTIVE_INCOMPLETE") return reply.code(409).send({ error: code });
      if (code === "PLAYER_NOT_FOUND") return reply.code(404).send({ error: code });
      throw error;
    }
  });
}
