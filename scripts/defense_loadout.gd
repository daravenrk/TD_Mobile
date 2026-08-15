class_name DefenseLoadout
extends RefCounted

## Data-only tower selection and progression rules. The methods deliberately
## mutate ordinary Dictionary pads so this can be introduced into the current
## prototype without first converting pads into custom Resources or Nodes.

const MAX_LEVEL := 3
const FAMILIES := ["ballistic", "arc", "cryo", "support"]

const FAMILY_DATA := {
	"ballistic": {
		"display_name": "Autocannon",
		"short_name": "GUN",
		"description": "Reliable kinetic fire with low power demand.",
		"color": Color("#ffad42"),
		"target_preference": "first",
		"build_cost": 45,
		"upgrade_costs": [0, 65, 95],
		"power_by_level": [0.0, 2.0, 3.0, 4.0],
		"stats_by_level": [
			{},
			{"damage": 9.0, "shots_per_second": 1.45, "range": 4.6, "pierce": 0.10},
			{"damage": 15.0, "shots_per_second": 1.65, "range": 5.0, "pierce": 0.16},
			{"damage": 23.0, "shots_per_second": 1.85, "range": 5.4, "pierce": 0.22}
		],
		"specializations": {
			"breacher": {
				"display_name": "Breacher Feed",
				"description": "Prioritizes armor and punches through plating.",
				"cost": 70,
				"target_preference": "highest_armor",
				"multipliers": {"damage": 1.20},
				"additions": {"pierce": 0.30}
			},
			"gunslinger": {
				"display_name": "Cycler Assembly",
				"description": "Faster tracking and sustained fire against runners.",
				"cost": 70,
				"target_preference": "fastest",
				"multipliers": {"shots_per_second": 1.35, "damage": 0.90},
				"additions": {"range": 0.4}
			}
		}
	},
	"arc": {
		"display_name": "Arc Coil",
		"short_name": "ARC",
		"description": "Chains energy through groups and disrupts shields.",
		"color": Color("#67d7ff"),
		"target_preference": "highest_shield",
		"build_cost": 60,
		"upgrade_costs": [0, 80, 115],
		"power_by_level": [0.0, 4.0, 6.0, 8.0],
		"stats_by_level": [
			{},
			{"damage": 7.0, "shots_per_second": 0.85, "range": 4.2, "pierce": 0.0, "chain_targets": 2.0, "shield_damage": 1.50},
			{"damage": 12.0, "shots_per_second": 0.95, "range": 4.6, "pierce": 0.0, "chain_targets": 3.0, "shield_damage": 1.65},
			{"damage": 18.0, "shots_per_second": 1.05, "range": 5.0, "pierce": 0.0, "chain_targets": 4.0, "shield_damage": 1.80}
		],
		"specializations": {
			"storm": {
				"display_name": "Storm Lattice",
				"description": "Adds chain jumps for dense incursions.",
				"cost": 85,
				"target_preference": "largest_cluster",
				"multipliers": {"damage": 0.90},
				"additions": {"chain_targets": 2.0}
			},
			"disruptor": {
				"display_name": "Aegis Disruptor",
				"description": "Overloads shielded contacts and briefly stuns them.",
				"cost": 85,
				"target_preference": "highest_shield",
				"multipliers": {"shield_damage": 1.45},
				"additions": {"stun_seconds": 0.35}
			}
		}
	},
	"cryo": {
		"display_name": "Cryo Projector",
		"short_name": "CRYO",
		"description": "Controls lanes with stacking movement slow.",
		"color": Color("#9ff4ff"),
		"target_preference": "fastest",
		"build_cost": 55,
		"upgrade_costs": [0, 75, 105],
		"power_by_level": [0.0, 3.0, 5.0, 7.0],
		"stats_by_level": [
			{},
			{"damage": 4.0, "shots_per_second": 1.10, "range": 4.0, "pierce": 0.0, "slow_fraction": 0.22, "slow_seconds": 1.5},
			{"damage": 7.0, "shots_per_second": 1.20, "range": 4.5, "pierce": 0.0, "slow_fraction": 0.30, "slow_seconds": 1.8},
			{"damage": 11.0, "shots_per_second": 1.30, "range": 5.0, "pierce": 0.0, "slow_fraction": 0.38, "slow_seconds": 2.1}
		],
		"specializations": {
			"deep_freeze": {
				"display_name": "Deep Freeze",
				"description": "Stronger slows hold the fastest target in place.",
				"cost": 80,
				"target_preference": "fastest",
				"multipliers": {"slow_fraction": 1.30, "slow_seconds": 1.25},
				"additions": {}
			},
			"shatter": {
				"display_name": "Shatter Core",
				"description": "Marks chilled enemies for amplified kinetic damage.",
				"cost": 80,
				"target_preference": "most_slowed",
				"multipliers": {"damage": 1.20},
				"additions": {"shatter_bonus": 0.30}
			}
		}
	},
	"support": {
		"display_name": "Field Station",
		"short_name": "SUP",
		"description": "Repairs defenses and strengthens nearby infrastructure.",
		"color": Color("#7deda2"),
		"target_preference": "most_damaged_structure",
		"build_cost": 50,
		"upgrade_costs": [0, 70, 100],
		"power_by_level": [0.0, 2.0, 3.0, 5.0],
		"stats_by_level": [
			{},
			{"damage": 0.0, "shots_per_second": 0.0, "range": 3.8, "pierce": 0.0, "repair_per_second": 2.0, "sensor_bonus": 1.0},
			{"damage": 0.0, "shots_per_second": 0.0, "range": 4.4, "pierce": 0.0, "repair_per_second": 3.2, "sensor_bonus": 1.5},
			{"damage": 0.0, "shots_per_second": 0.0, "range": 5.0, "pierce": 0.0, "repair_per_second": 4.6, "sensor_bonus": 2.0}
		],
		"specializations": {
			"fabricator": {
				"display_name": "Repair Fabricator",
				"description": "Concentrates on rapid structural recovery.",
				"cost": 75,
				"target_preference": "most_damaged_structure",
				"multipliers": {"repair_per_second": 1.60},
				"additions": {}
			},
			"relay": {
				"display_name": "Sensor Relay",
				"description": "Extends local intel and improves nearby tower range.",
				"cost": 75,
				"target_preference": "none",
				"multipliers": {"repair_per_second": 0.75},
				"additions": {"sensor_bonus": 2.5, "ally_range_bonus": 0.65}
			}
		}
	}
}


