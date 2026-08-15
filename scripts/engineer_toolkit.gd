class_name EngineerToolkit
extends RefCounted

## Data-only engineer health and deployable-barricade simulation.
## Grid collections accepted by placement methods may be Arrays of Vector2i or
## Dictionaries keyed by Vector2i (a false dictionary value is treated as absent).

signal event_emitted(event: Dictionary)

const DEFAULT_CONFIG := {
	"max_health": 100.0,
	"revive_health_fraction": 0.40,
	"downed_recovery_time": 6.0,
	"damage_invulnerability": 0.35,
	"max_barricade_charges": 3,
	"barricade_cooldown": 1.0,
	"barricade_max_hp": 120.0,
	"barricade_slow_multiplier": 0.35,
	"barricade_slow_duration": 0.30,
	"dismantle_refund_threshold": 0.50
}

var config: Dictionary = {}
var health: float = 0.0
var downed: bool = false
var recovery_remaining: float = 0.0
var invulnerability_remaining: float = 0.0
var barricade_charges: int = 0
var barricade_cooldown_remaining: float = 0.0
var barricades: Dictionary = {}
var revision: int = 0

var _next_barricade_id: int = 1
var _events: Array[Dictionary] = []


func _init(initial_config: Dictionary = {}) -> void:
	reset(initial_config)


func reset(overrides: Dictionary = {}) -> Dictionary:
	config = DEFAULT_CONFIG.duplicate(true)
	config.merge(overrides, true)
	config.max_health = maxf(1.0, float(config.max_health))
	config.revive_health_fraction = clampf(float(config.revive_health_fraction), 0.01, 1.0)
	config.downed_recovery_time = maxf(0.0, float(config.downed_recovery_time))
	config.damage_invulnerability = maxf(0.0, float(config.damage_invulnerability))
	config.max_barricade_charges = maxi(0, int(config.max_barricade_charges))
	config.barricade_cooldown = maxf(0.0, float(config.barricade_cooldown))
	config.barricade_max_hp = maxf(1.0, float(config.barricade_max_hp))
	config.barricade_slow_multiplier = clampf(float(config.barricade_slow_multiplier), 0.0, 1.0)
	config.barricade_slow_duration = maxf(0.0, float(config.barricade_slow_duration))
	config.dismantle_refund_threshold = clampf(float(config.dismantle_refund_threshold), 0.0, 1.0)
	health = float(config.max_health)
	downed = false
	recovery_remaining = 0.0
	invulnerability_remaining = 0.0
	barricade_charges = int(config.max_barricade_charges)
	barricade_cooldown_remaining = 0.0
	barricades.clear()
	_next_barricade_id = 1
	_events.clear()
	revision += 1
	_emit_event("toolkit_reset")
	return get_hud_state()


func update(delta: float) -> Array[Dictionary]:
	var safe_delta := maxf(0.0, delta)
	invulnerability_remaining = maxf(0.0, invulnerability_remaining - safe_delta)
	barricade_cooldown_remaining = maxf(0.0, barricade_cooldown_remaining - safe_delta)
	if downed:
		recovery_remaining = maxf(0.0, recovery_remaining - safe_delta)
		if recovery_remaining <= 0.0:
			downed = false
			health = maxf(1.0, float(config.max_health) * float(config.revive_health_fraction))
			invulnerability_remaining = float(config.damage_invulnerability)
			revision += 1
			_emit_event("engineer_recovered", {"health": health})
	return drain_events()


func take_damage(amount: float, source: String = "enemy") -> Dictionary:
	if amount <= 0.0:
		return _result(false, "invalid_damage")
	if downed:
		return _result(false, "already_downed")
	if invulnerability_remaining > 0.0:
		return _result(false, "invulnerable")
	health = maxf(0.0, health - amount)
	invulnerability_remaining = float(config.damage_invulnerability)
	revision += 1
	_emit_event("engineer_damaged", {"amount": amount, "source": source, "health": health})
	if health <= 0.0:
		downed = true
		recovery_remaining = float(config.downed_recovery_time)
		invulnerability_remaining = 0.0
		_emit_event("engineer_downed", {"source": source, "recovery_time": recovery_remaining})
	return _result(true, "downed" if downed else "damaged")


func heal(amount: float) -> Dictionary:
	if amount <= 0.0 or downed:
		return _result(false, "cannot_heal")
	var restored := minf(amount, float(config.max_health) - health)
	health = minf(float(config.max_health), health + amount)
	revision += 1
	_emit_event("engineer_healed", {"amount": restored, "health": health})
	return _result(true, "healed")


func can_place_barricade(cell: Vector2i, walkable_cells: Variant, reserved_cells: Variant = []) -> Dictionary:
	if downed:
		return {"valid": false, "reason": "engineer_downed"}
	if barricade_charges <= 0:
		return {"valid": false, "reason": "no_charges"}
	if barricade_cooldown_remaining > 0.0:
		return {"valid": false, "reason": "cooldown"}
	if not _collection_contains(walkable_cells, cell):
		return {"valid": false, "reason": "not_walkable"}
	if _collection_contains(reserved_cells, cell):
		return {"valid": false, "reason": "reserved"}
	if barricades.has(cell):
		return {"valid": false, "reason": "occupied"}
	return {"valid": true, "reason": "valid"}


