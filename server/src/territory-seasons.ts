import type { Pool } from "pg";

export const SEASON_INTERVAL_SECONDS=60;
interface SeasonRow{id:string;season_number:number;name:string;status:"active"|"resolved";starts_at:Date;ends_at:Date;resolved_at:Date|null;winner_type:"realm"|"guild"|null;winner_id:string|null;}
interface StandingRow{season_id:string;actor_type:"realm"|"guild";actor_id:string;points:string;territories_controlled:number;wins:number;}
export interface TerritorySeasonSummary{id:string;seasonNumber:number;name:string;status:"active"|"resolved";startsAt:string;endsAt:string;resolvedAt:string|null;winnerType:"realm"|"guild"|null;winnerId:string|null;}
export interface TerritorySeasonStanding{actorType:"realm"|"guild";actorId:string;points:string;territoriesControlled:number;wins:number;}

function mapSeason(x:SeasonRow):TerritorySeasonSummary{return{id:x.id,seasonNumber:x.season_number,name:x.name,status:x.status,startsAt:x.starts_at.toISOString(),endsAt:x.ends_at.toISOString(),resolvedAt:x.resolved_at?.toISOString()??null,winnerType:x.winner_type,winnerId:x.winner_id};}
export class TerritorySeasonStore{
  constructor(private readonly db:Pool){}
  async active():Promise<TerritorySeasonSummary|null>{const r=await this.db.query<SeasonRow>("SELECT id,season_number,name,status,starts_at,ends_at,resolved_at,winner_type,winner_id FROM territory_seasons WHERE status='active' ORDER BY season_number DESC LIMIT 1");return r.rows[0]?mapSeason(r.rows[0]):null;}
  async standings(seasonId?:string):Promise<TerritorySeasonStanding[]>{
    const season=seasonId??(await this.active())?.id;if(!season)return[];
    const r=await this.db.query<StandingRow>("SELECT actor_type,actor_id,points,territories_controlled,wins FROM territory_season_standings WHERE season_id=$1 ORDER BY points DESC,actor_type,actor_id",[season]);
    return r.rows.map(x=>({actorType:x.actor_type,actorId:x.actor_id,points:String(x.points),territoriesControlled:x.territories_controlled,wins:x.wins}));
  }
  async tick():Promise<boolean>{
    const c=await this.db.connect();try{await c.query("BEGIN");await c.query("SELECT pg_advisory_xact_lock(17017)");
      const season=await c.query<SeasonRow>("SELECT id,season_number,name,status,starts_at,ends_at,resolved_at,winner_type,winner_id FROM territory_seasons WHERE status='active' ORDER BY season_number DESC LIMIT 1 FOR UPDATE");
      if(!season.rows[0]){await c.query("COMMIT");return false;}
      const s=season.rows[0];
      const counts=await c.query<{actor_type:"realm"|"guild";actor_id:string;territories_controlled:string}>(
        "SELECT actor_type,actor_id,COUNT(*)::text territories_controlled FROM (SELECT 'guild'::varchar actor_type,guild_owner_id actor_id FROM territories WHERE guild_owner_id IS NOT NULL UNION ALL SELECT 'realm'::varchar,realm_owner_id FROM territories WHERE realm_owner_id IS NOT NULL) owners GROUP BY actor_type,actor_id");
      for(const row of counts.rows){
        await c.query("INSERT INTO territory_season_standings(season_id,actor_type,actor_id,points,territories_controlled) VALUES($1,$2,$3,$4,$5) ON CONFLICT(season_id,actor_type,actor_id) DO UPDATE SET points=territory_season_standings.points+$4,territories_controlled=EXCLUDED.territories_controlled,updated_at=CURRENT_TIMESTAMP",[s.id,row.actor_type,row.actor_id,row.territories_controlled,row.territories_controlled]);
      }
      if(new Date(s.ends_at)<=new Date()){
        const winner=await c.query<{actor_type:"realm"|"guild";actor_id:string}>("SELECT actor_type,actor_id FROM territory_season_standings WHERE season_id=$1 ORDER BY points DESC,territories_controlled DESC,actor_type,actor_id LIMIT 1",[s.id]);
        await c.query("UPDATE territory_seasons SET status='resolved',resolved_at=CURRENT_TIMESTAMP,winner_type=$2,winner_id=$3,state=jsonb_set(state,'{resolved}',to_jsonb(true)),updated_at=CURRENT_TIMESTAMP WHERE id=$1",[s.id,winner.rows[0]?.actor_type??null,winner.rows[0]?.actor_id??null]);
      }
      await c.query("COMMIT");return true;
    }catch(e){await c.query("ROLLBACK");throw e}finally{c.release();}
  }
}