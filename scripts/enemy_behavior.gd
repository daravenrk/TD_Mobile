class_name EnemyBehavior
extends RefCounted

## Infrastructure-aware enemy intent and attack rules.
##
## Every helper operates on the dictionary states already used by the game.
## Attack results describe the requested effect instead of depending on a scene
## or PowerNetwork instance: callers can route `damage_facility` results to
## PowerNetwork.damage_facility(), and `damage_vault` results to base health.

const STRATEGIC_TYPES := ["generator", "substation", "sensor", "armory", "blast_control"]

const BEHAVIORS := {
	"default": {
		"intent": "breach_vault",
		"target_mode": "vault",
		"attack_interval": 1.0,
		"attack_damage": 1.0,
		"telegraph_duration": 0.35,
		"telegraph_label": "Vault strike"
	},
	"sapper": {
		"intent": "sabotage_infrastructure",
		"target_mode": "strategic_facility",
		"attack_interval": 1.45,
		"attack_damage": 24.0,
		"telegraph_duration": 0.65,
		"telegraph_label": "Sabotaging"
	},
	"stalker": {
		"intent": "blind_sensors",
		"target_mode": "sensor_then_vault",
		"attack_interval": 1.15,
		"attack_damage": 12.0,
		"telegraph_duration": 0.28,
		"telegraph_label": "Sensor strike",
		"stealthed_outside_sensor": true
	},
	"burrower": {
		"intent": "open_breach",
		"target_mode": "vault",
		"attack_interval": 2.4,
		"attack_damage": 3.0,
		"telegraph_duration": 1.0,
		"telegraph_label": "Tunneling",
		"can_create_breach": true
	}
}

const FACILITY_PRIORITY := {
	"generator": 180.0,
	"substation": 155.0,
	"sensor": 130.0,
	"blast_control": 120.0,
	"armory": 105.0
}


static func get_behavior_profile(enemy_type: String) -> Dictionary:
	var behavior_id := enemy_type if BEHAVIORS.has(enemy_type) else "default"
	var result: Dictionary = BEHAVIORS[behavior_id].duplicate(true)
	result["behavior_id"] = behavior_id
	return result


static func choose_archetype(base_enemy_type: String, sector: int, spawn_index: int) -> String:
	# Introduce Sappers predictably once infrastructure is established. Keeping
	# the replacement schedule deterministic makes authored incursions testable.
	if sector >= 2 and posmod(spawn_index + sector * 2, 7) == 0:
		return "sapper"
	if sector >= 3 and posmod(spawn_index + sector, 13) == 0:
		return "stalker"
	return base_enemy_type


static func initialize_enemy(enemy: Dictionary, enemy_type: String = "") -> Dictionary:
	var resolved_type := enemy_type
	if resolved_type.is_empty():
		resolved_type = str(enemy.get("type", "drone"))
	var profile := get_behavior_profile(resolved_type)
	enemy["behavior_id"] = profile.behavior_id
	enemy["intent"] = profile.intent
	enemy["target_kind"] = "none"
	enemy["target_id"] = ""
	enemy["target_position"] = enemy.get("pos", Vector2.ZERO)
	enemy["attack_remaining"] = float(profile.attack_interval)
	enemy["attack_interval"] = float(profile.attack_interval)
	enemy["attack_damage"] = float(enemy.get("sabotage_damage", profile.attack_damage))
	enemy["telegraph_duration"] = float(profile.telegraph_duration)
	enemy["telegraph_label"] = str(profile.telegraph_label)
	if profile.has("stealthed_outside_sensor"):
		enemy["stealthed_outside_sensor"] = bool(profile.stealthed_outside_sensor)
	if profile.has("can_create_breach"):
		enemy["can_create_breach"] = bool(profile.can_create_breach)
	return enemy


static func choose_target(enemy: Dictionary, vault: Dictionary, facilities) -> Dictionary:
	var profile := get_behavior_profile(str(enemy.get("behavior_id", enemy.get("type", "default"))))
	var vault_target := _make_vault_target(vault)
	if profile.target_mode == "vault":
		return vault_target

	var facility_list := _normalize_facilities(facilities)
	var enemy_position := _as_vector2(enemy.get("pos", Vector2.ZERO))
	var best_target: Dictionary = {}
	var best_score := -INF
	for facility in facility_list:
		if not _is_valid_facility_target(facility):
			continue
		if profile.target_mode == "sensor_then_vault" and str(facility.get("type", "")) != "sensor":
			continue
		var score := score_facility_target(enemy_position, facility)
		if score > best_score or (is_equal_approx(score, best_score) and str(facility.get("id", "")) < str(best_target.get("id", "~"))):
			best_score = score
			best_target = _make_facility_target(facility, score)
	if not best_target.is_empty():
		return best_target
	return vault_target


static func score_facility_target(enemy_position: Vector2, facility: Dictionary) -> float:
	if not _is_valid_facility_target(facility):
		return -INF
	var facility_type := str(facility.get("type", ""))
	var score := float(FACILITY_PRIORITY.get(facility_type, 0.0))
	var hp := maxf(0.0, float(facility.get("hp", 0.0)))
	var max_hp := maxf(1.0, float(facility.get("max_hp", hp)))
	if bool(facility.get("online", false)):
		score += 70.0
	if hp < max_hp:
		score += (1.0 - hp / max_hp) * 25.0
	score -= enemy_position.distance_to(_as_vector2(facility.get("position", Vector2.ZERO))) * 4.0
	return score


