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
