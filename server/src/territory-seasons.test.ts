import { describe, expect, it } from "vitest";
import { createDbPool } from "./db.js";
import { TerritorySeasonStore } from "./territory-seasons.js";

describe("Gate 16 territory seasons", () => {
  it("persists authoritative scoring and standings for realm territory control", async () => {
    const db = createDbPool();
    const seasonNumber = 160000 + Math.floor(Date.now() % 10000);
    const temporaryTerritories: string[] = [];
    try {
      const realms = await db.query<{ id: string }>(
        "SELECT id FROM realms ORDER BY name LIMIT 2",
      );
      expect(realms.rows).toHaveLength(2);

      const season = await db.query<{ id: string }>(
        "INSERT INTO territory_seasons(season_number,name,ends_at,state) VALUES($1,$2,CURRENT_TIMESTAMP+INTERVAL '1 hour',$3::jsonb) RETURNING id",
        [seasonNumber, "Gate 16 Verification", JSON.stringify({ version: 1 })],
      );

      const territories = await db.query<{ id: string }>(
        "INSERT INTO territories(name,min_x,max_x,min_y,max_y,realm_owner_id) VALUES($1,-900,-899,-900,-899,$2),($3,-898,-897,-900,-899,$4),($5,-896,-895,-900,-899,$6) RETURNING id",
        [
          "G16 Verification A",
          realms.rows[0].id,
          "G16 Verification B",
          realms.rows[0].id,
          "G16 Verification C",
          realms.rows[1].id,
        ],
      );
      temporaryTerritories.push(...territories.rows.map((x) => x.id));

      const seasons = new TerritorySeasonStore(db);
      expect((await seasons.active())?.id).toBe(season.rows[0].id);
      expect(await seasons.tick()).toBe(true);

      const standings = await seasons.standings(season.rows[0].id);
      const realmA = standings.find(
        (x) => x.actorType === "realm" && x.actorId === realms.rows[0].id,
      );
      const realmB = standings.find(
        (x) => x.actorType === "realm" && x.actorId === realms.rows[1].id,
      );

      expect(realmA?.territoriesControlled).toBeGreaterThanOrEqual(2);
      expect(realmA?.points).toBe(realmA?.territoriesControlled.toString());
      expect(realmB?.territoriesControlled).toBeGreaterThanOrEqual(1);
      expect(realmB?.points).toBe(realmB?.territoriesControlled.toString());

      const persisted = await db.query<{
        points: string;
        territories_controlled: number;
      }>(
        "SELECT points,territories_controlled FROM territory_season_standings WHERE season_id=$1 AND actor_type='realm' AND actor_id=$2",
        [season.rows[0].id, realms.rows[0].id],
      );
      expect(persisted.rows).toEqual([
        {
          points: realmA?.points,
          territories_controlled: realmA?.territoriesControlled,
        },
      ]);
    } finally {
      if (temporaryTerritories.length) {
        await db.query(
          "DELETE FROM territories WHERE id = ANY($1::uuid[])",
          [temporaryTerritories],
        );
      }
      await db.query(
        "DELETE FROM territory_seasons WHERE season_number=$1",
        [seasonNumber],
      );
      await db.end();
    }
  });

  it("resolves an expired season and chooses the deterministic standings winner", async () => {
    const db = createDbPool();
    const seasonNumber = 170000 + Math.floor(Date.now() % 10000);
    try {
      const realms = await db.query<{ id: string }>(
        "SELECT id FROM realms ORDER BY name LIMIT 2",
      );
      expect(realms.rows).toHaveLength(2);

      const season = await db.query<{ id: string }>(
        "INSERT INTO territory_seasons(season_number,name,ends_at,state) VALUES($1,$2,CURRENT_TIMESTAMP-INTERVAL '1 second',$3::jsonb) RETURNING id",
        [seasonNumber, "Gate 16 Expiry Verification", JSON.stringify({ version: 1 })],
      );

      const standings = await db.query(
        "INSERT INTO territory_season_standings(season_id,actor_type,actor_id,points,territories_controlled,wins) VALUES($1,'realm',$2,100,2,4),($1,'realm',$3,99,1,9)",
        [season.rows[0].id, realms.rows[0].id, realms.rows[1].id],
      );
      expect(standings.rowCount).toBe(2);

      const seasons = new TerritorySeasonStore(db);
      expect(await seasons.tick()).toBe(true);

      const resolved = await db.query<{
        status: string;
        winner_type: string | null;
        winner_id: string | null;
        resolved_at: Date | null;
        state: Record<string, unknown>;
      }>(
        "SELECT status,winner_type,winner_id,resolved_at,state FROM territory_seasons WHERE id=$1",
        [season.rows[0].id],
      );

      expect(resolved.rows[0]).toMatchObject({
        status: "resolved",
        winner_type: "realm",
        winner_id: realms.rows[0].id,
        state: { version: 1, resolved: true },
      });
      expect(resolved.rows[0].resolved_at).not.toBeNull();
    } finally {
      await db.query(
        "DELETE FROM territory_seasons WHERE season_number=$1",
        [seasonNumber],
      );
      await db.end();
    }
  });

  it("uses stable actor ordering when points and territory control are tied", async () => {
    const db = createDbPool();
    const seasonNumber = 180000 + Math.floor(Date.now() % 10000);
    try {
      const realms = await db.query<{ id: string }>(
        "SELECT id FROM realms ORDER BY name LIMIT 2",
      );
      expect(realms.rows).toHaveLength(2);

      const season = await db.query<{ id: string }>(
        "INSERT INTO territory_seasons(season_number,name,ends_at,state) VALUES($1,$2,CURRENT_TIMESTAMP-INTERVAL '1 second',$3::jsonb) RETURNING id",
        [seasonNumber, "Gate 16 Tie Verification", JSON.stringify({ version: 1 })],
      );
      await db.query(
        "INSERT INTO territory_season_standings(season_id,actor_type,actor_id,points,territories_controlled,wins) VALUES($1,'realm',$2,200,3,1),($1,'realm',$3,200,3,99)",
        [season.rows[0].id, realms.rows[0].id, realms.rows[1].id],
      );

      const seasons = new TerritorySeasonStore(db);
      await seasons.tick();

      const row = await db.query<{ winner_id: string | null }>(
        "SELECT winner_id FROM territory_seasons WHERE id=$1",
        [season.rows[0].id],
      );
      expect(row.rows[0].winner_id).toBe(
        [realms.rows[0].id, realms.rows[1].id].sort()[0],
      );
    } finally {
      await db.query(
        "DELETE FROM territory_seasons WHERE season_number=$1",
        [seasonNumber],
      );
      await db.end();
    }
  });
});
