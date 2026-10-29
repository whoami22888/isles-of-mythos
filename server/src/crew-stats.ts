/**
 * Server-owned crew stats. Clients never choose skill or morale: a client-chosen skill/morale of
 * 100 would otherwise raise sailing speed (crew multiplier) and naval effectiveness for free.
 * Values are conservative baselines and are balance tunables for design review.
 */
export type NpcCrewType = "pirate" | "mermaid" | "dragon" | "npc_specialist";

export const CREW_START_MORALE = 100;

const NPC_CREW_SKILL: Readonly<Record<NpcCrewType, number>> = {
  pirate: 30,
  mermaid: 40,
  npc_specialist: 50,
  dragon: 60,
};

/** A tamed creature's crew skill is its persisted level (1..100). */
export function deriveCreatureCrewSkill(level: number): number {
  if (!Number.isFinite(level)) return 1;
  return Math.min(100, Math.max(1, Math.floor(level)));
}

export function deriveNpcCrewSkill(npcType: NpcCrewType): number {
  return NPC_CREW_SKILL[npcType];
}

/**
 * Owner decision D-07 (2026-10-29, fees revised to 5,000/25,000): NPC crew is a paid Gold Doubloon sink, fail-closed. A daily upkeep system is planned as a follow-up and is not implemented here.
 * Only pirates and specialists can be hired. Dragons and mermaids are earned through capture,
 * taming, research and town upgrades, never bought, so they are absent from this table.
 */
const NPC_CREW_HIRE_FEE: ReadonlyMap<string, bigint> = new Map<string, bigint>([
  ["pirate", 5_000n],
  ["npc_specialist", 25_000n],
]);

export function npcCrewHireFee(npcType: NpcCrewType): bigint {
  const fee = NPC_CREW_HIRE_FEE.get(npcType);
  if (fee === undefined) throw new Error("NPC_CREW_UNAVAILABLE");
  return fee;
}
