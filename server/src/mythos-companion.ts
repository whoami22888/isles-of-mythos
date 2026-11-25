import type { FastifyInstance, FastifyRequest } from "fastify";
import type { Pool, PoolClient } from "pg";
import { isGameplayAccessToken } from "./auth.js";
import type { DamageType } from "./combat.js";
import { runEconomyMutation } from "./economy.js";
import type { PlayerStore } from "./player.js";

export const MYTHOS_ELEMENTS = ["water", "fire", "earth", "air"] as const;
export type MythosElement = typeof MYTHOS_ELEMENTS[number];
export const MYTHOS_STATES = ["wild", "tamed_follow", "tamed_work", "resting"] as const;
export type MythosState = typeof MYTHOS_STATES[number];
export const MYTHOS_CARE_ACTIONS = ["pet", "feed"] as const;
export type MythosCareAction = typeof MYTHOS_CARE_ACTIONS[number];

export const PET_MOOD_GAIN = 10;
export const FEED_MOOD_GAIN = 15;
export const EXCITED_MOOD_THRESHOLD = 80;
export const EXCITED_XP_MULTIPLIER = 2;
export const FIRE_FORGE_YIELD_MULTIPLIER = 1.6;
export const WATER_DOCKS_FARM_YIELD_MULTIPLIER = 1.4;
export const COMPANION_FEED_ITEM = "creature.feed";
export const WORK_XP_PER_MINUTE = 1;

const WATER_WORKSTATIONS = new Set(["docks", "fishing_dock", "farm"]);
const WATER_FOOD_TASKS = new Set(["collect", "irrigation", "fishing", "net_operation", "aquatic_harvesting"]);

export interface MythosCompanionSnapshot {
  id: string;
  state: MythosState;
  element: MythosElement;
  mood: number;
  xp_multiplier: number;
  work_output_max: boolean;
  workstation: string;
  work_task: string;
  work_yield_multiplier: number;
}

export interface MythosWorkContext {
  element?: string | null;
  workstation?: string | null;
  task?: string | null;
}

export function isMythosElement(value: string): value is MythosElement {
  return (MYTHOS_ELEMENTS as readonly string[]).includes(value);
}

export function toMythosElement(element: string): MythosElement | null {
  return isMythosElement(element) ? element : null;
}

export function clampMood(mood: number): number {
  if (!Number.isFinite(mood)) throw new Error("INVALID_COMPANION_MOOD");
  return Math.min(100, Math.max(0, mood));
}

export function isExcited(state: MythosState, mood: number): boolean {
  return state !== "wild" && clampMood(mood) >= EXCITED_MOOD_THRESHOLD;
}

export function xpMultiplierFor(state: MythosState, mood: number): number {
  return isExcited(state, mood) ? EXCITED_XP_MULTIPLIER : 1;
}

export function grantCompanionXp(baseXp: number, state: MythosState, mood: number): number {
  if (!Number.isSafeInteger(baseXp) || baseXp < 0) throw new Error("INVALID_COMPANION_XP");
  return Math.floor(baseXp * xpMultiplierFor(state, mood));
}

export function workYieldMultiplier(element: string | null | undefined, workstation: string | null | undefined, task: string | null | undefined): number {
  const nextElement = (element ?? "").trim().toLowerCase();
  const nextWorkstation = (workstation ?? "").trim().toLowerCase();
  const nextTask = (task ?? "").trim().toLowerCase();
  if (nextElement === "fire" && nextWorkstation === "forge" && nextTask === "ore_smelting") {
    return FIRE_FORGE_YIELD_MULTIPLIER;
  }
  if (nextElement === "water" && WATER_WORKSTATIONS.has(nextWorkstation) && WATER_FOOD_TASKS.has(nextTask)) {
    return WATER_DOCKS_FARM_YIELD_MULTIPLIER;
  }
  return 1;
}

export function companionStateFrom(input: {
  tameProgress: number;
  assigned: boolean;
  companionState?: string | null;
  aiMode?: string | null;
}): MythosState {
  if (input.tameProgress < 100) return "wild";
  if (input.assigned) return "tamed_work";
  if (input.companionState === "resting" || input.aiMode === "stay") return "resting";
  return "tamed_follow";
}

