export const RESOURCE_CATALOGUE = Object.freeze([
  { id: "resource.wood", name: "Wood" },
  { id: "resource.stone", name: "Stone" },
  { id: "resource.sand", name: "Sand" },
  { id: "resource.iron", name: "Iron" },
  { id: "resource.steel", name: "Steel" },
  { id: "resource.gold", name: "Gold" },
  { id: "resource.food", name: "Food" },
  { id: "resource.fish", name: "Fish" },
  { id: "resource.crystal", name: "Crystal" },
  { id: "resource.coral", name: "Coral" },
  { id: "resource.pearl", name: "Pearl" },
  { id: "resource.ancient-relics", name: "Ancient Relics" },
  { id: "resource.dragon-scales", name: "Dragon Scales" },
  { id: "resource.mermaid-pearls", name: "Mermaid Pearls" },
  { id: "resource.arcane-dust", name: "Arcane Dust" },
] as const);

export type ResourceDefinition = (typeof RESOURCE_CATALOGUE)[number];
export type ResourceId = ResourceDefinition["id"];

const RESOURCE_BY_ID = new Map<string, ResourceDefinition>(
  RESOURCE_CATALOGUE.map((resource) => [resource.id, resource]),
);

export function getResource(resourceId: string): ResourceDefinition | undefined {
  return RESOURCE_BY_ID.get(resourceId);
}

export function isResourceId(resourceId: string): resourceId is ResourceId {
  return RESOURCE_BY_ID.has(resourceId);
}

export function validateResourceId(resourceId: string): void {
  if (!isResourceId(resourceId)) throw new Error("INVALID_RESOURCE_ID");
}
