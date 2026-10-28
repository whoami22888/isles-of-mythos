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
