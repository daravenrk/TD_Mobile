class_name PowerNetwork
extends RefCounted

## Data-driven infrastructure simulation. Facility dictionaries may contain:
## id, type, position, connections, power_cost, priority, enabled, hp, max_hp,
## plus type-specific values such as capacity, coverage_radius or damage_bonus.

signal event_emitted(event: Dictionary)

const FACILITY_DEFAULTS := {
	"generator": {"power_cost": 0.0, "priority": 1000, "max_hp": 200.0, "capacity": 12.0},
	"substation": {"power_cost": 1.0, "priority": 900, "max_hp": 100.0},
	"sensor": {"power_cost": 2.0, "priority": 700, "max_hp": 70.0, "coverage_radius": 7.0},
	"armory": {"power_cost": 3.0, "priority": 500, "max_hp": 100.0, "damage_bonus": 0.12, "armor_pierce_bonus": 0.05},
	"blast_control": {"power_cost": 2.0, "priority": 800, "max_hp": 120.0, "max_charge": 100.0, "charge_rate": 8.0, "seal_cost": 50.0}
}

var facilities: Dictionary = {}
var links: Dictionary = {}
var generator_id: String = ""
var capacity: float = 0.0
var power_used: float = 0.0
var revision: int = 0

var _events: Array[Dictionary] = []


func reset(facility_defs: Array, link_defs: Array = [], capacity_override: float = -1.0) -> Dictionary:
	facilities.clear()
	links.clear()
	generator_id = ""
	capacity = 0.0
	power_used = 0.0
	_events.clear()

	for raw_definition in facility_defs:
		if not raw_definition is Dictionary:
			continue
		var definition: Dictionary = raw_definition
		var facility_id := str(definition.get("id", ""))
		var facility_type := str(definition.get("type", ""))
		if facility_id.is_empty() or not FACILITY_DEFAULTS.has(facility_type) or facilities.has(facility_id):
			continue
		var facility: Dictionary = FACILITY_DEFAULTS[facility_type].duplicate(true)
		facility.merge(definition, true)
		facility["id"] = facility_id
		facility["type"] = facility_type
		facility["enabled"] = bool(facility.get("enabled", true))
		facility["max_hp"] = maxf(1.0, float(facility.get("max_hp", 100.0)))
		facility["hp"] = clampf(float(facility.get("hp", facility.max_hp)), 0.0, float(facility.max_hp))
		facility["online"] = false
		facility["offline_reason"] = "unconfigured"
		if facility_type == "blast_control":
			facility["charge"] = clampf(float(facility.get("charge", 0.0)), 0.0, float(facility.max_charge))
			facility["door_state"] = str(facility.get("door_state", "open"))
		facilities[facility_id] = facility
		if facility_type == "generator" and generator_id.is_empty():
			generator_id = facility_id

	for raw_link in link_defs:
		if raw_link is Dictionary:
			_add_link_definition(raw_link)
	for raw_definition in facility_defs:
		if not raw_definition is Dictionary:
			continue
		var from_id := str(raw_definition.get("id", ""))
		for connection in raw_definition.get("connections", []):
			var to_id := str(connection)
			if from_id != to_id:
				_add_link_definition({"a": from_id, "b": to_id})

	if not generator_id.is_empty():
		capacity = float(facilities[generator_id].get("capacity", 0.0))
	if capacity_override >= 0.0:
		capacity = capacity_override
	_recalculate()
	_emit_event("network_reset", {"facility_count": facilities.size(), "link_count": links.size()})
	return get_hud_state()


func update(delta: float) -> Array[Dictionary]:
	_recalculate()
	if delta > 0.0:
		for facility_id in facilities:
			var facility: Dictionary = facilities[facility_id]
			if facility.type == "blast_control" and facility.online:
				var old_charge := float(facility.charge)
				facility.charge = minf(float(facility.max_charge), old_charge + float(facility.charge_rate) * delta)
				if old_charge < float(facility.max_charge) and is_equal_approx(float(facility.charge), float(facility.max_charge)):
					_emit_event("blast_ready", {"facility_id": facility_id})
	return drain_events()


func set_facility_enabled(facility_id: String, enabled: bool) -> Dictionary:
	if not facilities.has(facility_id) or facility_id == generator_id:
		return _result(false, "unknown_or_fixed_facility", facility_id)
	var facility: Dictionary = facilities[facility_id]
	facility.enabled = enabled
	_recalculate()
	_emit_event("facility_toggled", {"facility_id": facility_id, "enabled": enabled})
	return _result(true, "enabled" if enabled else "disabled", facility_id)


