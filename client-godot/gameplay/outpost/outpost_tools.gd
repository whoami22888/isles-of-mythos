extends RefCounted
## Chapter 2 gathering: tool tiers (hands -> stone -> iron, per axe/pick),
## durability, a gathering skill that raises yield and crit chance, and the
## random rolls (crits, rare drops). Pure logic; state lives in st.ext["tools"].

const TIERS := ["hands", "stone", "iron"]
## tier -> [hits multiplier, yield multiplier, durability]
const TIER_STATS := {"hands": [1.6, 0.6, 0], "stone": [1.0, 1.0, 60], "iron": [0.6, 1.5, 160]}
const RECIPES := {
	"stone_axe": {"title": "Stone Axe", "slot": "axe", "tier": "stone", "cost": {"wood": 6, "stone": 4, "flint": 2}},
	"stone_pick": {"title": "Stone Pick", "slot": "pick", "tier": "stone", "cost": {"wood": 6, "stone": 6, "flint": 2}},
	"iron_axe": {"title": "Iron Axe", "slot": "axe", "tier": "iron", "cost": {"wood": 10, "iron": 8}, "building": "forge"},
	"iron_pick": {"title": "Iron Pick", "slot": "pick", "tier": "iron", "cost": {"wood": 10, "iron": 10}, "building": "forge"},
}

var st
var t: Dictionary = {}   # {axe: tier, pick: tier, dur: {axe: n, pick: n}, xp: n}


func setup(state) -> void:
	st = state
	t = st.ext.get("tools", {})
	if t.is_empty():
		t = {"axe": "hands", "pick": "hands", "dur": {"axe": 0, "pick": 0}, "xp": 0}
	st.ext["tools"] = t


func tier(slot: String) -> String:
	if slot == "" or slot == "hands":
		return "hands"
	return str(t.get(slot, "hands"))


func skill_level() -> int:
	return mini(1 + int(sqrt(float(t["xp"]) / 12.0)), 20)


func crit_chance() -> float:
	return 0.05 + 0.015 * (skill_level() - 1)


func hits_needed(row: Dictionary) -> int:
	var slot := str(row.get("tool", "axe"))
	return maxi(1, int(round(float(row.get("hits", 4)) * float(TIER_STATS[tier(slot)][0]))))


## Why `row` can't be worked with current tools ("" = ok).
func block(row: Dictionary) -> String:
	var need := str(row.get("min_tier", "hands"))
	var slot := str(row.get("tool", "axe"))
	if TIERS.find(tier(slot)) < TIERS.find(need):
		return "Needs a %s %s" % [need, slot]
	return ""


func craft_block(id: String) -> String:
	var r: Dictionary = RECIPES.get(id, {})
	if r.is_empty():
		return "Unknown"
	if TIERS.find(tier(r["slot"])) >= TIERS.find(r["tier"]) and int(t["dur"].get(r["slot"], 0)) > 0:
		return "Have one"
	if r.has("building") and st.level_of(r["building"]) == 0:
		return "Needs a " + st.title(r["building"])
	for k in r["cost"].keys():
		if st.count(k) < int(r["cost"][k]):
			return "Need " + st.cost_text(st.missing(r["cost"]))
	return ""


func craft(id: String) -> String:
	var why := craft_block(id)
	if why != "":
		return why
	var r: Dictionary = RECIPES[id]
	for k in r["cost"].keys():
		st.add_item(k, -int(r["cost"][k]))
	t[r["slot"]] = r["tier"]
	t["dur"][r["slot"]] = int(TIER_STATS[r["tier"]][2])
	return ""


## One strike's roll on node `row`. finish = the node's last hit.
## Returns {gain: {}, crit: bool, rare: {}, broke: String}.
func roll(row: Dictionary, finish: bool, rng: RandomNumberGenerator) -> Dictionary:
	var slot := str(row.get("tool", "axe"))
	var tr := tier(slot)
	var mult := float(TIER_STATS[tr][1]) * (1.0 + 0.03 * (skill_level() - 1))
	var crit := rng.randf() < crit_chance()
	if crit:
		mult *= 2.0
	var gain := {}
	var base: Dictionary = row.get("yield", {})
	for k in base.keys():
		gain[k] = maxi(1, int(round(float(base[k]) * mult)))
	if finish:
		var fin: Dictionary = row.get("finish", {})
		for k in fin.keys():
			gain[k] = int(gain.get(k, 0)) + maxi(1, int(round(float(fin[k]) * mult)))
	var rare := {}
	var rr: Dictionary = row.get("rare", {})
	for k in rr.keys():
		if rng.randf() < float(rr[k]) * (1.0 + 0.05 * skill_level()):
			rare[k] = 1
	if rng.randf() < 0.006:
		rare["map_fragment"] = 1
	t["xp"] = int(t["xp"]) + (2 if crit else 1)
	var broke := ""
	if tr != "hands" and slot in ["axe", "pick"]:
		t["dur"][slot] = int(t["dur"].get(slot, 0)) - 1
		if int(t["dur"][slot]) <= 0:
			broke = "%s %s" % [tr.capitalize(), slot]
			t[slot] = "hands"
	return {"gain": gain, "crit": crit, "rare": rare, "broke": broke}
