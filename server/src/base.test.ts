import {describe,expect,it} from "vitest";
import {BASE_BUILDING_DEFINITIONS,BaseStore,calculateBuildingCost,validateBuildingPlacement} from "./base.js";

describe("base foundation",()=>{
  it("defines every Phase 6 building with level 1-7 progression",()=>{
    expect(Object.keys(BASE_BUILDING_DEFINITIONS)).toHaveLength(19);
    for(const definition of Object.values(BASE_BUILDING_DEFINITIONS)){
      expect(definition.maxLevel).toBe(7);
    }
  });
  it("calculates increasing level costs",()=>{
    expect(calculateBuildingCost("storage",1)).toEqual({wood:50,stone:25});
    expect(calculateBuildingCost("storage",3)).toEqual({wood:450,stone:225});
  });
  it("enforces prerequisites and occupied grid cells",()=>{
    const empty={buildings:[]};
    expect(()=>validateBuildingPlacement(empty,"storage",1,1,1)).toThrow("BUILDING_PREREQUISITE_MISSING");
    const withCentre={buildings:[{id:"cc",baseId:"b",type:"command_centre" as const,level:1,gridX:0,gridY:0,active:true}]};
    expect(()=>validateBuildingPlacement(withCentre,"storage",1,0,0)).toThrow("BUILDING_POSITION_OCCUPIED");
    expect(()=>validateBuildingPlacement(withCentre,"storage",1,1,1)).not.toThrow();
  });
  it("treats the owner as authoritative for all base permissions",()=>{
    const base={id:"b",ownerUserId:"owner",name:"x",x:0,y:0,buildings:[],storage:{},workPriorities:[],permissions:{}};
    expect(BaseStore.can("owner",base,"manage")).toBe(true);
    expect(BaseStore.can("other",base,"manage")).toBe(false);
  });
});