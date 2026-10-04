import { describe, expect, it } from "vitest";
import { RESOURCE_CATALOGUE, getResource, isResourceId, validateResourceId } from "./resource.js";

describe("resource catalogue", () => {
  it("defines every Gate 7 resource authoritatively", () => {
    expect(RESOURCE_CATALOGUE.map((resource) => resource.name)).toEqual([
      "Wood", "Stone", "Sand", "Iron", "Steel", "Gold", "Food", "Fish",
      "Crystal", "Coral", "Pearl", "Ancient Relics", "Dragon Scales",
      "Mermaid Pearls", "Arcane Dust",
    ]);
  });

  it("provides stable validated resource lookup", () => {
    expect(getResource("resource.wood")).toEqual({ id: "resource.wood", name: "Wood" });
    expect(isResourceId("resource.arcane-dust")).toBe(true);
    expect(isResourceId("resource.unknown")).toBe(false);
    expect(() => validateResourceId("resource.unknown")).toThrow("INVALID_RESOURCE_ID");
  });
});
