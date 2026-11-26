class_name BreedingRecombinator
extends RefCounted
## Mendelian IV inheritance for camp breeding. Mutation chance is published (5%), never hidden.

const IV_MIN := 0
const IV_MAX := 31
const MUTATION_CHANCE := 0.05
const GAUSSIAN_MEAN := 0.5
const GAUSSIAN_SIGMA := 1.8
const STEAM_HYBRID_TRAIT := "air_steam_hybrid"

static func inherit_iv(parent_a: int, parent_b: int, rng: RandomNumberGenerator) -> int:
	var midpoint := int(floor((float(parent_a) + float(parent_b)) / 2.0))
	var delta := rng.randfn(GAUSSIAN_MEAN, GAUSSIAN_SIGMA)
	return clampi(int(floor(float(midpoint) + delta)), IV_MIN, IV_MAX)

static func inherit_ivs(parent_a: Dictionary, parent_b: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var result := {}
	for key in parent_a.keys():
		result[key] = inherit_iv(int(parent_a[key]), int(parent_b.get(key, parent_a[key])), rng)
	return result

static func roll_mutation(element_a: String, element_b: String, rng: RandomNumberGenerator) -> String:
	if rng.randf() >= MUTATION_CHANCE:
		return ""
	var pair := PackedStringArray([element_a.to_lower(), element_b.to_lower()])
	pair.sort()
	if pair[0] == "fire" and pair[1] == "water":
		return STEAM_HYBRID_TRAIT
	return "rare_trait"

static func can_breed(current_population: int, capacity: int) -> bool:
	if current_population < 0 or capacity < 0:
		return false
	return current_population < capacity
