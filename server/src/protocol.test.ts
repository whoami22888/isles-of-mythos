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
});
