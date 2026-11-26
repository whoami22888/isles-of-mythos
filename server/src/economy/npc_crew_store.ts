import type { FastifyInstance } from "fastify";
import type { Pool } from "pg";
import { verifyGameplayRequest } from "../auth.js";
import { parseGoldDoubloons, subtractGoldDoubloons } from "../economy.js";
import type { PlayerStore } from "../player.js";

export const NPC_CREW_FORBIDDEN = "NPC_CREW_FORBIDDEN";
export const CITADEL_LEVEL_REQUIRED = "CITADEL_LEVEL_REQUIRED";
export const INSUFFICIENT_FUNDS = "INSUFFICIENT_FUNDS";

export type PurchasableNpcCrew = "pirate_sailor" | "specialist_officer";
export type ForbiddenNpcCrew = "dragon_officer" | "mermaid_navigator";

export interface NpcHireTier {
  id: PurchasableNpcCrew;
  name: string;
  hireCost: bigint;
  dailyUpkeep: bigint;
  minCitadelLevel: number;
}

export const NPC_HIRE_TIERS: Readonly<Record<PurchasableNpcCrew, NpcHireTier>> = {
  pirate_sailor: {
    id: "pirate_sailor",
    name: "Pirate Sailor",
    hireCost: 5_000n,
    dailyUpkeep: 50n,
    minCitadelLevel: 1,
  },
  specialist_officer: {
    id: "specialist_officer",
    name: "Specialist Officer",
    hireCost: 25_000n,
    dailyUpkeep: 500n,
    minCitadelLevel: 8,
  },
};

const ALIASES: Readonly<Record<string, string>> = {
  pirate_sailor: "pirate_sailor",
  pirate: "pirate_sailor",
  "pirate sailor": "pirate_sailor",
  specialist_officer: "specialist_officer",
  npc_specialist: "specialist_officer",
  "specialist officer": "specialist_officer",
  dragon_officer: "dragon_officer",
  dragon: "dragon_officer",
  "dragon officer": "dragon_officer",
  mermaid_navigator: "mermaid_navigator",
  mermaid: "mermaid_navigator",
  "mermaid navigator": "mermaid_navigator",
};

const FORBIDDEN = new Set<string>(["dragon_officer", "mermaid_navigator"]);

export function normalizeNpcShopCrewType(raw: string): string {
  return ALIASES[raw.trim().toLowerCase()] ?? raw.trim().toLowerCase();
}

/** Fail-closed: dragons and mermaids cannot be bought; they must be earned. */
export function resolveNpcShopHire(crewType: string): NpcHireTier {
  const id = normalizeNpcShopCrewType(crewType);
  if (FORBIDDEN.has(id) || id === "dragon" || id === "mermaid") {
    throw new Error(NPC_CREW_FORBIDDEN);
  }
  const tier = NPC_HIRE_TIERS[id as PurchasableNpcCrew];
  if (!tier) throw new Error("NPC_CREW_UNKNOWN");
  return tier;
}

export interface NpcHireReceipt {
  contractId: string;
  crewType: PurchasableNpcCrew;
  hireCost: string;
  dailyUpkeep: string;
  balance: string;
}

export class NpcCrewStore {
  constructor(private readonly db: Pool) {}

  async hire(userId: string, crewType: string): Promise<NpcHireReceipt> {
    const tier = resolveNpcShopHire(crewType);
    const client = await this.db.connect();
    try {
      await client.query("BEGIN");
      const profile = await client.query<{ gold: string }>(
        "SELECT gold FROM player_profiles WHERE user_id = $1 FOR UPDATE",
        [userId],
      );
      if (!profile.rows[0]) throw new Error("PLAYER_NOT_FOUND");
      const citadel = await client.query<{ citadel_level: number }>(
        "SELECT citadel_level FROM player_citadels WHERE owner_user_id = $1",
        [userId],
      );
      const citadelLevel = citadel.rows[0]?.citadel_level ?? 1;
      if (citadelLevel < tier.minCitadelLevel) throw new Error(CITADEL_LEVEL_REQUIRED);

      const gold = parseGoldDoubloons(profile.rows[0].gold);
      if (gold < tier.hireCost) throw new Error(INSUFFICIENT_FUNDS);
      const nextGold = subtractGoldDoubloons(gold, tier.hireCost);
      await client.query(
        "UPDATE player_profiles SET gold=$2, updated_at=CURRENT_TIMESTAMP WHERE user_id=$1",
        [userId, nextGold.toString()],
      );
      const inserted = await client.query<{ id: string }>(
        `INSERT INTO npc_crew_contracts (user_id, crew_type, hire_cost, daily_upkeep)
         VALUES ($1, $2, $3, $4)
         RETURNING id`,
        [userId, tier.id, tier.hireCost.toString(), tier.dailyUpkeep.toString()],
      );
      await client.query("COMMIT");
      return {
        contractId: inserted.rows[0].id,
        crewType: tier.id,
        hireCost: tier.hireCost.toString(),
        dailyUpkeep: tier.dailyUpkeep.toString(),
        balance: nextGold.toString(),
      };
    } catch (error) {
      await client.query("ROLLBACK").catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }
}

export function registerNpcCrewRoutes(app: FastifyInstance, db: Pool, players: PlayerStore): NpcCrewStore {
  const store = new NpcCrewStore(db);

  app.post<{ Body: { crewType: string } }>(
    "/api/v1/economy/npc-crew/hire",
    {
      schema: {
        tags: ["shop"],
        security: [{ bearerAuth: [] }],
        body: {
          type: "object",
          required: ["crewType"],
          additionalProperties: false,
          properties: {
            crewType: { type: "string", minLength: 1, maxLength: 64 },
          },
        },
      },
    },
    async (request, reply) => {
      if (!(await verifyGameplayRequest(request))) {
        return reply.code(401).send({ error: "UNAUTHORIZED", message: "Invalid credentials" });
      }
      const userId = request.user.sub;
      try {
        await players.loadOrCreate(userId);
        const receipt = await store.hire(userId, request.body.crewType);
        if (players.get(userId)) await players.reloadEconomy(userId);
        return receipt;
      } catch (error) {
        const code = error instanceof Error ? error.message : "";
        if (code === NPC_CREW_FORBIDDEN) {
          return reply.code(403).send({ error: NPC_CREW_FORBIDDEN, message: "Forbidden" });
        }
        if (code === CITADEL_LEVEL_REQUIRED) {
          return reply.code(403).send({ error: CITADEL_LEVEL_REQUIRED, message: "Citadel Level 8 required" });
        }
        if (code === INSUFFICIENT_FUNDS || code === "INSUFFICIENT_GOLD") {
          return reply.code(400).send({ error: INSUFFICIENT_FUNDS, message: "Insufficient Funds" });
        }
        if (code === "NPC_CREW_UNKNOWN") {
          return reply.code(400).send({ error: code });
        }
        if (code === "PLAYER_NOT_FOUND") {
          return reply.code(404).send({ error: code });
        }
        return reply.code(500).send({ error: "NPC_CREW_HIRE_FAILED" });
      }
    },
  );

  return store;
}
