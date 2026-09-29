import { describe, expect, it } from "vitest";
import { parseClientMessage } from "./protocol.js";

describe("combat protocol", () => {
  it("accepts bounded attack messages", () => {
    expect(parseClientMessage(JSON.stringify({
      type: "attack",
      requestId: "attack-1",
      targetId: "creature:10:-4",
      facingX: 1,
      facingY: 0,
    }))).toEqual({
      type: "attack",
      requestId: "attack-1",
      targetId: "creature:10:-4",
      facingX: 1,
      facingY: 0,
    });
  });

  it("rejects malformed or unbounded attack messages", () => {
    expect(parseClientMessage(JSON.stringify({
      type: "attack",
      requestId: "attack-3",
      targetId: "creature:10:-4",
      facingX: 4,
      facingY: 0,
    }))).toBeNull();
    expect(parseClientMessage(JSON.stringify({
      type: "attack",
      requestId: "attack-2",
      targetId: "",
      facingX: 1,
      facingY: 0,
    }))).toBeNull();
  });
  it("accepts dodge and block controls", () => {
    expect(parseClientMessage(JSON.stringify({ type: "dodge", facingX: 1, facingY: 0 }))).toEqual({ type: "dodge", facingX: 1, facingY: 0 });
    expect(parseClientMessage(JSON.stringify({ type: "block", active: true }))).toEqual({ type: "block", active: true });
    expect(parseClientMessage(JSON.stringify({ type: "block", active: "yes" }))).toBeNull();
  });
  it("accepts bounded base management messages",()=>{
    expect(parseClientMessage(JSON.stringify({type:"upgrade_building",requestId:"u1",buildingId:"b1"}))).toEqual({type:"upgrade_building",requestId:"u1",buildingId:"b1"});
    expect(parseClientMessage(JSON.stringify({type:"storage",requestId:"s1",changes:{wood:10,stone:-5}}))).toEqual({type:"storage",requestId:"s1",changes:{wood:10,stone:-5}});
    expect(parseClientMessage(JSON.stringify({type:"set_base_permission",requestId:"p1",targetUserId:"u2",permission:"build",enabled:true}))).toEqual({type:"set_base_permission",requestId:"p1",targetUserId:"u2",permission:"build",enabled:true});
    expect(parseClientMessage(JSON.stringify({type:"assign_worker",requestId:"w1",creatureId:"c1",buildingId:"b1",task:"auto"}))).toEqual({type:"assign_worker",requestId:"w1",creatureId:"c1",buildingId:"b1",task:"auto"});
    expect(parseClientMessage(JSON.stringify({type:"set_work_priorities",requestId:"q1",priorities:["repair","collect","store"]}))).toEqual({type:"set_work_priorities",requestId:"q1",priorities:["repair","collect","store"]});
  });
  it("rejects unbounded storage mutations",()=>{
    expect(parseClientMessage(JSON.stringify({type:"storage",requestId:"s1",changes:{wood:1e12}}))).toBeNull();
    expect(parseClientMessage(JSON.stringify({type:"storage",requestId:"s1",changes:{}}))).toBeNull();
  });
});
