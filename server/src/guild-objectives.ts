import type { FastifyInstance, FastifyRequest } from "fastify";
import type { Pool, PoolClient } from "pg";
import { isGameplayAccessToken } from "./auth.js";
import { addGoldDoubloons, runEconomyMutation } from "./economy.js";
import type { PlayerStore } from "./player.js";

/**
 * Weekly guild objectives. The guild's progress is the sum of its current members'
 * committed gathers this UTC week (each member counted only after they joined). A member
 * who personally contributed at least `minContribution` may claim the reward once per week.
 */
export interface GuildObjective {
  id: string;
  itemId: string;
  target: number;
  minContribution: number;
  rewardGold: bigint;
}

export const GUILD_OBJECTIVES: readonly GuildObjective[] = [
  { id: "guild.wood", itemId: "resource.wood", target: 200, minContribution: 10, rewardGold: 30n },
];

type Queryable = Pick<Pool | PoolClient, "query">;

interface Progress { guildId: string; weekStart: string; guildTotal: number; mine: number }

// Both week bounds are built in UTC wall-clock time and converted once. Adding '7 days' to a
// timestamptz would use the session time zone and shift the end by an hour across a DST change.
export async function progressFor(db: Queryable, userId: string, objective: GuildObjective, asOf?: Date): Promise<Progress | null> {
  const { rows } = await db.query<{ guild_id: string; week_start: string; guild_total: string; mine: string }>(
    `WITH me AS (SELECT guild_id FROM guild_members WHERE user_id=$1),
          utc AS (SELECT date_trunc('week', COALESCE($3::timestamptz, now()) AT TIME ZONE 'UTC') AS start),
          wk AS (SELECT start AT TIME ZONE 'UTC' AS start, (start + interval '7 days') AT TIME ZONE 'UTC' AS finish FROM utc)
     SELECT me.guild_id,
            to_char((SELECT start FROM wk) AT TIME ZONE 'UTC', 'YYYY-MM-DD') AS week_start,
            COALESCE(SUM(r.quantity), 0)::bigint AS guild_total,
            COALESCE(SUM(r.quantity) FILTER (WHERE r.user_id = $1), 0)::bigint AS mine
       FROM me
       JOIN guild_members m ON m.guild_id = me.guild_id
       LEFT JOIN resource_gather_requests r
         ON r.user_id = m.user_id AND r.item_id = $2
        AND r.created_at >= GREATEST(m.joined_at, (SELECT start FROM wk))
        AND r.created_at < (SELECT finish FROM wk)
      GROUP BY me.guild_id`,
    [userId, objective.itemId, asOf ?? null],
  );
  const row = rows[0];
  if (!row) return null;
  return { guildId: row.guild_id, weekStart: row.week_start, guildTotal: Number(row.guild_total), mine: Number(row.mine) };
}

export interface GuildObjectiveView {
  objectiveId: string;
  itemId: string;
  target: number;
  guildProgress: number;
  myContribution: number;
  minContribution: number;
  complete: boolean;
  eligible: boolean;
  claimed: boolean;
  rewardGold: string;
}

export class GuildObjectiveStore {
  constructor(private readonly db: Pool) {}

  async list(userId: string): Promise<{ weekStart: string | null; guildId: string | null; objectives: GuildObjectiveView[] }> {
    let weekStart: string | null = null;
    let guildId: string | null = null;
    const objectives: GuildObjectiveView[] = [];
    for (const objective of GUILD_OBJECTIVES) {
      const progress = await progressFor(this.db, userId, objective);
      if (!progress) continue;
      weekStart = progress.weekStart;
      guildId = progress.guildId;
      const claim = await this.db.query("SELECT 1 FROM guild_objective_claims WHERE user_id=$1 AND week_start=$2::date AND objective_id=$3", [userId, progress.weekStart, objective.id]);
      const complete = progress.guildTotal >= objective.target;
      objectives.push({
        objectiveId: objective.id,
        itemId: objective.itemId,
        target: objective.target,
        guildProgress: Math.min(progress.guildTotal, objective.target),
        myContribution: progress.mine,
        minContribution: objective.minContribution,
        complete,
        eligible: complete && progress.mine >= objective.minContribution,
        claimed: (claim.rowCount ?? 0) > 0,
        rewardGold: objective.rewardGold.toString(),
      });
    }
    return { weekStart, guildId, objectives };
  }

