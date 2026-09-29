import {describe,expect,it} from "vitest";
import {BASE_BUILDING_DEFINITIONS,BaseStore,calculateBuildingCost,validateBuildingPlacement} from "./base.js";

describe("base foundation",()=>{
  it("defines every Phase 6 building with level 1-7 progression",()=>{
    expect(Object.keys(BASE_BUILDING_DEFINITIONS)).toHaveLength(19);
    for(const definition of Object.values(BASE_BUILDING_DEFINITIONS)){
      expect(definition.maxLevel).toBe(7);
    }
  });
  it("treats the owner as authoritative for all base permissions",()=>{
    const base={id:"b",ownerUserId:"owner",name:"x",x:0,y:0,buildings:[],storage:{},workPriorities:[],permissions:{}};
    expect(BaseStore.can("owner",base,"manage")).toBe(true);
    expect(BaseStore.can("other",base,"manage")).toBe(false);
  });
});