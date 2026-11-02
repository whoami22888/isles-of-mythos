import { describe, expect, it } from "vitest";
import { MIN_SAIL_HEADING_LENGTH, unitSailHeading } from "./sail-heading.js";

describe("unit sail heading", () => {
  it("normalizes diagonals and partial components to the same speed as a cardinal heading", () => {
    for (const [dx, dy] of [[1, 0], [0, 1], [-1, 0], [0, -1], [1, 1], [-1, -1], [1, -1], [-1, 1], [0.2, -0.2]] as const) {
      const heading = unitSailHeading(dx, dy);
      expect(heading).not.toBeNull();
      expect(Math.hypot(heading!.x, heading!.y)).toBeCloseTo(1, 8);
    }
    const east = unitSailHeading(1, 0)!;
    const diagonal = unitSailHeading(1, 1)!;
    const partial = unitSailHeading(0.2, -0.2)!;
    const samePartial = unitSailHeading(1, -1)!;
    expect(Math.hypot(diagonal.x, diagonal.y)).toBeCloseTo(Math.hypot(east.x, east.y), 8);
    expect(partial.x).toBeCloseTo(samePartial.x, 8);
    expect(partial.y).toBeCloseTo(samePartial.y, 8);
    expect(diagonal.x).toBeCloseTo(Math.SQRT1_2, 8);
    expect(diagonal.y).toBeCloseTo(Math.SQRT1_2, 8);
  });

  it("rejects zero, tiny, non-finite, and out-of-range headings", () => {
    expect(unitSailHeading(0, 0)).toBeNull();
    expect(unitSailHeading(MIN_SAIL_HEADING_LENGTH / 10, 0)).toBeNull();
    expect(unitSailHeading(1e-8, 1e-8)).toBeNull();
    expect(unitSailHeading(Number.NaN, 1)).toBeNull();
    expect(unitSailHeading(1, Number.POSITIVE_INFINITY)).toBeNull();
    expect(unitSailHeading(1.0000001, 0)).toBeNull();
    expect(unitSailHeading(0, -1.01)).toBeNull();
    expect(unitSailHeading("1", 0)).toBeNull();
    expect(unitSailHeading(1, null)).toBeNull();
  });
});
