import { describe, expect, it } from "vitest";
import { EngineStateManager, normalizeFrameDelta } from "./engine-state.js";

describe("engine initialization state", () => {
  it("starts at the menu and enters the overworld", () => {
    const states = new EngineStateManager();
    expect(states.state).toBe("menu");
    expect(states.transition("overworld")).toBe("overworld");
  });

  it("allows base-build and combat UI to return to the overworld", () => {
    const states = new EngineStateManager();
    states.transition("overworld");
    expect(states.transition("base-build")).toBe("base-build");
    expect(states.transition("overworld")).toBe("overworld");
    expect(states.transition("combat-ui")).toBe("combat-ui");
    expect(states.transition("overworld")).toBe("overworld");
  });

  it("rejects transitions that skip required game states", () => {
    const states = new EngineStateManager();
    expect(() => states.transition("base-build")).toThrow(
      "INVALID_ENGINE_STATE_TRANSITION:menu->base-build",
    );
  });

  it("normalizes invalid and oversized frame deltas", () => {
    expect(normalizeFrameDelta(Number.NaN)).toBe(0);
    expect(normalizeFrameDelta(-5)).toBe(0);
    expect(normalizeFrameDelta(16.7)).toBe(16.7);
    expect(normalizeFrameDelta(250)).toBe(100);
  });

  it("rejects an invalid maximum frame delta", () => {
    expect(() => normalizeFrameDelta(16, 0)).toThrow("INVALID_MAXIMUM_FRAME_DELTA");
  });
});
