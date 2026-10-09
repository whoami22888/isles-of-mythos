import { describe, expect, it, vi } from "vitest";
import {
  firstEndgameCreatureId,
  firstMythicContentKey,
  selectedCreatureEngagement,
} from "./endgame-selection.js";

describe("endgame creature selection", () => {
  it("selects a valid server-returned creature ID", () => {
    expect(firstEndgameCreatureId([{ id: "creature-1", species: "Tide Drake" }])).toBe("creature-1");
  });

  it("clears selection for empty, malformed, or non-array results", () => {
    expect(firstEndgameCreatureId([])).toBeUndefined();
    expect(firstEndgameCreatureId([{ species: "Tide Drake" }])).toBeUndefined();
    expect(firstEndgameCreatureId([{ id: 42 }])).toBeUndefined();
    expect(firstEndgameCreatureId({ "0": { id: "creature-1" } })).toBeUndefined();
  });

  it("emits an engagement payload only for a valid selected creature", () => {
    const send = vi.fn();
    const selected = firstEndgameCreatureId([{ id: "creature-1" }]);
    const payload = selectedCreatureEngagement(selected);
    if (payload) send("engage_endgame_creature", payload);
    expect(send).toHaveBeenCalledOnce();
    expect(send).toHaveBeenCalledWith("engage_endgame_creature", { creatureId: "creature-1" });
  });

  it("does not emit an engagement for missing or blank selection", () => {
    const send = vi.fn();
    for (const id of [undefined, "", "   "]) {
      const payload = selectedCreatureEngagement(id);
      if (payload) send("engage_endgame_creature", payload);
    }
    expect(send).not.toHaveBeenCalled();
  });
});

describe("mythic content selection", () => {
  it("recognizes the server's contentKey field", () => {
    expect(firstMythicContentKey([{ contentKey: "mythic-abyssal-crown", title: "Abyssal Crown" }]))
      .toBe("mythic-abyssal-crown");
  });

  it("does not mistake missing or malformed content keys for available content", () => {
    expect(firstMythicContentKey([])).toBeUndefined();
    expect(firstMythicContentKey([{ id: "wrong-field" }])).toBeUndefined();
    expect(firstMythicContentKey([{ contentKey: 7 }])).toBeUndefined();
    expect(firstMythicContentKey(null)).toBeUndefined();
  });
});
