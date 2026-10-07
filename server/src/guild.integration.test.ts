import {describe,expect,it} from 'vitest';
import type {FastifyInstance} from 'fastify';
import type {Pool} from 'pg';
import {buildApp} from './app.js';
import {createDbPool} from './db.js';
import {BaseStore} from './base.js';
import {GuildStore} from './guild.js';
import {PlayerStore} from './player.js';

async function register(app:FastifyInstance,tag:string):Promise<string>{
  const unique='guild_'+tag+'_'+Date.now().toString(36).slice(-6)+'_'+Math.random().toString(36).slice(2,5);
  const response=await app.inject({method:'POST',url:'/auth/register',payload:{username:unique,email:unique+'@example.com',password:'Correct-Horse-Battery-9'}});
  expect(response.statusCode).toBe(201);return (JSON.parse(response.body) as {user:{id:string}}).user.id;
}
async function fixture(db:Pool,userId:string){
  const bases=new BaseStore(db);const base=await bases.create(userId,'Guild Base',0,0);
  await db.query("INSERT INTO base_buildings(base_id,type,level,grid_x,grid_y,active) VALUES($1,'guild_hall',1,1,0,true)",[base.id]);
}
describe('Gate 10 guilds',()=>{
  it('creates guilds, invites members, applies configurable ranks and persists state',async()=>{
    const app=await buildApp();const db=createDbPool();
    try{
      const owner=await register(app,'owner'),member=await register(app,'member');await fixture(db,owner);
      const guilds=new GuildStore(db);const players=new PlayerStore(db);await players.loadOrCreate(owner);await players.loadOrCreate(member);
      const guild=await guilds.create(owner,'Sea Wardens','WARD');
      expect(guild.myRank).toBe('master');expect(guild.infrastructure.find(x=>x.structureType==='guild_hall')?.level).toBe(1);expect(guild.territory).toEqual({});
      await guilds.invite(owner,guild.id,member);
      const invites=await guilds.listInvitations(member);expect(invites).toHaveLength(1);expect(invites[0]?.guildId).toBe(guild.id);
      const invitation=invites[0];if(!invitation)throw new Error('INVITATION_MISSING');const joined=await guilds.acceptInvite(member,invitation.id);expect(joined.myRank).toBe('recruit');
      await guilds.setRank(owner,guild.id,member,'veteran');
      const afterRank=await guilds.get(member);expect(afterRank.myRank).toBe('veteran');
      await db.query("UPDATE player_profiles SET inventory=jsonb_build_object('wood',1000),gold=5000,triumph_badges=0,xp=0 WHERE user_id=$1",[member]);
      await db.query("UPDATE player_profiles SET gold=5000 WHERE user_id=$1",[owner]);
      const deposit=await guilds.bankDeposit(member,guild.id,'wood',1000,'0','guild-deposit-replay','guild_bank_deposit|wood|1000|0');
      expect(deposit.transactionId).toMatch(/^[0-9a-f-]{36}$/i);
      expect(deposit.rewardTransactionIds).toHaveLength(1);
      expect(deposit.rewardTransactionIds[0]).toMatch(/^[0-9a-f-]{36}$/i);
      const replay=await guilds.bankDeposit(member,guild.id,'wood',1000,'0','guild-deposit-replay','guild_bank_deposit|wood|1000|0');
      expect(replay).toEqual(deposit);
      await app.close();
      const restartedGuilds=new GuildStore(db);
      const restartReplay=await restartedGuilds.bankDeposit(member,guild.id,'wood',1000,'0','guild-deposit-replay','guild_bank_deposit|wood|1000|0');
      expect(restartReplay).toEqual(deposit);
      await expect(restartedGuilds.bankDeposit(member,guild.id,'wood',999,'0','guild-deposit-replay','guild_bank_deposit|wood|999|0')).rejects.toThrow('GUILD_BANK_REQUEST_CONFLICT');
      const afterQuest=await guilds.get(member);
      expect(afterQuest.quests.some(q=>q.requirementItem==='wood'&&q.status==='completed')).toBe(true);
      expect(afterQuest.experience).toBe('250');expect(afterQuest.treasury).toBe('100');
      const profile=await db.query<{inventory:Record<string,number>;xp:string;triumph_badges:string}>("SELECT inventory,xp,triumph_badges FROM player_profiles WHERE user_id=$1",[member]);
      expect(profile.rows[0]?.inventory.wood).toBe(0);expect(profile.rows[0]?.xp).toBe('250');expect(profile.rows[0]?.triumph_badges).toBe('1');
      await expect(guilds.bankWithdraw(member,guild.id,'wood',1,'0','guild-withdraw-denied','guild_bank_withdraw|wood|1|0')).rejects.toThrow('GUILD_PERMISSION_DENIED');
      const treasuryDeposit=await guilds.bankDeposit(owner,guild.id,'',0,'1000','guild-treasury-deposit','guild_bank_deposit||0|1000');
      expect(treasuryDeposit.transactionId).toMatch(/^[0-9a-f-]{36}$/i);
      const infrastructure=await guilds.buildInfrastructure(owner,guild.id,'guild_hall');
      expect(infrastructure.transactionId).toMatch(/^[0-9a-f-]{36}$/i);
      const built=await guilds.get(owner);expect(built.infrastructure.find(x=>x.structureType==='guild_hall')?.level).toBe(2);expect(built.treasury).toBe('100');
      await db.query("UPDATE player_profiles SET inventory=jsonb_build_object('wood',200) WHERE user_id=$1",[member]);
      const concurrent=await Promise.all([guilds.bankDeposit(member,guild.id,'wood',100,'0','guild-concurrent-1','guild_bank_deposit|wood|100|0'),guilds.bankDeposit(member,guild.id,'wood',100,'0','guild-concurrent-2','guild_bank_deposit|wood|100|0')]);
      expect(new Set(concurrent.map(x=>x.transactionId)).size).toBe(2);
      const bank=await guilds.bank(owner,guild.id);expect(bank.items.find(x=>x.itemId==='wood')?.quantity).toBe('1200');
      const transactionIds=(bank.transactions as Array<{transaction_id:string}>).map(x=>x.transaction_id);
      expect(transactionIds.length).toBeGreaterThanOrEqual(5);
      expect(new Set(transactionIds).size).toBe(transactionIds.length);
      const app2=await buildApp({db});try{const restarted=await new GuildStore(db).get(owner);expect(restarted.id).toBe(guild.id);expect(restarted.infrastructure.find(x=>x.structureType==='guild_hall')?.level).toBe(2);}finally{await app2.close();}
    }finally{await db.end();if(app.server.listening)await app.close();}
  });
});
