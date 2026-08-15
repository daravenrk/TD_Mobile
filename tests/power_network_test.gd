extends SceneTree

const PowerNetwork = preload("res://scripts/power_network.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _definitions() -> Array:
	return [
		{"id": "vault", "type": "generator", "capacity": 7.0, "connections": ["relay"]},
		{"id": "relay", "type": "substation", "priority": 100, "connections": ["sensor", "armory", "doors"]},
		{"id": "sensor", "type": "sensor", "priority": 90, "position": Vector2(4, 2), "coverage_radius": 8.0},
		{"id": "armory", "type": "armory", "priority": 40, "damage_bonus": 0.15, "armor_pierce_bonus": 0.07},
		{"id": "doors", "type": "blast_control", "priority": 80, "charge": 45.0, "charge_rate": 10.0, "seal_cost": 50.0}
	]


func _run() -> void:
	var network := PowerNetwork.new()
	network.reset(_definitions())

	_check(network.is_online("vault"), "Healthy generator should be online")
	_check(network.is_online("relay"), "Connected substation should be online")
	_check(network.is_online("sensor"), "Higher-priority sensor should receive power")
	_check(network.is_online("doors"), "Blast control should receive remaining power")
	_check(not network.is_online("armory"), "Capacity limit should shed the lower-priority armory")
	_check(is_equal_approx(float(network.get_hud_state().power_used), 5.0), "Power budget should count online consumers")
	_check(network.get_sensor_coverage().size() == 1, "Online sensor should contribute coverage")
	_check(is_equal_approx(float(network.get_armory_bonuses().damage_multiplier), 1.0), "Offline armory should not grant bonuses")

	# Toggling a consumer should free capacity for the next priority.
	network.set_facility_enabled("doors", false)
	_check(network.is_online("armory"), "Armory should power up when blast control is disabled")
	_check(is_equal_approx(float(network.get_armory_bonuses().damage_multiplier), 1.15), "Online armory damage bonus is incorrect")
	_check(is_equal_approx(float(network.get_armory_bonuses().armor_pierce_bonus), 0.07), "Online armory pierce bonus is incorrect")
	network.set_facility_enabled("doors", true)
	_check(not network.is_online("armory"), "Priority allocation should restore blast control before armory")

	# Relay damage cascades to every downstream service, then repairs restore it.
	network.damage_facility("relay", 999.0)
	_check(not network.is_online("relay"), "Destroyed substation should be offline")
	_check(not network.is_online("sensor") and not network.is_online("doors"), "Relay loss should cascade downstream")
	network.repair_facility("relay", 100.0)
	_check(network.is_online("sensor") and network.is_online("doors"), "Repair should restore downstream allocation")

	# Exposed link sabotage disconnects the branch and link repair reconnects it.
	var root_link := "relay--vault"
	_check(network.get_link(root_link).get("exposed", false), "Generated connection should create an exposed link")
	network.sabotage_link(root_link, 999.0)
	_check(not network.is_online("relay") and not network.is_online("sensor"), "Severed link should disconnect its branch")
	network.repair_link(root_link, 60.0)
	_check(network.is_online("relay") and network.is_online("sensor"), "Link repair should reconnect its branch")

	# Generator loss is a whole-network blackout.
	network.damage_facility("vault", 999.0)
	_check(not network.is_online("vault") and not network.is_online("relay"), "Generator destruction should black out the network")
	network.repair_facility("vault", 200.0)
	_check(network.is_online("vault") and network.is_online("sensor"), "Generator repair should restore the network")

	# Blast charge advances only while powered and can be spent to seal the door.
	network.update(0.5)
	_check(is_equal_approx(float(network.get_facility("doors").charge), 50.0), "Blast control should recharge while online")
	var seal_result := network.request_blast_door("doors", true)
	_check(bool(seal_result.success), "Charged online blast control should seal its door")
	_check(network.get_facility("doors").door_state == "sealed", "Blast door state should be serializable")
	_check(is_equal_approx(float(network.get_facility("doors").charge), 0.0), "Sealing should consume charge")
	_check(not bool(network.request_blast_door("doors", true).success), "Blast door should reject sealing without charge")
	network.request_blast_door("doors", false)
	_check(network.get_facility("doors").door_state == "open", "Blast door should reopen without spending charge")

	var hud := network.get_hud_state()
	_check(hud.has("facilities") and hud.has("armory_bonuses") and hud.has("revision"), "HUD snapshot is missing required serializable fields")
	var events := network.drain_events()
	_check(events.size() >= 2, "Blast door mutations should expose consumable events")
	_check(network.drain_events().is_empty(), "Draining events should clear the queue")

	if failures.is_empty():
		print("POWER NETWORK TEST PASSED: budgeting, propagation, sabotage, repair, bonuses, and blast control")
		quit(0)
	else:
		for failure in failures:
			push_error("POWER NETWORK TEST FAILED: " + failure)
		quit(1)
