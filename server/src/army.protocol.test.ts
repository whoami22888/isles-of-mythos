import {describe,expect,it} from "vitest";
import {parseClientMessage} from "./protocol.js";

describe("Gate 11 tactical army protocol",()=>{
  it("accepts bounded army, command, battle and defense messages",()=>{
    expect(parseClientMessage(JSON.stringify({type:"create_army",requestId:"a",name:"First Company"}))?.type).toBe("create_army");
    expect(parseClientMessage(JSON.stringify({type:"train_army",requestId:"t",armyId:"a",unitType:"pirate_infantry",quantity:10}))?.type).toBe("train_army");
    expect(parseClientMessage(JSON.stringify({type:"set_army_formation",requestId:"f",armyId:"a",name:"Line",formationType:"line",layout:{slots:[1,2]}}))?.type).toBe("set_army_formation");
    expect(parseClientMessage(JSON.stringify({type:"issue_army_order",requestId:"o",armyId:"a",battleId:null,orderType:"defend",targetUnitId:null,targetX:2,targetY:3,payload:{priority:"nearest"}}))?.type).toBe("issue_army_order");
    expect(parseClientMessage(JSON.stringify({type:"create_army_battle",requestId:"b",attackerArmyId:"a",defenderArmyId:null,targetX:1,targetY:2}))?.type).toBe("create_army_battle");
    expect(parseClientMessage(JSON.stringify({type:"build_defense",requestId:"d",baseId:"b",structureType:"spike_trap",gridX:2,gridY:3}))?.type).toBe("build_defense");
    expect(parseClientMessage(JSON.stringify({type:"army_tactical_action",requestId:"x",battleId:"b",unitId:"u",actionType:"ability",targetUnitId:"t"}))?.type).toBe("army_tactical_action");
    expect(parseClientMessage(JSON.stringify({type:"train_army",requestId:"t",armyId:"a",unitType:"pirate_infantry",quantity:1001}))).toBeNull();
  });
});
