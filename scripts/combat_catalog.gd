class_name CombatCatalog
extends RefCounted

## Data-only combat catalog for Deepwatch. All public methods return fresh
## dictionaries/arrays so callers can safely add runtime state to them.

const ENEMY_ORDER: Array[String] = ["drone", "runner", "brute", "armored", "shielded"]

const ENEMIES := {
	"drone": {
		"display_name": "Breach Drone",
		"hp": 60.0,
		"speed": 1.30,
		"damage": 1,
		"reward": 9.0,
		"armor": 0.0,
		"shield": 0.0,
		"tags": ["standard"]
	},
	"runner": {
		"display_name": "Tunnel Runner",
		"hp": 43.0,
		"speed": 2.05,
		"damage": 1,
		"reward": 11.0,
		"armor": 0.0,
		"shield": 0.0,
		"tags": ["fast"]
	},
	"brute": {
		"display_name": "Siege Brute",
		"hp": 150.0,
		"speed": 0.82,
		"damage": 3,
		"reward": 22.0,
		"armor": 0.08,
		"shield": 0.0,
		"tags": ["heavy"]
	},
	"armored": {
		"display_name": "Bulwark Walker",
		"hp": 195.0,
		"speed": 0.72,
		"damage": 4,
		"reward": 29.0,
		"armor": 0.36,
		"shield": 0.0,
		"tags": ["heavy", "armored"]
	},
	"shielded": {
		"display_name": "Aegis Drone",
		"hp": 88.0,
		"speed": 1.12,
		"damage": 2,
		"reward": 25.0,
		"armor": 0.04,
		"shield": 82.0,
		"shield_regen": 4.0,
		"shield_regen_delay": 3.0,
		"tags": ["shielded"]
	}
}

const TURRET_TIERS := {
	1: {
		"display_name": "Sentry Mk I",
		"damage": 18.0,
		"range": 3.2,
		"cooldown": 0.72,
		"armor_pierce": 0.0,
		"effect": "none",
		"effect_strength": 0.0,
		"effect_duration": 0.0
	},
	2: {
		"display_name": "Sentry Mk II",
		"damage": 27.0,
		"range": 3.8,
		"cooldown": 0.58,
		"armor_pierce": 0.18,
		"effect": "armor_break",
		"effect_strength": 0.12,
		"effect_duration": 2.5
	},
	3: {
		"display_name": "Sentry Mk III",
		"damage": 39.0,
		"range": 4.5,
		"cooldown": 0.43,
		"armor_pierce": 0.32,
		"effect": "slow",
		"effect_strength": 0.28,
		"effect_duration": 1.6
	}
}

# Hand-authored introductions for the campaign's six waves. Later waves use a
# deterministic generator so endless or extended modes require no new data.
const CAMPAIGN_WAVES := {
	1: ["drone", "drone", "drone", "drone", "drone", "drone", "drone", "drone"],
	2: ["drone", "runner", "drone", "drone", "runner", "drone", "runner", "drone", "drone", "runner", "drone"],
	3: ["drone", "runner", "brute", "drone", "runner", "drone", "armored", "drone", "runner", "brute", "drone", "runner", "drone", "drone"],
	4: ["runner", "drone", "shielded", "drone", "brute", "runner", "drone", "armored", "runner", "drone", "shielded", "brute", "drone", "runner", "drone", "armored", "drone"],
	5: ["runner", "shielded", "drone", "brute", "armored", "runner", "drone", "shielded", "brute", "runner", "armored", "drone", "runner", "shielded", "brute", "drone", "armored", "runner", "drone", "brute"],
	6: ["shielded", "runner", "armored", "drone", "brute", "runner", "shielded", "armored", "drone", "brute", "runner", "armored", "shielded", "drone", "brute", "runner", "armored", "shielded", "brute", "runner", "drone", "armored", "shielded"]
}


static func get_enemy_ids() -> Array[String]:
	return ENEMY_ORDER.duplicate()


static func has_enemy(enemy_id: String) -> bool:
	return ENEMIES.has(enemy_id)


static func get_enemy_base(enemy_id: String) -> Dictionary:
	if not ENEMIES.has(enemy_id):
		return {}
	var result: Dictionary = ENEMIES[enemy_id].duplicate(true)
	result["id"] = enemy_id
	return result


