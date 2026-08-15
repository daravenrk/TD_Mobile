class_name EngineerAbilities
extends RefCounted

## Cooldown and effect rules for the engineer's active abilities.
##
## This class deliberately has no scene-tree dependencies. The game owns input,
## visuals, enemy removal, rewards, and assignment of the returned resource
## values. This keeps the rules reusable by gameplay code and headless tests.

const DEFAULT_SHOCK_COOLDOWN := 8.0
const DEFAULT_SHOCK_RADIUS := 3.25
const DEFAULT_SHOCK_DAMAGE := 36.0
const DEFAULT_REPAIR_COOLDOWN := 18.0
const DEFAULT_REPAIR_AMOUNT := 5
const DEFAULT_REPAIR_CREDIT_PER_POINT := 14.0

var shock_cooldown: float
var shock_radius: float
var shock_damage: float
var repair_cooldown: float
var repair_amount: int
var repair_credit_per_point: float

var _shock_remaining := 0.0
var _repair_remaining := 0.0


func _init(
	configured_shock_cooldown: float = DEFAULT_SHOCK_COOLDOWN,
	configured_shock_radius: float = DEFAULT_SHOCK_RADIUS,
	configured_shock_damage: float = DEFAULT_SHOCK_DAMAGE,
	configured_repair_cooldown: float = DEFAULT_REPAIR_COOLDOWN,
	configured_repair_amount: int = DEFAULT_REPAIR_AMOUNT,
	configured_repair_credit_per_point: float = DEFAULT_REPAIR_CREDIT_PER_POINT
) -> void:
	shock_cooldown = maxf(0.01, configured_shock_cooldown)
	shock_radius = maxf(0.0, configured_shock_radius)
	shock_damage = maxf(0.0, configured_shock_damage)
	repair_cooldown = maxf(0.01, configured_repair_cooldown)
	repair_amount = maxi(1, configured_repair_amount)
	repair_credit_per_point = maxf(0.01, configured_repair_credit_per_point)


func update_cooldowns(delta: float) -> void:
	var elapsed := maxf(0.0, delta)
	_shock_remaining = maxf(0.0, _shock_remaining - elapsed)
	_repair_remaining = maxf(0.0, _repair_remaining - elapsed)


func can_activate_shock() -> bool:
	return is_zero_approx(_shock_remaining)


func activate_shock(origin: Vector2, enemies: Array) -> Dictionary:
	if not can_activate_shock():
		return _failure("shock_pulse", "cooldown", _shock_remaining)

	_shock_remaining = shock_cooldown
	var affected: Array = []
	var defeated: Array = []
	var total_damage := 0.0
	for enemy_variant in enemies:
		if not enemy_variant is Dictionary:
			continue
		var enemy: Dictionary = enemy_variant
		var enemy_position = enemy.get("pos")
		if not enemy_position is Vector2 or origin.distance_to(enemy_position) > shock_radius:
			continue
		var old_health := maxf(0.0, float(enemy.get("hp", 0.0)))
		var new_health := maxf(0.0, old_health - shock_damage)
		enemy["hp"] = new_health
		enemy["hit"] = maxf(float(enemy.get("hit", 0.0)), 0.18)
		total_damage += old_health - new_health
		affected.append(enemy)
		if old_health > 0.0 and is_zero_approx(new_health):
			defeated.append(enemy)

	return {
		"activated": true,
		"ability": "shock_pulse",
		"affected": affected,
		"defeated": defeated,
		"damage_dealt": total_damage,
		"cooldown_remaining": _shock_remaining
	}


func can_activate_emergency_repair(current_health: int, max_health: int, available_credits: float) -> bool:
	return (
		is_zero_approx(_repair_remaining)
		and current_health < max_health
		and available_credits + 0.0001 >= repair_credit_per_point
	)


func activate_emergency_repair(current_health: int, max_health: int, available_credits: float) -> Dictionary:
	if not is_zero_approx(_repair_remaining):
		return _repair_failure("cooldown", current_health, available_credits)
	if current_health >= max_health:
		return _repair_failure("vault_full", current_health, available_credits)
	if available_credits + 0.0001 < repair_credit_per_point:
		return _repair_failure("insufficient_credits", current_health, available_credits)

	var missing_health := maxi(0, max_health - current_health)
	var affordable_points := floori(available_credits / repair_credit_per_point)
	var repaired := mini(repair_amount, mini(missing_health, affordable_points))
	var cost := repaired * repair_credit_per_point
	_repair_remaining = repair_cooldown
	return {
		"activated": true,
		"ability": "emergency_repair",
		"repaired": repaired,
		"cost": cost,
		"base_health": current_health + repaired,
		"credits": maxf(0.0, available_credits - cost),
		"cooldown_remaining": _repair_remaining
	}


func reset() -> void:
	_shock_remaining = 0.0
	_repair_remaining = 0.0


func get_shock_cooldown_remaining() -> float:
	return _shock_remaining


func get_repair_cooldown_remaining() -> float:
	return _repair_remaining


func get_shock_ready_ratio() -> float:
	return clampf(1.0 - _shock_remaining / shock_cooldown, 0.0, 1.0)


func get_repair_ready_ratio() -> float:
	return clampf(1.0 - _repair_remaining / repair_cooldown, 0.0, 1.0)


func get_hud_state() -> Dictionary:
	return {
		"shock_pulse": {
			"ready": can_activate_shock(),
			"ready_ratio": get_shock_ready_ratio(),
			"cooldown_remaining": _shock_remaining,
			"cooldown_duration": shock_cooldown,
			"radius": shock_radius,
			"damage": shock_damage
		},
		"emergency_repair": {
			"cooldown_ready": is_zero_approx(_repair_remaining),
			"ready_ratio": get_repair_ready_ratio(),
			"cooldown_remaining": _repair_remaining,
			"cooldown_duration": repair_cooldown,
			"maximum_repair": repair_amount,
			"credit_per_point": repair_credit_per_point
		}
	}


func _failure(ability: String, reason: String, cooldown_remaining: float) -> Dictionary:
	return {
		"activated": false,
		"ability": ability,
		"reason": reason,
		"cooldown_remaining": cooldown_remaining
	}


func _repair_failure(reason: String, current_health: int, available_credits: float) -> Dictionary:
	var result := _failure("emergency_repair", reason, _repair_remaining)
	result["repaired"] = 0
	result["cost"] = 0.0
	result["base_health"] = current_health
	result["credits"] = available_credits
	return result
