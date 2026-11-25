import { describe, expect, it } from "vitest";
import { applyTurnRate, resolveBroadside, shortestSignedAngle } from "./ship-turn.js";

describe("applyTurnRate", () => {
  it("reaches the requested heading when the turn-rate budget is large enough", () => {
    const turned = applyTurnRate(0, { x: 0, y: 1 }, 2, 60);
    expect(turned.heading).toBeCloseTo(Math.PI / 2, 10);
    expect(turned.travel.x).toBeCloseTo(0, 10);
    expect(turned.travel.y).toBeCloseTo(1, 10);
  });

  it("caps a 180-degree request to turnRate * dt and travels along the intermediate heading", () => {
    const turned = applyTurnRate(0, { x: -1, y: 0 }, 2, 0.5);
    expect(turned.heading).toBeCloseTo(1, 10);
    expect(turned.travel.x).toBeCloseTo(Math.cos(1), 10);
    expect(turned.travel.y).toBeCloseTo(Math.sin(1), 10);
    expect(Math.abs(turned.heading)).toBeLessThan(Math.PI / 2);
  });

  it("does not turn when elapsed time is zero", () => {
    const turned = applyTurnRate(0.4, { x: 0, y: 1 }, 2, 0);
    expect(turned.heading).toBeCloseTo(0.4, 10);
    expect(turned.travel.x).toBeCloseTo(Math.cos(0.4), 10);
    expect(turned.travel.y).toBeCloseTo(Math.sin(0.4), 10);
  });
});

describe("resolveBroadside", () => {
  it("treats a target on +Y as port when heading faces +X", () => {
    expect(resolveBroadside(0, 0, 0, 0, 20)).toBe("port");
  });

  it("treats a target on -Y as starboard when heading faces +X", () => {
    expect(resolveBroadside(0, 0, 0, 0, -20)).toBe("starboard");
  });

  it("rejects bow and stern shots", () => {
    expect(resolveBroadside(0, 0, 0, 20, 0)).toBeNull();
    expect(resolveBroadside(0, 0, 0, -20, 0)).toBeNull();
    expect(resolveBroadside(0, 0, 0, 0, 0)).toBeNull();
  });

  it("still accepts a target 40 degrees off the port beam", () => {
    const x = 20 * Math.sin(40 * Math.PI / 180);
    const y = 20 * Math.cos(40 * Math.PI / 180);
    expect(resolveBroadside(0, 0, 0, x, y)).toBe("port");
  });

  it("uses the shortest signed angle across the PI wrap", () => {
    expect(shortestSignedAngle(Math.PI - 0.1, -Math.PI + 0.1)).toBeCloseTo(0.2, 10);
  });
});