func deploy_barricade(cell: Vector2i, walkable_cells: Variant, reserved_cells: Variant = []) -> Dictionary:
	var validation := can_place_barricade(cell, walkable_cells, reserved_cells)
	if not bool(validation.valid):
		return _result(false, str(validation.reason), cell)
	var barricade := {
		"id": _next_barricade_id,
		"cell": cell,
		"hp": float(config.barricade_max_hp),
		"max_hp": float(config.barricade_max_hp),
		"blocks_movement": true
	}
	_next_barricade_id += 1
	barricades[cell] = barricade
	barricade_charges -= 1
	barricade_cooldown_remaining = float(config.barricade_cooldown)
	revision += 1
	_emit_event("barricade_deployed", {"barricade": barricade.duplicate(true), "charges": barricade_charges})
	return _result(true, "deployed", cell, {"barricade": barricade.duplicate(true)})


func handle_enemy_contact(cell: Vector2i, enemy: Dictionary, contact_scale: float = 1.0) -> Dictionary:
	if not barricades.has(cell):
		return {"blocked": false, "slowed": false, "destroyed": false, "reason": "no_barricade", "cell": cell}
	var barricade: Dictionary = barricades[cell]
	var attack_damage := maxf(0.0, float(enemy.get("structure_damage", enemy.get("damage", 0.0))) * maxf(0.0, contact_scale))
	barricade.hp = maxf(0.0, float(barricade.hp) - attack_damage)
	var destroyed := float(barricade.hp) <= 0.0
	var result := {
		"blocked": not destroyed,
		"slowed": true,
		"destroyed": destroyed,
		"cell": cell,
		"damage_to_barricade": attack_damage,
		"slow_multiplier": float(config.barricade_slow_multiplier),
		"slow_duration": float(config.barricade_slow_duration),
		"barricade_hp": float(barricade.hp),
		"enemy_id": enemy.get("id", enemy.get("type", "unknown"))
	}
	revision += 1
	_emit_event("barricade_hit", result)
	if destroyed:
		var destroyed_barricade: Dictionary = barricades[cell].duplicate(true)
		barricades.erase(cell)
		_emit_event("barricade_destroyed", {"barricade": destroyed_barricade, "refunded": false})
	return result


func repair_barricade(cell: Vector2i, amount: float) -> Dictionary:
	if not barricades.has(cell) or amount <= 0.0:
		return _result(false, "invalid_repair", cell)
	var barricade: Dictionary = barricades[cell]
	var repaired := minf(amount, float(barricade.max_hp) - float(barricade.hp))
	barricade.hp = minf(float(barricade.max_hp), float(barricade.hp) + amount)
	revision += 1
	_emit_event("barricade_repaired", {"cell": cell, "amount": repaired, "hp": barricade.hp})
	return _result(true, "repaired", cell, {"amount": repaired})


func dismantle_barricade(cell: Vector2i) -> Dictionary:
	if not barricades.has(cell):
		return _result(false, "no_barricade", cell)
	var barricade: Dictionary = barricades[cell]
	var health_fraction := float(barricade.hp) / float(barricade.max_hp)
	var refunded := health_fraction >= float(config.dismantle_refund_threshold) and barricade_charges < int(config.max_barricade_charges)
	if refunded:
		barricade_charges += 1
	barricades.erase(cell)
	revision += 1
	_emit_event("barricade_dismantled", {"cell": cell, "refunded": refunded, "charges": barricade_charges})
	return _result(true, "dismantled", cell, {"refunded": refunded})


func get_barricade(cell: Vector2i) -> Dictionary:
	if not barricades.has(cell):
		return {}
	return barricades[cell].duplicate(true)


func get_barricades() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell in barricades:
		result.append(barricades[cell].duplicate(true))
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
	return result


func is_cell_blocked(cell: Vector2i) -> bool:
	return barricades.has(cell) and bool(barricades[cell].blocks_movement)


func get_hud_state() -> Dictionary:
	return {
		"health": health,
		"max_health": float(config.max_health),
		"downed": downed,
		"recovery_remaining": recovery_remaining,
		"invulnerability_remaining": invulnerability_remaining,
		"barricade_charges": barricade_charges,
		"max_barricade_charges": int(config.max_barricade_charges),
		"barricade_cooldown_remaining": barricade_cooldown_remaining,
		"barricade_count": barricades.size(),
		"barricades": get_barricades(),
		"revision": revision
	}


func drain_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = _events.duplicate(true)
	_events.clear()
	return result


func _collection_contains(collection: Variant, cell: Vector2i) -> bool:
	if collection is Dictionary:
		return collection.has(cell) and bool(collection[cell])
	if collection is Array:
		return cell in collection
	return false


func _emit_event(event_type: String, payload: Dictionary = {}) -> void:
	var event := {"type": event_type, "revision": revision}
	event.merge(payload, true)
	_events.append(event)
	event_emitted.emit(event.duplicate(true))


func _result(success: bool, reason: String, target: Variant = null, extra: Dictionary = {}) -> Dictionary:
	var result := {"success": success, "reason": reason, "target": target, "state": get_hud_state()}
	result.merge(extra, true)
	return result