export function buildCompanionSnapshot(input: {
  id: string;
  element: string;
  mood: number;
  tameProgress: number;
  assigned: boolean;
  companionState?: string | null;
  aiMode?: string | null;
  workstation?: string | null;
  task?: string | null;
}): MythosCompanionSnapshot {
  const element = toMythosElement(input.element);
  if (!element) throw new Error("INVALID_MYTHOS_ELEMENT");
  const state = companionStateFrom(input);
  const mood = clampMood(input.mood);
  const excited = isExcited(state, mood);
  const workstation = state === "tamed_work" ? (input.workstation ?? "").trim().toLowerCase() : "";
  const workTask = state === "tamed_work" ? (input.task ?? "").trim().toLowerCase() : "";
  if (state === "tamed_work" && (!workstation || !workTask)) throw new Error("INVALID_COMPANION_WORK_ASSIGNMENT");
  return {
    id: input.id,
    state,
    element,
    mood,
    xp_multiplier: xpMultiplierFor(state, mood),
    work_output_max: excited,
    workstation,
    work_task: workTask,
    work_yield_multiplier: state === "tamed_work" ? workYieldMultiplier(element, workstation, workTask) : 1,
  };
}

interface CompanionRow {
  id: string;
  owner_user_id: string;
  element: DamageType;
  tame_progress: number;
  mood: string | number;
  companion_state: string;
  ai_mode: string | null;
  building_id: string | null;
  building_type: string | null;
  task: string | null;
}

function rowToSnapshot(row: CompanionRow): MythosCompanionSnapshot {
  return buildCompanionSnapshot({
    id: row.id,
    element: row.element,
    mood: Number(row.mood),
    tameProgress: row.tame_progress,
    assigned: Boolean(row.building_id),
    companionState: row.companion_state,
    aiMode: row.ai_mode,
    workstation: row.building_type,
    task: row.task,
  });
}

const COMPANION_SELECT = `SELECT pc.id, pc.owner_user_id, pc.element, pc.tame_progress, pc.mood, pc.companion_state, pc.ai_mode,
  bw.building_id, bb.type AS building_type, bw.task
  FROM player_creatures pc
  LEFT JOIN base_workers bw ON bw.creature_id = pc.id
  LEFT JOIN base_buildings bb ON bb.id = bw.building_id`;

export class MythosCompanionStore {
  constructor(private readonly db: Pool) {}

  async snapshot(userId: string, creatureId: string): Promise<MythosCompanionSnapshot> {
    const result = await this.db.query<CompanionRow>(`${COMPANION_SELECT} WHERE pc.id=$1`, [creatureId]);
    const row = result.rows[0];
    if (!row || row.owner_user_id !== userId) throw new Error("CREATURE_NOT_FOUND");
    return rowToSnapshot(row);
  }

