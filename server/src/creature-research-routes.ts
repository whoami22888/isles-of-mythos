import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import type { PlayerStore } from "./player.js";
import { CREATURE_SKILLS, canResearchSkill, rankForExperience, type BuildingProgress, type SkillId } from "./creature-mastery.js";
import { CreatureResearchStore, RESEARCH_MATERIALS } from "./creature-research-store.js";

interface UnlockBody { requestId: string; skillId: SkillId; }
interface SkillRow { skill_id: string; experience: number; }
interface TrainingRow {
  id: string;
  species: string;
  nickname: string | null;
  level: number;
  tame_progress: number;
  training_experience: number;
  bond: number;
  learned_commands: unknown[];
  training_unlocked: boolean;
}

const unlockConflicts = new Set([
  "SKILL_PREREQUISITE_MISSING", "RESEARCH_FACILITY_MISSING",
  "SKILL_ALREADY_UNLOCKED", "INSUFFICIENT_INVENTORY", "PROGRESSION_REQUEST_CONFLICT",
]);
const unlockBadRequests = new Set(["UNKNOWN_SKILL", "INVALID_PROGRESSION_REQUEST_ID"]);

/**
 * Player-facing read/unlock boundary. Never exposes practice-XP award endpoints:
 * experience originates only from authoritative server-side verified events.
 */
export function registerCreatureResearchRoutes(app: FastifyInstance, db: Pool, players: PlayerStore): void {
  const store = new CreatureResearchStore(db);
  const skillIds = Object.keys(CREATURE_SKILLS) as SkillId[];

  app.get("/creature-research", {
    schema: { tags: ["creatures"], security: [{ bearerAuth: [] }] },
    config: { rateLimit: { max: 60, timeWindow: "1 minute" } },
  }, async (request, reply) => {
    try { await request.jwtVerify(); }
    catch { return reply.code(401).send({ error: "UNAUTHORIZED" }); }
    const userId = request.user.sub;
    await players.ensureProfile(userId);
    const [rows, buildings] = await Promise.all([
      db.query<SkillRow>("SELECT skill_id,experience FROM player_creature_skills WHERE user_id=$1", [userId]),
      db.query<BuildingProgress>(
        "SELECT b.type,b.level,b.active FROM base_buildings b JOIN player_bases p ON p.id=b.base_id WHERE p.owner_user_id=$1",
        [userId],
      ),
    ]);
    const unlocked = new Map(rows.rows.map(row => [row.skill_id, row.experience]));
    const playerSkills: Record<string,{ unlocked: true; experience: number }> = {};
    for (const row of rows.rows) playerSkills[row.skill_id] = { unlocked: true, experience: row.experience };
    return {
      skills: skillIds.map(skillId => {
        const definition = CREATURE_SKILLS[skillId];
        const experience = unlocked.get(skillId) ?? null;
        const isUnlocked = experience !== null;
        const denial = isUnlocked ? null : canResearchSkill(skillId, playerSkills, buildings.rows);
        return {
          skillId,
          unlocked: isUnlocked,
          experience,
          rank: experience === null ? null : rankForExperience(experience),
          researchRequirementsMet: !isUnlocked && denial === null,
          denial,
          prerequisites: definition.prerequisites,
          facilities: definition.facilities,
          cost: RESEARCH_MATERIALS[skillId],
        };
      }),
    };
  });

  app.get("/creature-training", {
    schema: { tags: ["creatures"], security: [{ bearerAuth: [] }] },
    config: { rateLimit: { max: 60, timeWindow: "1 minute" } },
  }, async (request, reply) => {
    try { await request.jwtVerify(); }
    catch { return reply.code(401).send({ error: "UNAUTHORIZED" }); }
    const userId = request.user.sub;
    const { rows } = await db.query<TrainingRow>(
      `SELECT c.id,c.species,c.nickname,c.level,c.tame_progress,
              COALESCE(t.experience,0)::int AS training_experience,
              COALESCE(t.bond,0)::int AS bond,
              COALESCE(t.learned_commands,'[]'::jsonb) AS learned_commands,
              (s.user_id IS NOT NULL) AS training_unlocked
         FROM player_creatures c
         LEFT JOIN creature_training_progress t ON t.creature_id=c.id
         LEFT JOIN player_creature_skills s
           ON s.user_id=c.owner_user_id AND s.skill_id='creature_training'
        WHERE c.owner_user_id=$1
        ORDER BY c.created_at,c.id`,
      [userId],
    );
    return {
      creatures: rows.map(row => ({
        id: row.id,
        species: row.species,
        nickname: row.nickname,
        level: row.level,
        tameProgress: row.tame_progress,
        trainingExperience: row.training_experience,
        bond: row.bond,
        learnedCommands: row.learned_commands,
        trainingUnlocked: row.training_unlocked,
        trainable: row.training_unlocked && row.tame_progress >= 100,
      })),
    };
  });

  app.post<{ Body: UnlockBody }>("/creature-research/unlock", {
    schema: {
      tags: ["creatures"],
      security: [{ bearerAuth: [] }],
      body: {
        type: "object", additionalProperties: false, required: ["requestId", "skillId"],
        properties: {
          requestId: { type: "string", minLength: 1, maxLength: 64, pattern: "^[A-Za-z0-9._:-]+$" },
          skillId: { type: "string", enum: skillIds },
        },
      },
    },
    config: { rateLimit: { max: 10, timeWindow: "1 minute" } },
    // Fastify may strip additionalProperties during schema validation. Reject
    // unexpected keys before the validator can silently discard them.
    preValidation: async (request, reply) => {
      if (Object.keys(request.body ?? {}).some(key => key !== "requestId" && key !== "skillId")) {
        return reply.code(400).send({ error: "INVALID_RESEARCH_BODY" });
      }
    },
  }, async (request, reply) => {
    try { await request.jwtVerify(); }
    catch { return reply.code(401).send({ error: "UNAUTHORIZED" }); }
    try {
      const userId = request.user.sub;
      return await players.runExclusive(userId, async () => {
        // Direct HTTP unlocks must initialize persistence without activating
        // the player in the simulation.
        await players.ensureProfile(userId);
        const result = await store.unlock(userId, request.body.requestId, request.body.skillId);
        // HTTP-only requests must not enter the simulation. Refresh only a
        // player that is already active through an authenticated WebSocket.
        if (players.get(userId)) await players.reloadEconomy(userId);
        return result;
      });
    } catch (error) {
      const code = error instanceof Error ? error.message : "";
      if (unlockConflicts.has(code)) return reply.code(409).send({ error: code });
      if (unlockBadRequests.has(code)) return reply.code(400).send({ error: code });
      if (code === "PLAYER_NOT_FOUND") return reply.code(404).send({ error: code });
      throw error; // Unknown database failures belong to the central error handler.
    }
  });
}