func set_priority(facility_id: String, priority: int) -> Dictionary:
	if not facilities.has(facility_id) or facility_id == generator_id:
		return _result(false, "unknown_or_fixed_facility", facility_id)
	facilities[facility_id].priority = priority
	_recalculate()
	_emit_event("priority_changed", {"facility_id": facility_id, "priority": priority})
	return _result(true, "priority_changed", facility_id)


func damage_facility(facility_id: String, amount: float) -> Dictionary:
	if not facilities.has(facility_id) or amount <= 0.0:
		return _result(false, "invalid_damage", facility_id)
	var facility: Dictionary = facilities[facility_id]
	var was_alive := float(facility.hp) > 0.0
	facility.hp = maxf(0.0, float(facility.hp) - amount)
	_recalculate()
	_emit_event("facility_damaged", {"facility_id": facility_id, "amount": amount, "hp": facility.hp})
	if was_alive and float(facility.hp) <= 0.0:
		_emit_event("facility_destroyed", {"facility_id": facility_id})
	return _result(true, "damaged", facility_id)


func repair_facility(facility_id: String, amount: float) -> Dictionary:
	if not facilities.has(facility_id) or amount <= 0.0:
		return _result(false, "invalid_repair", facility_id)
	var facility: Dictionary = facilities[facility_id]
	var repaired := minf(amount, float(facility.max_hp) - float(facility.hp))
	facility.hp = minf(float(facility.max_hp), float(facility.hp) + amount)
	_recalculate()
	_emit_event("facility_repaired", {"facility_id": facility_id, "amount": repaired, "hp": facility.hp})
	return _result(true, "repaired", facility_id)


func sabotage_link(link_id: String, amount: float) -> Dictionary:
	if not links.has(link_id) or amount <= 0.0:
		return _result(false, "invalid_sabotage", link_id)
	var link: Dictionary = links[link_id]
	if not bool(link.exposed):
		return _result(false, "protected_link", link_id)
	link.hp = maxf(0.0, float(link.hp) - amount)
	_recalculate()
	_emit_event("link_sabotaged", {"link_id": link_id, "amount": amount, "hp": link.hp})
	return _result(true, "sabotaged", link_id)


func repair_link(link_id: String, amount: float) -> Dictionary:
	if not links.has(link_id) or amount <= 0.0:
		return _result(false, "invalid_repair", link_id)
	var link: Dictionary = links[link_id]
	var repaired := minf(amount, float(link.max_hp) - float(link.hp))
	link.hp = minf(float(link.max_hp), float(link.hp) + amount)
	_recalculate()
	_emit_event("link_repaired", {"link_id": link_id, "amount": repaired, "hp": link.hp})
	return _result(true, "repaired", link_id)


func request_blast_door(facility_id: String, seal: bool) -> Dictionary:
	if not facilities.has(facility_id) or facilities[facility_id].type != "blast_control":
		return _result(false, "unknown_blast_control", facility_id)
	var facility: Dictionary = facilities[facility_id]
	if not seal:
		facility.door_state = "open"
		_emit_event("blast_door_opened", {"facility_id": facility_id})
		return _result(true, "opened", facility_id)
	if not facility.online:
		return _result(false, "offline", facility_id)
	var cost := float(facility.seal_cost)
	if float(facility.charge) < cost:
		return _result(false, "insufficient_charge", facility_id)
	facility.charge = float(facility.charge) - cost
	facility.door_state = "sealed"
	_emit_event("blast_door_sealed", {"facility_id": facility_id, "charge": facility.charge})
	return _result(true, "sealed", facility_id)


func get_facility(facility_id: String) -> Dictionary:
	if not facilities.has(facility_id):
		return {}
	return facilities[facility_id].duplicate(true)


func get_link(link_id: String) -> Dictionary:
	if not links.has(link_id):
		return {}
	return links[link_id].duplicate(true)


func is_online(facility_id: String) -> bool:
	return facilities.has(facility_id) and bool(facilities[facility_id].online)


func get_sensor_coverage() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for facility_id in facilities:
		var facility: Dictionary = facilities[facility_id]
		if facility.type == "sensor" and facility.online:
			result.append({"facility_id": facility_id, "position": facility.get("position", Vector2.ZERO), "radius": float(facility.coverage_radius)})
	return result


func get_armory_bonuses() -> Dictionary:
	var damage_bonus := 0.0
	var armor_pierce_bonus := 0.0
	var online_count := 0
	for facility_id in facilities:
		var facility: Dictionary = facilities[facility_id]
		if facility.type == "armory" and facility.online:
			online_count += 1
			damage_bonus += float(facility.damage_bonus)
			armor_pierce_bonus += float(facility.armor_pierce_bonus)
	return {"online_count": online_count, "damage_multiplier": 1.0 + damage_bonus, "armor_pierce_bonus": armor_pierce_bonus}


