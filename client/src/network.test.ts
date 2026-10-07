import { describe, expect, it } from "vitest";
import { parseServerMessage } from "./network.js";

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
