
describe("resource gather transaction protocol", () => {
  const state = {
    userId:"user-1", x:0, y:0, health:100, defense:0, stamina:100, maxStamina:100,
    hunger:100, oxygen:100, xp:0, level:1, gold:"80", triumphBadges:"0",
    inventory:{"resource.wood":2}, hotbar:[null,null,null,null,null,null,null,null], selectedHotbarSlot:0,
  };
  it("requires a valid transaction id on resource gather results", () => {
    expect(parseServerMessage({
      type:"resource_gathered", requestId:"gather-1", transactionId:"550e8400-e29b-41d4-a716-446655440000",
      resourceId:"node-1", itemId:"resource.wood", quantity:2, respawnsAt:"2026-10-07T14:00:00.000Z", state,
    })).toMatchObject({type:"resource_gathered",transactionId:"550e8400-e29b-41d4-a716-446655440000"});
    expect(parseServerMessage({
      type:"resource_gathered", requestId:"gather-2", transactionId:123,
      resourceId:"node-1", itemId:"resource.wood", quantity:2, respawnsAt:"2026-10-07T14:00:00.000Z", state,
    })).toBeNull();
  });
});

describe("craft transaction protocol", () => {
  const state = {
    userId:"user-1", x:0, y:0, health:100, defense:0, stamina:100, maxStamina:100,
    hunger:100, oxygen:100, xp:0, level:1, gold:"80", triumphBadges:"0",
    inventory:{"resource.wood":1}, hotbar:[null,null,null,null,null,null,null,null], selectedHotbarSlot:0,
  };
  it("requires a valid transaction id on craft results", () => {
    expect(parseServerMessage({
      type:"craft_result", requestId:"craft-1", transactionId:"550e8400-e29b-41d4-a716-446655440000",
      recipeId:"tool.wooden-club", state,
    })).toMatchObject({type:"craft_result",transactionId:"550e8400-e29b-41d4-a716-446655440000"});
    expect(parseServerMessage({
      type:"craft_result", requestId:"craft-2", transactionId:123,
      recipeId:"tool.wooden-club", state,
    })).toBeNull();
  });
});

describe("shop transaction protocol", () => {
  const state = {
    userId:"user-1", x:0, y:0, health:100, defense:0, stamina:100, maxStamina:100,
    hunger:100, oxygen:100, xp:0, level:1, gold:"80", triumphBadges:"0",
    inventory:{"resource.wood":2}, hotbar:[null,null,null,null,null,null,null,null], selectedHotbarSlot:0,
  };

  it("requires a server-generated transaction id on shop results", () => {
    expect(parseServerMessage({
      type:"shop_purchase_result", requestId:"purchase-1", transactionId:"550e8400-e29b-41d4-a716-446655440000",
      itemId:"resource.wood", quantity:2, totalGold:"20", state,
    })).toMatchObject({type:"shop_purchase_result", transactionId:"550e8400-e29b-41d4-a716-446655440000"});

    expect(parseServerMessage({
      type:"shop_purchase_result", requestId:"purchase-2", transactionId:123,
      itemId:"resource.wood", quantity:2, totalGold:"20", state,
    })).toBeNull();
  });
});

import { describe, expect, it } from "vitest";
import { parseServerMessage } from "./network.js";

describe("guild transaction protocol", () => {
  it("accepts transaction ids for mutating guild operations", () => {
    expect(parseServerMessage({
      type:"guild_operation_ok", requestId:"guild-1", guildId:"guild-1",
      transactionId:"550e8400-e29b-41d4-a716-446655440000", rewardTransactionIds:["550e8400-e29b-41d4-a716-446655440001"],
    })).toMatchObject({type:"guild_operation_ok",transactionId:"550e8400-e29b-41d4-a716-446655440000",rewardTransactionIds:["550e8400-e29b-41d4-a716-446655440001"]});

    expect(parseServerMessage({
      type:"guild_operation_ok", requestId:"guild-2", guildId:"guild-1", transactionId:123,
    })).toBeNull();

    expect(parseServerMessage({
      type:"guild_operation_ok", requestId:"guild-2b", guildId:"guild-1", rewardTransactionIds:[123],
    })).toBeNull();

    expect(parseServerMessage({
      type:"guild_operation_ok", requestId:"guild-3", guildId:"guild-1",
    })).toMatchObject({type:"guild_operation_ok",guildId:"guild-1"});
  });
});