func get_hud_state() -> Dictionary:
	var facility_states: Array[Dictionary] = []
	for facility_id in facilities:
		var facility: Dictionary = facilities[facility_id]
		var state := {
			"id": facility_id,
			"type": facility.type,
			"enabled": facility.enabled,
			"online": facility.online,
			"offline_reason": facility.offline_reason,
			"hp": facility.hp,
			"max_hp": facility.max_hp,
			"power_cost": facility.power_cost,
			"priority": facility.priority
		}
		if facility.type == "blast_control":
			state["charge"] = facility.charge
			state["max_charge"] = facility.max_charge
			state["door_state"] = facility.door_state
		facility_states.append(state)
	facility_states.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	var damaged_links := 0
	for link_id in links:
		if float(links[link_id].hp) < float(links[link_id].max_hp):
			damaged_links += 1
	return {
		"capacity": capacity,
		"power_used": power_used,
		"power_free": maxf(0.0, capacity - power_used),
		"generator_online": is_online(generator_id),
		"facilities": facility_states,
		"sensor_count": get_sensor_coverage().size(),
		"armory_bonuses": get_armory_bonuses(),
		"damaged_links": damaged_links,
		"revision": revision
	}


func drain_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = _events.duplicate(true)
	_events.clear()
	return result


func _add_link_definition(definition: Dictionary) -> void:
	var a := str(definition.get("a", definition.get("from", "")))
	var b := str(definition.get("b", definition.get("to", "")))
	if not facilities.has(a) or not facilities.has(b) or a == b:
		return
	var link_id := str(definition.get("id", _canonical_link_id(a, b)))
	if links.has(link_id):
		return
	var max_hp := maxf(1.0, float(definition.get("max_hp", 60.0)))
	links[link_id] = {
		"id": link_id,
		"a": a,
		"b": b,
		"exposed": bool(definition.get("exposed", true)),
		"max_hp": max_hp,
		"hp": clampf(float(definition.get("hp", max_hp)), 0.0, max_hp)
	}


func _canonical_link_id(a: String, b: String) -> String:
	return "%s--%s" % [a, b] if a < b else "%s--%s" % [b, a]


func _recalculate() -> void:
	revision += 1
	power_used = 0.0
	for facility_id in facilities:
		var facility: Dictionary = facilities[facility_id]
		facility.online = false
		if float(facility.hp) <= 0.0:
			facility.offline_reason = "destroyed"
		elif not bool(facility.enabled):
			facility.offline_reason = "disabled"
		else:
			facility.offline_reason = "disconnected"
	if generator_id.is_empty() or float(facilities[generator_id].hp) <= 0.0:
		return
	var generator: Dictionary = facilities[generator_id]
	generator.online = true
	generator.offline_reason = ""

	# Only powered substations relay power. Repeatedly allocate the highest-priority
	# facility currently reachable from the already powered relay network.
	var relays: Dictionary = {generator_id: true}
	var pending: Array[String] = []
	for facility_id in facilities:
		if facility_id != generator_id:
			pending.append(facility_id)
	while true:
		var available: Array[String] = []
		for facility_id in pending:
			var facility: Dictionary = facilities[facility_id]
			if float(facility.hp) > 0.0 and bool(facility.enabled) and _touches_powered_relay(facility_id, relays):
				available.append(facility_id)
		if available.is_empty():
			break
		available.sort_custom(func(a: String, b: String) -> bool:
			var priority_a := int(facilities[a].priority)
			var priority_b := int(facilities[b].priority)
			return priority_a > priority_b if priority_a != priority_b else a < b
		)
		var made_progress := false
		for facility_id in available:
			pending.erase(facility_id)
			var facility: Dictionary = facilities[facility_id]
			var cost := maxf(0.0, float(facility.power_cost))
			if power_used + cost <= capacity + 0.0001:
				facility.online = true
				facility.offline_reason = ""
				power_used += cost
				if facility.type == "substation":
					relays[facility_id] = true
				made_progress = true
			else:
				facility.offline_reason = "insufficient_power"
		if not made_progress:
			break


func _touches_powered_relay(facility_id: String, relays: Dictionary) -> bool:
	for link_id in links:
		var link: Dictionary = links[link_id]
		if float(link.hp) <= 0.0:
			continue
		if link.a == facility_id and relays.has(str(link.b)):
			return true
		if link.b == facility_id and relays.has(str(link.a)):
			return true
	return false


func _emit_event(event_type: String, payload: Dictionary = {}) -> void:
	var event := {"type": event_type, "revision": revision}
	event.merge(payload, true)
	_events.append(event)
	event_emitted.emit(event.duplicate(true))


func _result(success: bool, reason: String, target_id: String) -> Dictionary:
	return {"success": success, "reason": reason, "target_id": target_id, "state": get_hud_state()}
