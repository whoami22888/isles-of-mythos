function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function firstEndgameCreatureId(value: unknown): string | undefined {
  if (!Array.isArray(value)) return undefined;
  const first: unknown = value[0];
  if (!isRecord(first) || typeof first.id !== "string" || first.id.trim().length === 0) return undefined;
  return first.id;
}

export function firstMythicContentKey(value: unknown): string | undefined {
  if (!Array.isArray(value)) return undefined;
  const first: unknown = value[0];
  if (!isRecord(first) || typeof first.contentKey !== "string" || first.contentKey.trim().length === 0) return undefined;
  return first.contentKey;
}

export function selectedCreatureEngagement(selectedId: string | undefined): { creatureId: string } | undefined {
  if (typeof selectedId !== "string" || selectedId.trim().length === 0) return undefined;
  return { creatureId: selectedId };
}
