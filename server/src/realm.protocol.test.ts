import {describe,expect,it} from "vitest";
import {parseClientMessage} from "./protocol.js";
describe("Gate 12 realm protocol",()=>{
 it("validates realm, territory, reputation and trade messages",()=>{
  expect(parseClientMessage(JSON.stringify({type:"list_realms",requestId:"r"}))?.type).toBe("list_realms");
  expect(parseClientMessage(JSON.stringify({type:"territory_at",requestId:"t",x:10,y:20}))?.type).toBe("territory_at");
  expect(parseClientMessage(JSON.stringify({type:"change_realm_reputation",requestId:"p",realm:"Sunken Kingdom",delta:100}))?.type).toBe("change_realm_reputation");
  expect(parseClientMessage(JSON.stringify({type:"create_trade_route",requestId:"x",sourceTerritoryId:"a",destinationTerritoryId:"b",resourceKey:"iron",quantity:"1000",travelSeconds:60,guildId:null,realmId:null}))?.type).toBe("create_trade_route");
  expect(parseClientMessage(JSON.stringify({type:"create_trade_route",requestId:"x",sourceTerritoryId:"a",destinationTerritoryId:"b",resourceKey:"iron",quantity:"-1",travelSeconds:60,guildId:null,realmId:null}))).toBeNull();
 });
});
