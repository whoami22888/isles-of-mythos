import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { buildApp } from "../app.js";
import { createDbPool } from "../db.js";
import { PlayerStore } from "../player.js";
import {
  NPC_CREW_FORBIDDEN,
  NPC_HIRE_TIERS,
  normalizeNpcShopCrewType,
  resolveNpcShopHire,
} from "./npc_crew_store.js";

describe("NPC crew shop entitlements", () => {
  it("publishes pirate and specialist hire costs and daily upkeep", () => {
    expect(NPC_HIRE_TIERS.pirate_sailor).toMatchObject({ hireCost: 5_000n, dailyUpkeep: 50n, minCitadelLevel: 1 });
    expect(NPC_HIRE_TIERS.specialist_officer).toMatchObject({
      hireCost: 25_000n,
      dailyUpkeep: 500n,
      minCitadelLevel: 8,
    });
  });

  it("fail-closes Dragon Officer and Mermaid Navigator shop purchases", () => {
    for (const name of ["dragon_officer", "Dragon Officer", "dragon", "mermaid_navigator", "Mermaid Navigator", "mermaid"]) {
      expect(normalizeNpcShopCrewType(name) === "dragon_officer" || normalizeNpcShopCrewType(name) === "mermaid_navigator").toBe(true);
      expect(() => resolveNpcShopHire(name)).toThrow(NPC_CREW_FORBIDDEN);
    }
  });
});

async function createCrewShopPlayer() {
  const db = createDbPool();
  const app = await buildApp({ db });
  const unique = randomUUID().replace(/-/g, "").slice(0, 24);
  const response = await app.inject({
    method: "POST",
    url: "/auth/register",
    payload: {
      username: `crew_${unique}`,
      email: `crew_${unique}@example.com`,
      password: "Correct-Horse-Battery-9",
    },
  });
  expect(response.statusCode).toBe(201);
  const body = JSON.parse(response.body) as { user: { id: string }; accessToken: string };
  await new PlayerStore(db).loadOrCreate(body.user.id);
  return { db, app, userId: body.user.id, token: body.accessToken };
}

describe("POST /api/v1/economy/npc-crew/hire", () => {
  it("returns HTTP 403 Forbidden when buying a Dragon Officer from the NPC shop", async () => {
    const { db, app, token } = await createCrewShopPlayer();
    try {
      const response = await app.inject({
        method: "POST",
        url: "/api/v1/economy/npc-crew/hire",
        headers: { authorization: `Bearer ${token}` },
        payload: { crewType: "Dragon Officer" },
      });
      expect(response.statusCode).toBe(403);
      expect(JSON.parse(response.body)).toEqual({ error: NPC_CREW_FORBIDDEN, message: "Forbidden" });
    } finally {
      await app.close();
      await db.end();
    }
  });

  it("hires a Pirate Sailor and records the published 50 gold/day upkeep", async () => {
    const { db, app, userId, token } = await createCrewShopPlayer();
    try {
      await db.query("UPDATE player_profiles SET gold=$2 WHERE user_id=$1", [userId, "5000"]);
      const response = await app.inject({
        method: "POST",
        url: "/api/v1/economy/npc-crew/hire",
        headers: { authorization: `Bearer ${token}` },
        payload: { crewType: "pirate_sailor" },
      });
      expect(response.statusCode).toBe(200);
      const body = JSON.parse(response.body) as { dailyUpkeep: string; hireCost: string; balance: string };
      expect(body).toMatchObject({ hireCost: "5000", dailyUpkeep: "50", balance: "0" });
    } finally {
      await app.close();
      await db.end();
    }
  });

  it("rejects a Specialist Officer hire below Citadel level 8", async () => {
    const { db, app, userId, token } = await createCrewShopPlayer();
    try {
      await db.query("UPDATE player_profiles SET gold=$2 WHERE user_id=$1", [userId, "25000"]);
      const response = await app.inject({
        method: "POST",
        url: "/api/v1/economy/npc-crew/hire",
        headers: { authorization: `Bearer ${token}` },
        payload: { crewType: "specialist_officer" },
      });
      expect(response.statusCode).toBe(403);
      expect(JSON.parse(response.body).error).toBe("CITADEL_LEVEL_REQUIRED");
    } finally {
      await app.close();
      await db.end();
    }
  });
});
