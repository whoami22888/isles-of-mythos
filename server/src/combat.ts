export type DamageType = "physical" | "fire" | "water" | "earth" | "air" | "lightning" | "ice" | "shadow" | "light" | "arcane";
export type StatusEffectId = "burn" | "poison" | "slow" | "stun";

export interface WeaponSpec {
  id: string;
  damage: number;
  range: number;
  cooldownMs: number;
  staminaCost: number;
  damageType: DamageType;
  criticalChance: number;
  criticalMultiplier: number;
  status?: { id: StatusEffectId; durationMs: number; magnitude: number };
}

export const WEAPONS: Record<string, WeaponSpec> = {
  cutlass: { id: "cutlass", damage: 20, range: 1.6, cooldownMs: 450, staminaCost: 8, damageType: "physical", criticalChance: 0.08, criticalMultiplier: 1.75 },
  dagger: { id: "dagger", damage: 14, range: 1.4, cooldownMs: 300, staminaCost: 6, damageType: "physical", criticalChance: 0.18, criticalMultiplier: 2 },
  flintlock: { id: "flintlock", damage: 35, range: 8, cooldownMs: 900, staminaCost: 10, damageType: "physical", criticalChance: 0.12, criticalMultiplier: 2 },
  musket: { id: "musket", damage: 52, range: 12, cooldownMs: 1500, staminaCost: 14, damageType: "physical", criticalChance: 0.1, criticalMultiplier: 2.1 },
  bow: { id: "bow", damage: 24, range: 10, cooldownMs: 700, staminaCost: 8, damageType: "physical", criticalChance: 0.1, criticalMultiplier: 1.8 },
  fire_spell: { id: "fire_spell", damage: 28, range: 7, cooldownMs: 1100, staminaCost: 16, damageType: "fire", criticalChance: 0.1, criticalMultiplier: 2, status: { id: "burn", durationMs: 2500, magnitude: 4 } },
  harpoon: { id: "harpoon", damage: 18, range: 9, cooldownMs: 1000, staminaCost: 12, damageType: "physical", criticalChance: 0.05, criticalMultiplier: 1.6 },
};

export interface StatusEffect {
  id: StatusEffectId;
  remainingMs: number;
  magnitude: number;
}

export interface ThreatEntry {
  userId: string;
  threat: number;
  lastHitAt: number;
}

export type CreatureAiState = "idle" | "alert" | "chase" | "attack" | "flee" | "stunned" | "dead";

export interface CreatureAbility {
  id: string;
  cooldownMs: number;
  range: number;
  damage: number;
  damageType: DamageType;
  status?: { id: StatusEffectId; durationMs: number; magnitude: number };
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
  speed: number;
  attack: number;
  stamina: number;
  maxStamina: number;
  aiState: CreatureAiState;
  aggroRange: number;
  attackRange: number;
  nextAbilityAt: number;
  statuses: StatusEffect[];
  threat: Map<string, ThreatEntry>;
}

export interface DamageResult {
  amount: number;
  critical: boolean;
  killed: boolean;
  statusApplied?: StatusEffect;
}

