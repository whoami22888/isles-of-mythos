export type DamageType = "physical" | "fire" | "water" | "earth" | "air" | "lightning" | "ice" | "shadow" | "light" | "arcane";
export type StatusEffectId = "burn" | "poison" | "slow" | "stun";

export interface WeaponSpec {
  id: string;
  damage: number;
  range: number;
  cooldownMs: number;
  damageType: DamageType;
  criticalChance: number;
  criticalMultiplier: number;
  status?: { id: StatusEffectId; durationMs: number; magnitude: number };
}

export const WEAPONS: Record<string, WeaponSpec> = {
  cutlass: { id: "cutlass", damage: 20, range: 1.6, cooldownMs: 450, damageType: "physical", criticalChance: 0.08, criticalMultiplier: 1.75 },
  flintlock: { id: "flintlock", damage: 35, range: 8, cooldownMs: 900, damageType: "physical", criticalChance: 0.12, criticalMultiplier: 2 },
  bow: { id: "bow", damage: 24, range: 10, cooldownMs: 700, damageType: "physical", criticalChance: 0.1, criticalMultiplier: 1.8 },
  fire_spell: { id: "fire_spell", damage: 28, range: 7, cooldownMs: 1100, damageType: "fire", criticalChance: 0.1, criticalMultiplier: 2, status: { id: "burn", durationMs: 2500, magnitude: 4 } },
};

export interface StatusEffect {
  id: StatusEffectId;
  remainingMs: number;
  magnitude: number;
}

export interface CombatTarget {
  id: string;
  species: string;
  x: number;
  y: number;
  level: number;
  health: number;
  maxHealth: number;
  defense: number;
  element: DamageType;
  statuses: StatusEffect[];
}

export interface DamageResult {
  amount: number;
  critical: boolean;
  killed: boolean;
  statusApplied?: StatusEffect;
}

const ELEMENT_MULTIPLIERS: Record<DamageType, Partial<Record<DamageType, number>>> = {
  physical: {},
  fire: { ice: 1.25, water: 0.75 },
  water: { fire: 1.25, earth: 0.85 },
  earth: { lightning: 1.25, air: 0.85 },
  air: { earth: 1.15, lightning: 0.9 },
  lightning: { water: 1.25, earth: 0.75 },
  ice: { air: 1.2, fire: 0.75 },
  shadow: { light: 1.2 },
  light: { shadow: 1.2 },
  arcane: { physical: 1.1 },
};

export const CREATURE_STATS: Record<string, { health: number; defense: number; element: DamageType }> = {
  slime: { health: 45, defense: 2, element: "water" },
  boar: { health: 70, defense: 5, element: "earth" },
  raptor: { health: 90, defense: 7, element: "air" },
};

export function weaponFor(id: string | null | undefined): WeaponSpec | null {
  return id ? WEAPONS[id] ?? null : null;
}

export function distance(a: { x: number; y: number }, b: { x: number; y: number }): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

export function calculateDamage(weapon: WeaponSpec, target: Pick<CombatTarget, "defense" | "element">, random = Math.random()): DamageResult {
  const critical = random < weapon.criticalChance;
  const multiplier = ELEMENT_MULTIPLIERS[weapon.damageType][target.element] ?? 1;
  const raw = weapon.damage * (critical ? weapon.criticalMultiplier : 1) * multiplier;
  const amount = Math.max(1, Math.round(raw - target.defense));
  return { amount, critical, killed: false };
}

export function applyDamage(target: CombatTarget, weapon: WeaponSpec, random = Math.random()): DamageResult {
  const result = calculateDamage(weapon, target, random);
  target.health = Math.max(0, target.health - result.amount);
  const status = weapon.status ? { ...weapon.status } : undefined;
  if (status) {
    target.statuses = target.statuses.filter((entry) => entry.id !== status.id);
    target.statuses.push({ id: status.id, remainingMs: status.durationMs, magnitude: status.magnitude });
    result.statusApplied = { id: status.id, remainingMs: status.durationMs, magnitude: status.magnitude };
  }
  result.killed = target.health <= 0;
  return result;
}

export function tickStatuses(target: CombatTarget, dtMs: number): number {
  let damage = 0;
  const next: StatusEffect[] = [];
  for (const status of target.statuses) {
    const activeMs = Math.min(dtMs, status.remainingMs);
    if (status.id === "burn" || status.id === "poison") {
      damage += status.magnitude * activeMs / 1000;
    }
    const remainingMs = status.remainingMs - dtMs;
    if (remainingMs > 0) next.push({ ...status, remainingMs });
  }
  target.statuses = next;
  target.health = Math.max(0, target.health - damage);
  return damage;
}

export function createCombatTarget(id: string, species: string, x: number, y: number, level: number): CombatTarget {
  const stats = CREATURE_STATS[species] ?? { health: 50, defense: 3, element: "physical" as DamageType };
  const scaledHealth = stats.health + Math.max(0, level - 1) * 10;
  return { id, species, x, y, level, health: scaledHealth, maxHealth: scaledHealth, defense: stats.defense + Math.max(0, level - 1), element: stats.element, statuses: [] };
}
