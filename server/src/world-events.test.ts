import { describe, expect, it } from "vitest";
import { calculateWorldEventReward } from "./world-events.js";

describe("Gate 15 deterministic world-event loot",()=>{
  it("returns deterministic rank-scaled server-side rewards",()=>{
    const first=calculateWorldEventReward("kraken",100n,1);
    const second=calculateWorldEventReward("kraken",100n,1);
    expect(first).toEqual(second);
    expect(first.gold).toBe(10000n);
    expect(first.items).toEqual({"resource.mermaid-pearls":3});
    expect(calculateWorldEventReward("kraken",100n,2)).toEqual({gold:6000n,items:{"resource.mermaid-pearls":1}});
  });
  it("supports all Gate 15 event types without exposing a client loot table",()=>{
    for(const type of ["world_boss","treasure_storm","ghost_fleet","kraken","dragon_migration"] as const){
      const reward=calculateWorldEventReward(type,10n,1);
      expect(reward.gold).toBeGreaterThan(0n);
      expect(Object.keys(reward.items).length).toBeGreaterThan(0);
    }
  });
});