func initialize_pad(pad: Dictionary, family: String = "ballistic") -> Dictionary:
	if not is_valid_family(family):
		return _failure("Unknown tower family: %s" % family)
	if not pad.has("level"):
		pad["level"] = 0
	pad["level"] = clampi(int(pad.level), 0, MAX_LEVEL)
	if not pad.has("tower_family") or not is_valid_family(str(pad.tower_family)):
		pad["tower_family"] = family
	if not pad.has("specialization"):
		pad["specialization"] = ""
	if not pad.has("progress"):
		pad["progress"] = 0.0
	if not pad.has("cooldown"):
		pad["cooldown"] = 0.0
	return {"ok": true, "pad": pad}


func assign_family(pad: Dictionary, family: String) -> Dictionary:
	if not is_valid_family(family):
		return _failure("Unknown tower family: %s" % family)
	initialize_pad(pad, family)
	if int(pad.level) > 0:
		return _failure("Built towers cannot change family")
	pad["tower_family"] = family
	pad["specialization"] = ""
	# Choosing a blueprint is free. The build cost is charged by upgrade() when
	# the selected pad advances from level zero to MK-1.
	return {"ok": true, "cost": 0, "build_cost": get_build_cost(family), "pad": pad}


func upgrade(pad: Dictionary, available_credits: float) -> Dictionary:
	var family := str(pad.get("tower_family", "ballistic"))
	var initialized := initialize_pad(pad, family)
	if not initialized.ok:
		return initialized
	var level := int(pad.level)
	if level >= MAX_LEVEL:
		return _failure("Tower is already at maximum level")
	var cost := get_upgrade_cost(family, level + 1)
	var validation := validate_cost(available_credits, cost)
	if not validation.ok:
		return validation
	pad["level"] = level + 1
	pad["progress"] = 0.0
	return {"ok": true, "cost": cost, "credits_remaining": available_credits - cost, "new_level": level + 1, "pad": pad}


func specialize(pad: Dictionary, branch: String, available_credits: float) -> Dictionary:
	var family := str(pad.get("tower_family", "ballistic"))
	var initialized := initialize_pad(pad, family)
	if not initialized.ok:
		return initialized
	if int(pad.level) < 2:
		return _failure("Specializations require tower level 2")
	if str(pad.specialization) != "":
		return _failure("Tower already has a specialization")
	var branches: Dictionary = FAMILY_DATA[family].specializations
	if not branches.has(branch):
		return _failure("Unknown specialization for %s: %s" % [family, branch])
	var cost := int(branches[branch].cost)
	var validation := validate_cost(available_credits, cost)
	if not validation.ok:
		return validation
	pad["specialization"] = branch
	return {"ok": true, "cost": cost, "credits_remaining": available_credits - cost, "pad": pad}