static func get_enemy_stats(enemy_id: String, wave: int = 1) -> Dictionary:
	var stats := get_enemy_base(enemy_id)
	if stats.is_empty():
		return stats

	var safe_wave := maxi(1, wave)
	var steps := safe_wave - 1
	var hp_scale := pow(1.13, steps)
	var damage_scale := pow(1.075, steps)
	var reward_scale := 1.0 + steps * 0.09
	stats["wave"] = safe_wave
	stats["hp"] = snappedf(float(stats.hp) * hp_scale, 0.1)
	stats["speed"] = snappedf(float(stats.speed) * (1.0 + minf(0.30, steps * 0.025)), 0.001)
	stats["damage"] = maxi(1, int(round(float(stats.damage) * damage_scale)))
	stats["reward"] = snappedf(float(stats.reward) * reward_scale, 0.1)
	stats["armor"] = minf(0.65, float(stats.armor) + steps * 0.008)
	stats["shield"] = snappedf(float(stats.shield) * hp_scale, 0.1)
	if stats.has("shield_regen"):
		stats["shield_regen"] = snappedf(float(stats.shield_regen) * (1.0 + steps * 0.06), 0.1)
	return stats


static func get_turret_tier(level: int) -> Dictionary:
	if not TURRET_TIERS.has(level):
		return {}
	var result: Dictionary = TURRET_TIERS[level].duplicate(true)
	result["level"] = level
	return result


static func get_wave_composition(wave: int) -> Array[String]:
	var safe_wave := maxi(1, wave)
	if CAMPAIGN_WAVES.has(safe_wave):
		var campaign_result: Array[String] = []
		campaign_result.assign(CAMPAIGN_WAVES[safe_wave])
		return campaign_result

	var count := 5 + safe_wave * 3
	var result: Array[String] = []
	var rotation := safe_wave % 5
	var pattern: Array[String] = ["drone", "runner", "shielded", "brute", "armored"]
	for index in range(count):
		var enemy_id := pattern[(index * 2 + rotation) % pattern.size()]
		# Keep heavy units separated to avoid unfair burst damage at the vault.
		if index > 0 and enemy_id in ["brute", "armored"] and result[index - 1] in ["brute", "armored"]:
			enemy_id = "drone"
		result.append(enemy_id)
	return result


static func get_wave_enemy_id(wave: int, spawn_index: int) -> String:
	var composition := get_wave_composition(wave)
	if composition.is_empty():
		return "drone"
	return composition[posmod(spawn_index, composition.size())]


static func make_enemy_state(enemy_id: String, wave: int, path_index: int) -> Dictionary:
	var stats := get_enemy_stats(enemy_id, wave)
	if stats.is_empty():
		return {}
	return {
		"type": enemy_id,
		"display_name": stats.display_name,
		"hp": stats.hp,
		"max_hp": stats.hp,
		"speed": stats.speed,
		"damage": stats.damage,
		"reward": stats.reward,
		"armor": stats.armor,
		"shield": stats.shield,
		"max_shield": stats.shield,
		"shield_regen": stats.get("shield_regen", 0.0),
		"shield_regen_delay": stats.get("shield_regen_delay", 0.0),
		"path": maxi(0, path_index),
		"segment": 0,
		"hit": 0.0,
		"status_effects": []
	}


static func get_wave_spawn_plan(wave: int, path_count: int = 3) -> Array[Dictionary]:
	var composition := get_wave_composition(wave)
	var safe_path_count := maxi(1, path_count)
	var interval := maxf(0.30, 0.88 - maxi(1, wave) * 0.055)
	var result: Array[Dictionary] = []
	for index in range(composition.size()):
		result.append({
			"spawn_index": index,
			"path_index": index % safe_path_count,
			"spawn_time": snappedf(index * interval, 0.001),
			"enemy": make_enemy_state(composition[index], wave, index % safe_path_count)
		})
	return result


static func calculate_hit(raw_damage: float, armor: float, armor_pierce: float = 0.0) -> float:
	var effective_armor := clampf(armor - armor_pierce, 0.0, 0.85)
	return maxf(0.0, raw_damage) * (1.0 - effective_armor)

