import { describe, expect, it } from "vitest";
import { parseClientMessage } from "./protocol.js";

describe("resource gathering protocol", () => {
  it("accepts bounded gather requests", () => {
    expect(parseClientMessage(JSON.stringify({
      type: "gather_resource",
      requestId: "gather-1",
      resourceId: "wood:10:20",
    }))).toEqual({ type: "gather_resource", requestId: "gather-1", resourceId: "wood:10:20" });
  });

  it("rejects invalid resource identifiers and request ids", () => {
    expect(parseClientMessage(JSON.stringify({
      type: "gather_resource",
      requestId: "",
      resourceId: "wood:10:20",
    }))).toBeNull();
    expect(parseClientMessage(JSON.stringify({
      type: "gather_resource",
      requestId: "gather-1",
      resourceId: "",
    }))).toBeNull();
  });
});
