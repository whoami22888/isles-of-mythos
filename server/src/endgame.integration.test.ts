import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { buildApp } from "./app.js";
import { createDbPool } from "./db.js";
import { EndgameStore } from "./endgame.js";
import { PlayerStore } from "./player.js";

async function setup(){
  const db=createDbPool();const app=await buildApp({db});
  const createUser=async(prefix:string)=>{
    const id=randomUUID().replace(/-/g,"").slice(0,20);
    const r=await app.inject({method:"POST",url:"/auth/register",payload:{username:prefix+"_"+id,email:prefix+"_"+id+"@example.com",password:"Correct-Horse-Battery-9"}});
    expect(r.statusCode).toBe(201);
    const user=(JSON.parse(r.body) as {user:{id:string}}).user.id;
    await new PlayerStore(db).loadOrCreate(user);
    return user;
  };
  const a=await createUser("g16_a");const b=await createUser("g16_b");
  const ga=(await db.query<{id:string}>("INSERT INTO guilds(name,tag,leader_user_id,level) VALUES($1,$2,$3,5) RETURNING id",["G16A_"+Date.now(),"G6A"+String(Date.now()).slice(-3),a])).rows[0].id;
  const gb=(await db.query<{id:string}>("INSERT INTO guilds(name,tag,leader_user_id,level) VALUES($1,$2,$3,5) RETURNING id",["G16B_"+Date.now(),"G6B"+String(Date.now()).slice(-3),b])).rows[0].id;
  await db.query("INSERT INTO guild_members(guild_id,user_id,rank) VALUES($1,$2,'master'),($3,$4,'master')",[ga,a,gb,b]);
  const armyA=(await db.query<{id:string}>("INSERT INTO armies(owner_user_id,name,assignment,status) VALUES($1,'Gate16 A','realm_warfare','ready') RETURNING id",[a])).rows[0].id;
  const armyB=(await db.query<{id:string}>("INSERT INTO armies(owner_user_id,name,assignment,status) VALUES($1,'Gate16 B','realm_warfare','ready') RETURNING id",[b])).rows[0].id;
  await db.query("INSERT INTO army_units(army_id,unit_type,category,quantity,health,max_health,attack,defense,range,speed) VALUES($1,'royal_guard','infantry',10,1000,1000,50,40,5,3),($2,'royal_guard','infantry',12,1200,1200,55,45,5,3)",[armyA,armyB]);
  return {db,app,a,b,ga,gb,armyA,armyB};
}

describe("Gate 16 endgame integration",()=>{
  it("persists realm wars and derives contribution from locked army power",async()=>{
    const s=await setup();try{
      const realms=await s.db.query<{id:string}>("SELECT id FROM realms ORDER BY name LIMIT 2");
      const defenderTerritory=await s.db.query<{id:string;realm_owner_id:string}>("SELECT id,realm_owner_id FROM territories WHERE realm_owner_id=$1 LIMIT 1",[realms.rows[1].id]);
      const endgame=new EndgameStore(s.db);
      const war=await endgame.createRealmWar(s.a,realms.rows[0].id,realms.rows[1].id,defenderTerritory.rows[0].id);
      await endgame.joinRealmWar(s.b,war.id,s.gb,realms.rows[1].id);
      const updated=await endgame.realmWarAction(s.a,war.id,s.ga,s.armyA);
      expect(BigInt(updated.attackerScore)).toBeGreaterThan(0n);
      expect(updated.phase).toBe("assault");
      const row=await s.db.query<{contribution:string}>("SELECT contribution FROM realm_war_participants WHERE war_id=$1 AND guild_id=$2",[war.id,s.ga]);
      expect(BigInt(row.rows[0].contribution)).toBe(BigInt(updated.attackerScore));
    }finally{await s.app.close();await s.db.end();}
  });

  it("supports multi-army guild battles and resolves the winner server-side",async()=>{
    const s=await setup();try{
      const territory=await s.db.query<{id:string}>("SELECT id FROM territories ORDER BY name LIMIT 1");
      const endgame=new EndgameStore(s.db);
      const battle=await endgame.createGuildBattle(s.a,s.ga,s.gb,territory.rows[0].id);
      await endgame.joinGuildBattle(s.a,battle.id,s.armyA);
      await endgame.joinGuildBattle(s.b,battle.id,s.armyB);
      const afterA=await endgame.guildBattleAction(s.a,battle.id,s.armyA);
      const afterB=await endgame.guildBattleAction(s.b,battle.id,s.armyB);
      expect(BigInt(afterA.attackerScore)).toBeGreaterThan(0n);
      expect(BigInt(afterB.defenderScore)).toBeGreaterThan(0n);
      await s.db.query("UPDATE guild_battles SET ends_at=CURRENT_TIMESTAMP-INTERVAL '1 second' WHERE id=$1",[battle.id]);
      expect(await endgame.tick()).toBeGreaterThanOrEqual(1);
      const resolved=(await endgame.guildBattles()).find(x=>x.id===battle.id)!;
      expect(resolved.status).toBe("resolved");
      expect(resolved.winnerGuildId).toBe(s.gb);
    }finally{await s.app.close();await s.db.end();}
  });

  it("settles a high-level creature defeat atomically with authoritative rewards",async()=>{
    const s=await setup();try{
      await s.db.query("UPDATE player_profiles SET level=75 WHERE user_id=$1",[s.a]);
      const endgame=new EndgameStore(s.db);
      await endgame.spawnCreaturesIfNeeded();
      const creature=(await s.db.query<{id:string}>("SELECT id FROM endgame_creatures WHERE status='wild' ORDER BY id LIMIT 1")).rows[0];
      await s.db.query("UPDATE endgame_creatures SET health=1 WHERE id=$1",[creature.id]);
      const before=await s.db.query<{gold:string}>("SELECT gold FROM player_profiles WHERE user_id=$1",[s.a]);
      const result=await endgame.engageCreature(s.a,creature.id,75);
      expect(result.status).toBe("defeated");
      const after=await s.db.query<{gold:string;inventory:Record<string,number>}>("SELECT gold,inventory FROM player_profiles WHERE user_id=$1",[s.a]);
      const expectedGold=BigInt(before.rows[0].gold)+BigInt(result.level)*500n;
      expect(BigInt(after.rows[0].gold)).toBe(expectedGold);
      expect(after.rows[0].inventory["resource.pearl"]).toBe(Math.max(1,Math.floor(result.level/20)));
      await expect(endgame.engageCreature(s.a,creature.id,75)).rejects.toThrow("ENDGAME_CREATURE_DEFEATED");
    }finally{await s.app.close();await s.db.end();}
  });
});