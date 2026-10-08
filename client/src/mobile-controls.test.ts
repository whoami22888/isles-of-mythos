import { describe, expect, it } from "vitest";
import { getMobileLayout, normalizeStick } from "./mobile-layout.js";

describe("mobile touch controls", () => {
  it("normalizes a centered stick to zero", () => {
    expect(normalizeStick(0, 0, 64)).toEqual({ x: 0, y: 0 });
  });

  it("clamps diagonal input to the stick boundary", () => {
    const value = normalizeStick(100, 100, 64);
    expect(Math.hypot(value.x, value.y)).toBeCloseTo(1, 5);
    expect(value.x).toBeCloseTo(value.y, 5);
  });

  it("handles invalid stick radius safely", () => {
    expect(normalizeStick(10, 10, 0)).toEqual({ x: 0, y: 0 });
    expect(normalizeStick(10, 10, Number.NaN)).toEqual({ x: 0, y: 0 });
  });

  it("keeps controls inside a responsive viewport", () => {
    for (const [width, height] of [[320, 480], [480, 320], [800, 480], [1280, 720]]) {
      const layout = getMobileLayout(width, height);
      expect(layout.radius).toBeGreaterThan(0);
      expect(layout.joystickX - layout.radius).toBeGreaterThanOrEqual(0);
      expect(layout.joystickY + layout.radius).toBeLessThanOrEqual(height);
      expect(layout.actionX + layout.radius).toBeLessThanOrEqual(width);
      expect(layout.actionY + layout.radius).toBeLessThanOrEqual(height);
    }
  });

  it("uses the same safe layout strategy for portrait and landscape", () => {
    const portrait = getMobileLayout(480, 800);
    const landscape = getMobileLayout(800, 480);
    expect(portrait.joystickX).toBeLessThan(landscape.joystickX);
    expect(portrait.joystickY).toBeGreaterThan(landscape.joystickY);
  });
});