func get_effective_stats(pad: Dictionary, damage_modifier: float = 1.0, pierce_modifier: float = 0.0) -> Dictionary:
	var family := str(pad.get("tower_family", "ballistic"))
	if not is_valid_family(family):
		return {}
	var level := clampi(int(pad.get("level", 0)), 0, MAX_LEVEL)
	var family_data: Dictionary = FAMILY_DATA[family]
	var stats: Dictionary = family_data.stats_by_level[level].duplicate(true)
	stats["family"] = family
	stats["level"] = level
	stats["power_cost"] = float(family_data.power_by_level[level])
	stats["target_preference"] = family_data.target_preference
	stats["specialization"] = str(pad.get("specialization", ""))

	var branch := str(stats.specialization)
	if branch != "" and family_data.specializations.has(branch):
		var branch_data: Dictionary = family_data.specializations[branch]
		for stat_name in branch_data.multipliers:
			stats[stat_name] = float(stats.get(stat_name, 0.0)) * float(branch_data.multipliers[stat_name])
		for stat_name in branch_data.additions:
			stats[stat_name] = float(stats.get(stat_name, 0.0)) + float(branch_data.additions[stat_name])
		stats["target_preference"] = branch_data.target_preference

	stats["damage"] = float(stats.get("damage", 0.0)) * maxf(damage_modifier, 0.0)
	stats["pierce"] = clampf(float(stats.get("pierce", 0.0)) + pierce_modifier, 0.0, 1.0)
	return stats


func get_family_display_data(family: String) -> Dictionary:
	if not is_valid_family(family):
		return {}
	var data: Dictionary = FAMILY_DATA[family]
	var branches: Array = []
	for branch_id in data.specializations:
		var branch: Dictionary = data.specializations[branch_id]
		branches.append({
			"id": branch_id,
			"display_name": branch.display_name,
			"description": branch.description,
			"cost": branch.cost
		})
	return {
		"id": family,
		"display_name": data.display_name,
		"short_name": data.short_name,
		"description": data.description,
		"color": data.color,
		"build_cost": data.build_cost,
		"target_preference": data.target_preference,
		"specializations": branches
	}


func get_pad_display_data(pad: Dictionary) -> Dictionary:
	var family := str(pad.get("tower_family", "ballistic"))
	if not is_valid_family(family):
		return {}
	var family_display := get_family_display_data(family)
	var level := clampi(int(pad.get("level", 0)), 0, MAX_LEVEL)
	var branch := str(pad.get("specialization", ""))
	var specialization_name := ""
	if branch != "" and FAMILY_DATA[family].specializations.has(branch):
		specialization_name = FAMILY_DATA[family].specializations[branch].display_name
	return {
		"family": family,
		"name": family_display.display_name,
		"short_name": family_display.short_name,
		"color": family_display.color,
		"level": level,
		"level_label": "UNBUILT" if level == 0 else "MK-%d" % level,
		"specialization": branch,
		"specialization_name": specialization_name,
		"stats": get_effective_stats(pad),
		"next_upgrade_cost": get_upgrade_cost(family, level + 1) if level < MAX_LEVEL else -1
	}


func get_build_cost(family: String) -> int:
	return int(FAMILY_DATA[family].build_cost) if is_valid_family(family) else -1


func get_upgrade_cost(family: String, target_level: int) -> int:
	if not is_valid_family(family) or target_level < 1 or target_level > MAX_LEVEL:
		return -1
	if target_level == 1:
		return get_build_cost(family)
	return int(FAMILY_DATA[family].upgrade_costs[target_level - 1])


func get_specialization_ids(family: String) -> Array:
	if not is_valid_family(family):
		return []
	return FAMILY_DATA[family].specializations.keys()


func validate_cost(available_credits: float, cost: float) -> Dictionary:
	if cost < 0.0:
		return _failure("Invalid purchase cost")
	if available_credits < cost:
		return {"ok": false, "reason": "Insufficient credits", "cost": cost, "shortfall": cost - available_credits}
	return {"ok": true, "cost": cost, "credits_remaining": available_credits - cost}


func is_valid_family(family: String) -> bool:
	return FAMILY_DATA.has(family)


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