describe("Gate 13 client invasion protocol", () => {
  it("parses an invasion list and tactical wave state", () => {
    expect(parseServerMessage({
      type:"invasion_list",
      requestId:"r1",
      invasions:[{
        id:"inv-1",territoryId:"territory-1",sourceType:"pirate_fleet",targetBaseId:"base-1",
        phase:"BATTLE",threatScore:5000,outcome:null,phaseEndsAt:"2026-10-05T00:00:00.000Z",
      }],
    })).toMatchObject({ type:"invasion_list", requestId:"r1" });
    expect(parseServerMessage({
      type:"invasion_waves",
      requestId:"r2",
      invasionId:"inv-1",
      waves:[{
        id:"wave-1",wave_number:1,unit_type:"pirate_infantry",category:"infantry",quantity:10,
        max_health:1000,current_health:900,attack:14,defense:12,status:"active",aggro_range:14,target_user_id:"user-1",
      }],
    })).toMatchObject({ type:"invasion_waves", invasionId:"inv-1" });
  });

  it("rejects malformed invasion state rather than trusting it", () => {
    expect(parseServerMessage({
      type:"invasion_waves",requestId:"r3",invasionId:"inv-1",
      waves:[{ id:"wave-1",wave_number:1,unit_type:"pirate_infantry",category:"infantry",quantity:10,
        max_health:1000,current_health:900,attack:14,defense:12,status:"active",aggro_range:0,target_user_id:null }],
    })).toBeNull();
  });

  it("parses the army list used by the tactical overlay", () => {
    expect(parseServerMessage({
      type:"army_list",requestId:"r4",
      armies:[{id:"army-1",name:"Harbor Guard",assignment:"garrison",status:"ready"}],
    })).toMatchObject({ type:"army_list", requestId:"r4" });
  });
});


describe("Gate 14 client social protocol",()=>{
  it("parses friends, chat, party and auction messages",()=>{
    expect(parseServerMessage({type:"friends_list",requestId:"f1",friends:[]})).toMatchObject({type:"friends_list"});
    expect(parseServerMessage({type:"chat_message",requestId:"c1",message:{channel:"global",body:"hello"}})).toMatchObject({type:"chat_message"});
    expect(parseServerMessage({type:"party_state",requestId:"p1",party:null})).toMatchObject({type:"party_state",party:null});
    expect(parseServerMessage({type:"auction_list",requestId:"a1",listings:[]})).toMatchObject({type:"auction_list"});
  });
});


describe("Gate 15 client world event protocol",()=>{
  it("parses global event state and rejects malformed health values",()=>{
    const event={id:"event-1",eventType:"kraken",status:"active",regionId:null,centerX:10,centerY:-4,maxHealth:"10000000",currentHealth:"9999990",state:{phase:1},startedAt:"2026-10-05T00:00:00.000Z",endsAt:"2026-10-05T00:15:00.000Z"};
    expect(parseServerMessage({type:"world_event_state",requestId:"e1",event})).toMatchObject({type:"world_event_state",event:{eventType:"kraken"}});
    expect(parseServerMessage({type:"world_event_list",requestId:"e2",events:[event]})).toMatchObject({type:"world_event_list",requestId:"e2"});
    expect(parseServerMessage({type:"world_event_state",requestId:"e3",event:{...event,maxHealth:100,currentHealth:50}})).toBeNull();
  });
});


describe("resource gathering messages", () => {
  it("parses a resource reward with updated player state", () => {
    expect(parseServerMessage({
      type: "resource_gathered",
      requestId: "gather-1",
      resourceId: "wood:10:20",
      itemId: "resource.wood",
      quantity: 2,
      respawnsAt: "2026-10-07T08:00:00.000Z",
      state: {
        userId: "user-1",
        x: 10,
        y: 20,
        health: 100,
        defense: 0,
        stamina: 100,
        maxStamina: 100,
        hunger: 100,
        oxygen: 100,
        xp: 0,
        level: 1,
        gold: "0",
        triumphBadges: "0",
        inventory: { "resource.wood": 2 },
        hotbar: [null, null, null, null, null, null, null, null],
        selectedHotbarSlot: 0,
      },
    })).toMatchObject({ type: "resource_gathered", resourceId: "wood:10:20", itemId: "resource.wood", quantity: 2 });
  });
});


describe("system response parser", () => {
  it("accepts authoritative state responses for client system flows", () => {
    const types = [
      "guild_state","guild_invitations","guild_bank_state","realm_list","territory_list","fortress_list",
      "trade_route_list","battle_state","defense_list","ship_list","fleet_list","breeding_jobs",
      "realm_war_list","guild_battle_list","endgame_creature_list","mythic_content_list","territory_season_state",
    ];
    for (const type of types) {
      expect(parseServerMessage({ type, requestId: "system-1", state: "server-state" })).toMatchObject({ type, requestId: "system-1" });
    }
  });
});
