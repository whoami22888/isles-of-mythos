import { describe, expect, it } from "vitest";
import { parseClientMessage } from "./protocol.js";

describe("Gate 16 endgame protocol",()=>{
  it("accepts realm-war and guild-battle commands",()=>{
    expect(parseClientMessage(JSON.stringify({type:"create_realm_war",requestId:"r",attackerRealmId:"a",defenderRealmId:"d",targetTerritoryId:"t"}))).toEqual({type:"create_realm_war",requestId:"r",attackerRealmId:"a",defenderRealmId:"d",targetTerritoryId:"t"});
    expect(parseClientMessage(JSON.stringify({type:"join_realm_war",requestId:"r",warId:"w",guildId:"g",realmId:"d"}))).toEqual({type:"join_realm_war",requestId:"r",warId:"w",guildId:"g",realmId:"d"});
    expect(parseClientMessage(JSON.stringify({type:"join_guild_battle",requestId:"r",battleId:"b",armyId:"a"}))).toEqual({type:"join_guild_battle",requestId:"r",battleId:"b",armyId:"a"});
  });
  it("rejects malformed endgame identifiers",()=>{
    expect(parseClientMessage(JSON.stringify({type:"engage_endgame_creature",requestId:"",creatureId:"c"}))).toBeNull();
    expect(parseClientMessage(JSON.stringify({type:"realm_war_action",requestId:"r",warId:"",guildId:"g",armyId:"a"}))).toBeNull();
  });
});