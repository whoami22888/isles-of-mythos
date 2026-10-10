import { describe, expect, it } from "vitest";
import { findBasePath, nextWorkerWaypoint } from "./base-pathfinding.js";

describe("base worker pathfinding", () => {
  it("returns the deterministic shortest four-way path to a lumber mill", () => {
    expect(findBasePath({ x: 0, y: 0 }, { x: 2, y: 0 }, [])).toEqual([
      { x: 0, y: 0 },
      { x: 1, y: 0 },
      { x: 2, y: 0 },
    ]);
  });

  it("routes around active buildings and ignores inactive buildings", () => {
    const path = findBasePath(
      { x: 0, y: 0 },
      { x: 2, y: 0 },
      [
        { x: 1, y: 0, active: true },
        { x: 1, y: 1, active: false },
      ],
    );
    expect(path).not.toBeNull();
    expect(path?.[1]).toEqual({ x: 0, y: -1 });
    expect(path?.some((point) => point.x === 1 && point.y === 0)).toBe(true);
    expect(path?.length).toBe(5);
  });

  it("returns null when the goal is outside the base grid or enclosed", () => {
    expect(findBasePath({ x: 0, y: 0 }, { x: 129, y: 0 }, [])).toBeNull();
    expect(findBasePath(
      { x: 0, y: 0 },
      { x: 2, y: 0 },
      [
        { x: 1, y: 0, active: true },
        { x: 2, y: 1, active: true },
        { x: 2, y: -1, active: true },
        { x: 3, y: 0, active: true },
      ],
    )).toBeNull();
  });

  it("routes an assigned worker toward its lumber mill while avoiding other buildings", () => {
    const base = {
      x: 10,
      y: 20,
      buildings: [
        { id: "cc", gridX: 0, gridY: 0, active: true },
        { id: "blocker", gridX: 1, gridY: 0, active: true },
        { id: "mill", gridX: 2, gridY: 0, active: true },
      ],
      workers: [{ creatureId: "worker-1", buildingId: "mill" }],
    };
    expect(nextWorkerWaypoint(base, "worker-1", 10.5, 20.5)).toEqual({ x: 10.5, y: 19.5 });
    expect(nextWorkerWaypoint(base, "unassigned", 10.5, 20.5)).toBeNull();
    expect(nextWorkerWaypoint(base, "worker-1", Number.NaN, 20.5)).toBeNull();
  });

  it("returns a single point when the worker is already at the target", () => {
    expect(findBasePath({ x: -4, y: 7 }, { x: -4, y: 7 }, [])).toEqual([{ x: -4, y: 7 }]);
  });
});