static func assign_target(enemy: Dictionary, vault: Dictionary, facilities) -> Dictionary:
	var target := choose_target(enemy, vault, facilities)
	enemy["target_kind"] = str(target.get("kind", "vault"))
	enemy["target_id"] = str(target.get("id", "vault"))
	enemy["target_position"] = target.get("position", Vector2.ZERO)
	enemy["target_name"] = str(target.get("name", "Command Vault"))
	if enemy.target_kind == "facility":
		enemy["intent"] = "sabotage_infrastructure"
	else:
		enemy["intent"] = "breach_vault"
	return target


static func update_attack(enemy: Dictionary, delta: float, target_in_range: bool) -> Dictionary:
	var profile := get_behavior_profile(str(enemy.get("behavior_id", enemy.get("type", "default"))))
	var interval := maxf(0.05, float(enemy.get("attack_interval", profile.attack_interval)))
	if not enemy.has("attack_remaining"):
		enemy["attack_remaining"] = interval
	if not target_in_range:
		return {
			"event": "approaching",
			"attack_ready": false,
			"target_kind": str(enemy.get("target_kind", "vault")),
			"target_id": str(enemy.get("target_id", "vault")),
			"telegraph": get_telegraph_data(enemy)
		}

	enemy.attack_remaining = float(enemy.attack_remaining) - maxf(0.0, delta)
	if float(enemy.attack_remaining) > 0.0:
		return {
			"event": "telegraph" if get_telegraph_data(enemy).visible else "winding_up",
			"attack_ready": false,
			"target_kind": str(enemy.get("target_kind", "vault")),
			"target_id": str(enemy.get("target_id", "vault")),
			"telegraph": get_telegraph_data(enemy)
		}

	# Preserve overshoot so variable frame rates do not slow the attack cadence.
	enemy.attack_remaining = interval + fmod(float(enemy.attack_remaining), interval)
	if float(enemy.attack_remaining) <= 0.0:
		enemy.attack_remaining += interval
	var target_kind := str(enemy.get("target_kind", "vault"))
	var action := "damage_facility" if target_kind == "facility" else "damage_vault"
	if bool(enemy.get("can_create_breach", false)) and target_kind == "vault":
		action = "create_breach"
	return {
		"event": "attack",
		"attack_ready": true,
		"action": action,
		"damage": maxf(0.0, float(enemy.get("attack_damage", profile.attack_damage))),
		"target_kind": target_kind,
		"target_id": str(enemy.get("target_id", "vault")),
		"source_type": str(enemy.get("type", profile.behavior_id)),
		"intent": str(enemy.get("intent", profile.intent)),
		"telegraph": get_telegraph_data(enemy)
	}


static func get_telegraph_data(enemy: Dictionary) -> Dictionary:
	var remaining := maxf(0.0, float(enemy.get("attack_remaining", 0.0)))
	var duration := maxf(0.0, float(enemy.get("telegraph_duration", 0.35)))
	var visible := duration > 0.0 and remaining <= duration
	var target_name := str(enemy.get("target_name", "Command Vault"))
	var label := str(enemy.get("telegraph_label", "Attacking"))
	return {
		"visible": visible,
		"label": "%s: %s" % [label, target_name],
		"countdown": remaining,
		"progress": clampf(1.0 - remaining / maxf(duration, 0.001), 0.0, 1.0) if visible else 0.0,
		"severity": "critical" if str(enemy.get("target_kind", "vault")) == "vault" else "warning",
		"target_id": str(enemy.get("target_id", "vault")),
		"intent": str(enemy.get("intent", "breach_vault"))
	}


static func _normalize_facilities(facilities) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if facilities is Dictionary:
		for facility_id in facilities:
			var value = facilities[facility_id]
			if value is Dictionary:
				var facility: Dictionary = value
				var copy := facility.duplicate(true)
				if str(copy.get("id", "")).is_empty():
					copy["id"] = str(facility_id)
				result.append(copy)
	elif facilities is Array:
		for value in facilities:
			if value is Dictionary:
				result.append(value)
	return result


static func _is_valid_facility_target(facility: Dictionary) -> bool:
	var facility_type := str(facility.get("type", ""))
	var hp := float(facility.get("hp", 0.0))
	var max_hp := maxf(1.0, float(facility.get("max_hp", hp)))
	return (
		facility_type in STRATEGIC_TYPES
		and hp > 0.0
		and (bool(facility.get("online", false)) or hp < max_hp)
		and (facility.get("position", null) is Vector2 or facility.get("position", null) is Vector2i)
	)


static func _make_facility_target(facility: Dictionary, score: float) -> Dictionary:
	return {
		"kind": "facility",
		"id": str(facility.get("id", "facility")),
		"name": str(facility.get("name", str(facility.get("type", "facility")).capitalize())),
		"facility_type": str(facility.get("type", "")),
		"position": _as_vector2(facility.get("position", Vector2.ZERO)),
		"score": score
	}


static func _make_vault_target(vault: Dictionary) -> Dictionary:
	return {
		"kind": "vault",
		"id": str(vault.get("id", "vault")),
		"name": str(vault.get("name", "Command Vault")),
		"position": _as_vector2(vault.get("position", vault.get("pos", Vector2.ZERO))),
		"score": 0.0
	}


static func _as_vector2(value) -> Vector2:
	if value is Vector2:
		return value
	if value is Vector2i:
		return Vector2(value)
	return Vector2.ZERO
