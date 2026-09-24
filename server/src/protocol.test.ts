import { describe, expect, it } from "vitest";
import { parseClientMessage } from "./protocol.js";

describe("combat protocol", () => {
  it("accepts bounded attack messages", () => {
    expect(parseClientMessage(JSON.stringify({
      type: "attack",
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
      targetId: "creature:10:-4",
      facingX: 4,
      facingY: 0,
    }))).toBeNull();
    expect(parseClientMessage(JSON.stringify({
      type: "attack",
      targetId: "",
      facingX: 1,
      facingY: 0,
    }))).toBeNull();
  });
});
