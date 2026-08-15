extends SceneTree

const Behavior = preload("res://scripts/enemy_behavior.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_sapper_targeting_and_attack()
	_test_fallbacks_and_specialists()
	_test_deterministic_selection()
	if failures.is_empty():
		print("ENEMY BEHAVIOR TEST PASSED: sapper targeting, attack timers, telegraphs, fallbacks, and specialist metadata")
		quit(0)
	else:
		for failure in failures:
			push_error("ENEMY BEHAVIOR TEST FAILED: " + failure)
		quit(1)


func _test_sapper_targeting_and_attack() -> void:
	var vault := {"id": "vault", "name": "Command Vault", "position": Vector2(20, 20)}
	var facilities := {
		"sensor_a": {"type": "sensor", "position": Vector2(2, 0), "hp": 70.0, "max_hp": 70.0, "online": true},
		"grid_a": {"id": "grid_a", "type": "substation", "position": Vector2(5, 0), "hp": 75.0, "max_hp": 100.0, "online": true},
		"offline_armory": {"type": "armory", "position": Vector2(1, 0), "hp": 100.0, "max_hp": 100.0, "online": false}
	}
	var sapper := {"type": "sapper", "pos": Vector2.ZERO, "sabotage_damage": 30.0}
	Behavior.initialize_enemy(sapper)
	_check(sapper.intent == "sabotage_infrastructure", "Sapper did not receive sabotage intent")
	var target := Behavior.assign_target(sapper, vault, facilities)
	_check(target.kind == "facility", "Sapper chose the vault while infrastructure was available")
	_check(target.id == "grid_a", "Sapper scoring did not prioritize the strategic substation")
	_check(sapper.target_id == "grid_a", "Assigned target metadata was not stored on the enemy")

	var winding: Dictionary = Behavior.update_attack(sapper, 0.9, true)
	_check(not winding.attack_ready, "Sapper attacked before its timer elapsed")
	_check(winding.telegraph.visible, "Sapper did not telegraph its imminent sabotage")
	_check("Substation" in winding.telegraph.label, "Telegraph does not name the readable target")
	var attack: Dictionary = Behavior.update_attack(sapper, 1.0, true)
	_check(attack.attack_ready and attack.action == "damage_facility", "Sapper did not produce facility damage")
	_check(is_equal_approx(float(attack.damage), 30.0), "Sapper ignored its configured sabotage damage")
	_check(attack.target_id == "grid_a", "Attack result lost its target ID")
	_check(float(sapper.attack_remaining) > 0.0, "Attack timer did not reset")


func _test_fallbacks_and_specialists() -> void:
	var vault := {"position": Vector2(9, 9)}
	var dead_or_offline := [
		{"id": "dead_sensor", "type": "sensor", "position": Vector2.ONE, "hp": 0.0, "max_hp": 70.0, "online": false},
		{"id": "idle_armory", "type": "armory", "position": Vector2.ONE, "hp": 100.0, "max_hp": 100.0, "online": false}
	]
	var sapper := {"type": "sapper", "pos": Vector2.ZERO}
	Behavior.initialize_enemy(sapper)
	_check(Behavior.assign_target(sapper, vault, dead_or_offline).kind == "vault", "Sapper did not fall back to the vault")
	var approaching := Behavior.update_attack(sapper, 99.0, false)
	_check(approaching.event == "approaching", "Out-of-range enemy advanced its attack timer")

	var stalker := {"type": "stalker", "pos": Vector2.ZERO}
	Behavior.initialize_enemy(stalker)
	_check(stalker.stealthed_outside_sensor, "Stalker is missing stealth behavior metadata")
	var sensor_target := Behavior.choose_target(stalker, vault, [
		{"id": "sensor", "type": "sensor", "position": Vector2(4, 0), "hp": 40.0, "max_hp": 70.0, "online": true},
		{"id": "generator", "type": "generator", "position": Vector2.ONE, "hp": 100.0, "max_hp": 100.0, "online": true}
	])
	_check(sensor_target.id == "sensor", "Stalker did not prioritize the sensor")

	var burrower := {"type": "burrower", "pos": Vector2.ZERO}
	Behavior.initialize_enemy(burrower)
	Behavior.assign_target(burrower, vault, [])
	burrower.attack_remaining = 0.0
	var breach := Behavior.update_attack(burrower, 0.0, true)
	_check(breach.action == "create_breach", "Burrower did not produce breach behavior")


func _test_deterministic_selection() -> void:
	var first: Array[String] = []
	var second: Array[String] = []
	for index in range(30):
		first.append(Behavior.choose_archetype("drone", 3, index))
		second.append(Behavior.choose_archetype("drone", 3, index))
	_check(first == second, "Archetype injection is not deterministic")
	_check("sapper" in first, "Sector three composition never introduced a Sapper")
	_check("stalker" in first, "Sector three composition never introduced a Stalker")
	_check(Behavior.get_behavior_profile("unknown").behavior_id == "default", "Unknown enemy did not use default behavior")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