export interface CreatureAiResult {
  targetUserId: string | null;
  state: CreatureAiState;
  moveX: number;
  moveY: number;
  ability?: CreatureAbility;
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

export const CREATURE_STATS: Record<string, {
  health: number; defense: number; element: DamageType; speed: number; attack: number; aggroRange: number; attackRange: number; ability?: CreatureAbility;
}> = {
  slime: { health: 45, defense: 2, element: "water", speed: 1.4, attack: 7, aggroRange: 5, attackRange: 1.2, ability: { id: "acid_burst", cooldownMs: 3500, range: 3.5, damage: 10, damageType: "water", status: { id: "slow", durationMs: 1500, magnitude: 0.35 } } },
  boar: { health: 70, defense: 5, element: "earth", speed: 2.1, attack: 11, aggroRange: 6, attackRange: 1.4, ability: { id: "charge", cooldownMs: 4000, range: 4, damage: 18, damageType: "earth" } },
  raptor: { health: 90, defense: 7, element: "air", speed: 2.7, attack: 14, aggroRange: 8, attackRange: 1.6, ability: { id: "pounce", cooldownMs: 3000, range: 5, damage: 22, damageType: "air", status: { id: "stun", durationMs: 700, magnitude: 1 } } },
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
  if (!Number.isFinite(dtMs) || dtMs <= 0) return 0;
  let damage = 0;
  const next: StatusEffect[] = [];
  for (const status of target.statuses) {
    const activeMs = Math.min(dtMs, status.remainingMs);
    if (status.id === "burn" || status.id === "poison") damage += status.magnitude * activeMs / 1000;
    const remainingMs = status.remainingMs - dtMs;
    if (remainingMs > 0) next.push({ ...status, remainingMs });
  }
  target.statuses = next;
  target.health = Math.max(0, target.health - damage);
  return damage;
}

export function addThreat(target: CombatTarget, userId: string, amount: number, now = Date.now()): void {
  if (!userId || !Number.isFinite(amount) || amount <= 0) return;
  const current = target.threat.get(userId);
  target.threat.set(userId, { userId, threat: (current?.threat ?? 0) + amount, lastHitAt: now });
  if (target.aiState !== "dead") target.aiState = "alert";
}

export function selectThreatTarget(target: CombatTarget, candidates: Iterable<{ userId: string; x: number; y: number }>): { userId: string; x: number; y: number } | null {
  let selected: { userId: string; x: number; y: number } | null = null;
  let bestThreat = -1;
  for (const candidate of candidates) {
    const entry = target.threat.get(candidate.userId);
    if (!entry || distance(target, candidate) > target.aggroRange * 1.5) continue;
    if (entry.threat > bestThreat) {
      bestThreat = entry.threat;
      selected = candidate;
    }
  }
  return selected;
}

export function tickCreatureAi(target: CombatTarget, candidates: Iterable<{ userId: string; x: number; y: number }>, now = Date.now(), dtMs = 250): CreatureAiResult {
  if (target.health <= 0) {
    target.aiState = "dead";
    return { targetUserId: null, state: "dead", moveX: 0, moveY: 0 };
  }
  const candidateList = [...candidates];
  let selected = selectThreatTarget(target, candidateList);
  if (!selected) {
    for (const candidate of candidateList) {
      if (distance(target, candidate) <= target.aggroRange) {
        selected = candidate;
        addThreat(target, candidate.userId, 1, now);
        break;
      }
    }
  }
  if (!selected) {
    target.aiState = "idle";
    target.stamina = Math.min(target.maxStamina, target.stamina + dtMs * 0.01);
    return { targetUserId: null, state: "idle", moveX: 0, moveY: 0 };
  }
  const d = distance(target, selected);
  if (d > target.attackRange) {
    target.aiState = "chase";
    const dx = selected.x - target.x;
    const dy = selected.y - target.y;
    const length = Math.hypot(dx, dy) || 1;
    return { targetUserId: selected.userId, state: "chase", moveX: dx / length, moveY: dy / length };
  }
  target.aiState = "attack";
  const species = CREATURE_STATS[target.species];
  const ability = species?.ability && now >= target.nextAbilityAt && d <= species.ability.range ? species.ability : undefined;
  if (ability) target.nextAbilityAt = now + ability.cooldownMs;
  return { targetUserId: selected.userId, state: "attack", moveX: 0, moveY: 0, ability };
}

export function createCombatTarget(id: string, species: string, x: number, y: number, level: number): CombatTarget {
  const stats = CREATURE_STATS[species] ?? { health: 50, defense: 3, element: "physical" as DamageType, speed: 1.5, attack: 8, aggroRange: 5, attackRange: 1.2 };
  const scaledHealth = stats.health + Math.max(0, level - 1) * 10;
  return {
    id, species, x, y, level, health: scaledHealth, maxHealth: scaledHealth,
    defense: stats.defense + Math.max(0, level - 1), element: stats.element,
    speed: stats.speed, attack: stats.attack + Math.max(0, level - 1) * 2,
    stamina: 100, maxStamina: 100, aiState: "idle", aggroRange: stats.aggroRange, attackRange: stats.attackRange,
    nextAbilityAt: 0, statuses: [], threat: new Map(),
  };
}

export function creatureAbilityDamage(target: CombatTarget, ability: CreatureAbility): DamageResult {
  const pseudoWeapon: WeaponSpec = {
    id: ability.id, damage: ability.damage, range: ability.range, cooldownMs: ability.cooldownMs,
    staminaCost: 0, damageType: ability.damageType, criticalChance: 0, criticalMultiplier: 1, status: ability.status,
  };
  return applyDamage(target, pseudoWeapon, 1);
}