  async claim(userId: string, objectiveId: string): Promise<{ objectiveId: string; weekStart: string; transactionId: string; rewardGold: string; replayed: boolean }> {
    const objective = GUILD_OBJECTIVES.find((candidate) => candidate.id === objectiveId);
    if (!objective) throw new Error("GUILD_OBJECTIVE_NOT_FOUND");
    const client = await this.db.connect();
    try {
      await client.query("BEGIN");
      // Player row first (same lock order as every economy mutation), then the membership.
      const player = await client.query("SELECT 1 FROM player_profiles WHERE user_id=$1 FOR UPDATE", [userId]);
      if (!player.rows[0]) throw new Error("PLAYER_NOT_FOUND");
      const member = await client.query("SELECT 1 FROM guild_members WHERE user_id=$1 FOR SHARE", [userId]);
      if (!member.rows[0]) throw new Error("GUILD_MEMBERSHIP_REQUIRED");
      const progress = await progressFor(client, userId, objective);
      if (!progress) throw new Error("GUILD_MEMBERSHIP_REQUIRED");
      const prior = await client.query<{ transaction_id: string; reward_gold: string }>(
        "SELECT transaction_id, reward_gold FROM guild_objective_claims WHERE user_id=$1 AND week_start=$2::date AND objective_id=$3",
        [userId, progress.weekStart, objective.id],
      );
      if (prior.rows[0]) {
        // Replay: no economy write, so the audit trail records only the real payout.
        await client.query("COMMIT");
        return { objectiveId: objective.id, weekStart: progress.weekStart, transactionId: prior.rows[0].transaction_id, rewardGold: prior.rows[0].reward_gold, replayed: true };
      }
      if (progress.guildTotal < objective.target) throw new Error("GUILD_OBJECTIVE_INCOMPLETE");
      if (progress.mine < objective.minContribution) throw new Error("GUILD_CONTRIBUTION_REQUIRED");
      const result = await runEconomyMutation(client, userId, async (draft) => {
        const inserted = await client.query<{ transaction_id: string }>(
          "INSERT INTO guild_objective_claims(user_id, week_start, objective_id, guild_id, reward_gold) VALUES($1,$2::date,$3,$4,$5) RETURNING transaction_id",
          [userId, progress.weekStart, objective.id, progress.guildId, objective.rewardGold.toString()],
        );
        const transactionId = inserted.rows[0]?.transaction_id;
        if (!transactionId) throw new Error("GUILD_OBJECTIVE_TRANSACTION_MISSING");
        return {
          gold: addGoldDoubloons(draft.gold, objective.rewardGold),
          inventory: draft.inventory,
          value: { objectiveId: objective.id, weekStart: progress.weekStart, transactionId, rewardGold: objective.rewardGold.toString(), replayed: false },
        };
      }, "guild_objective_claim");
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
  GUILD_OBJECTIVE_NOT_FOUND: 404,
  PLAYER_NOT_FOUND: 404,
  GUILD_MEMBERSHIP_REQUIRED: 409,
  GUILD_OBJECTIVE_INCOMPLETE: 409,
  GUILD_CONTRIBUTION_REQUIRED: 409,
};

// `onEconomyChanged` lets the WebSocket layer push the refreshed player_state to an in-world
// player, so the HUD shows the reward at once instead of on the next move.
export function registerGuildObjectiveRoutes(app: FastifyInstance, db: Pool, players: PlayerStore, onEconomyChanged?: (userId: string) => void): void {
  const store = new GuildObjectiveStore(db);

  app.get("/guild-objectives", {
    schema: { tags: ["guilds"], security: [{ bearerAuth: [] }] },
    config: { rateLimit: { max: 60, timeWindow: "1 minute" } },
  }, async (request, reply) => {
    const userId = await verifyPlayer(request);
    if (!userId) return reply.code(401).send({ error: "UNAUTHORIZED" });
    return store.list(userId);
  });

  app.post<{ Body: { objectiveId: string } }>("/guild-objectives/claim", {
    schema: {
      tags: ["guilds"],
      security: [{ bearerAuth: [] }],
      body: { type: "object", additionalProperties: false, required: ["objectiveId"], properties: { objectiveId: { type: "string", minLength: 1, maxLength: 64, pattern: "^[a-z]+\\.[a-z]+$" } } },
    },
    config: { rateLimit: { max: 30, timeWindow: "1 minute" } },
  }, async (request, reply) => {
    const userId = await verifyPlayer(request);
    if (!userId) return reply.code(401).send({ error: "UNAUTHORIZED" });
    try {
      return await players.runExclusive(userId, async () => {
        await players.ensureProfile(userId);
        const result = await store.claim(userId, request.body.objectiveId);
        if (players.get(userId)) {
          await players.reloadEconomy(userId);
          onEconomyChanged?.(userId);
        }
        return result;
      });
    } catch (error) {
      const code = error instanceof Error ? error.message : "";
      if (code in ERRORS) return reply.code(ERRORS[code] ?? 400).send({ error: code });
      throw error;
    }
  });
}