  async care(userId: string, creatureId: string, action: MythosCareAction): Promise<MythosCompanionSnapshot> {
    if (action !== "pet" && action !== "feed") throw new Error("INVALID_COMPANION_CARE");
    const client = await this.db.connect();
    try {
      await client.query("BEGIN");
      const result = await client.query<CompanionRow>(
        `${COMPANION_SELECT} WHERE pc.id=$1 FOR UPDATE OF pc`,
        [creatureId],
      );
      const row = result.rows[0];
      if (!row || row.owner_user_id !== userId) throw new Error("CREATURE_NOT_FOUND");
      const current = rowToSnapshot(row);
      if (current.state === "wild") throw new Error("CREATURE_NOT_TAMED");
      const gain = action === "pet" ? PET_MOOD_GAIN : FEED_MOOD_GAIN;
      if (action === "feed") {
        await runEconomyMutation(client, userId, (draft) => {
          const feed = Number(draft.inventory[COMPANION_FEED_ITEM] ?? 0);
          if (!Number.isSafeInteger(feed) || feed < 1) throw new Error("NO_CREATURE_FEED");
          return {
            gold: draft.gold,
            inventory: { ...draft.inventory, [COMPANION_FEED_ITEM]: feed - 1 },
            value: undefined,
          };
        }, "mythos_companion_feed");
      }
      const nextMood = clampMood(Number(row.mood) + gain);
      await client.query(
        "UPDATE player_creatures SET mood=$2, updated_at=CURRENT_TIMESTAMP WHERE id=$1 AND owner_user_id=$3",
        [creatureId, nextMood, userId],
      );
      await client.query("COMMIT");
      return buildCompanionSnapshot({
        id: row.id,
        element: row.element,
        mood: nextMood,
        tameProgress: row.tame_progress,
        assigned: Boolean(row.building_id),
        companionState: row.companion_state,
        aiMode: row.ai_mode,
        workstation: row.building_type,
        task: row.task,
      });
    } catch (error) {
      await client.query("ROLLBACK").catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  async grantWorkXp(client: PoolClient, creatureId: string, elapsedMs: number): Promise<number> {
    if (!Number.isFinite(elapsedMs) || elapsedMs <= 0) return 0;
    const result = await client.query<{ id: string; owner_user_id: string; xp: string; mood: string; tame_progress: number; companion_state: string; ai_mode: string | null; building_id: string | null }>(
      "SELECT pc.id, pc.owner_user_id, pc.xp, pc.mood, pc.tame_progress, pc.companion_state, pc.ai_mode, bw.building_id FROM player_creatures pc LEFT JOIN base_workers bw ON bw.creature_id=pc.id WHERE pc.id=$1 FOR UPDATE OF pc",
      [creatureId],
    );
    const row = result.rows[0];
    if (!row) return 0;
    const state = companionStateFrom({
      tameProgress: row.tame_progress,
      assigned: Boolean(row.building_id),
      companionState: row.companion_state,
      aiMode: row.ai_mode,
    });
    const baseXp = Math.floor((elapsedMs / 60000) * WORK_XP_PER_MINUTE);
    const xp = grantCompanionXp(baseXp, state, Number(row.mood));
    if (xp <= 0) return 0;
    await client.query(
      "UPDATE player_creatures SET xp=xp+$2, updated_at=CURRENT_TIMESTAMP WHERE id=$1",
      [creatureId, xp],
    );
    return xp;
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
  if (code === "CREATURE_NOT_FOUND" || code === "PLAYER_NOT_FOUND") return 404;
  if (
    code === "CREATURE_NOT_TAMED"
    || code === "NO_CREATURE_FEED"
    || code === "INVALID_COMPANION_CARE"
    || code === "INVALID_MYTHOS_ELEMENT"
    || code === "INVALID_COMPANION_WORK_ASSIGNMENT"
  ) return 409;
  return 500;
}

export function registerMythosCompanionRoutes(app: FastifyInstance, db: Pool, players: PlayerStore, onEconomyChanged?: (userId: string) => void): MythosCompanionStore {
  const store = new MythosCompanionStore(db);

  app.get<{ Params: { creatureId: string } }>("/creatures/:creatureId/companion", {
    schema: { tags: ["creatures"], security: [{ bearerAuth: [] }] },
    config: { rateLimit: { max: 60, timeWindow: "1 minute" } },
  }, async (request, reply) => {
    const userId = await verifyPlayer(request);
    if (!userId) return reply.code(401).send({ error: "UNAUTHORIZED" });
    try {
      await players.ensureProfile(userId);
      return await store.snapshot(userId, request.params.creatureId);
    } catch (error) {
      const code = error instanceof Error ? error.message : "";
      const status = httpStatusFor(code);
      if (status < 500) return reply.code(status).send({ error: code });
      throw error;
    }
  });

  app.post<{ Params: { creatureId: string }; Body: { action?: string } }>("/creatures/:creatureId/care", {
    schema: {
      tags: ["creatures"],
      security: [{ bearerAuth: [] }],
      body: {
        type: "object",
        additionalProperties: false,
        required: ["action"],
        properties: { action: { type: "string", enum: ["pet", "feed"] } },
      },
    },
    config: { rateLimit: { max: 30, timeWindow: "1 minute" } },
  }, async (request, reply) => {
    const userId = await verifyPlayer(request);
    if (!userId) return reply.code(401).send({ error: "UNAUTHORIZED" });
    try {
      return await players.runExclusive(userId, async () => {
        await players.ensureProfile(userId);
        const result = await store.care(userId, request.params.creatureId, request.body.action as MythosCareAction);
        if (request.body.action === "feed" && players.get(userId)) {
          await players.reloadEconomy(userId);
          onEconomyChanged?.(userId);
        }
        return result;
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
