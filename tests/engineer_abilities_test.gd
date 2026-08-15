extends SceneTree

const Abilities = preload("res://scripts/engineer_abilities.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var abilities = Abilities.new(4.0, 2.0, 30.0, 10.0, 5, 10.0)
	var near_enemy := {"pos": Vector2(1.0, 0.0), "hp": 20.0, "hit": 0.0}
	var sturdy_enemy := {"pos": Vector2(0.0, 2.0), "hp": 50.0, "hit": 0.0}
	var far_enemy := {"pos": Vector2(2.01, 0.0), "hp": 50.0, "hit": 0.0}
	var enemies := [near_enemy, sturdy_enemy, far_enemy]

	_check(abilities.can_activate_shock(), "Shock should start ready")
	var shock: Dictionary = abilities.activate_shock(Vector2.ZERO, enemies)
	_check(shock.activated, "Shock did not activate")
	_check(shock.affected.size() == 2, "Shock radius selected the wrong enemies")
	_check(shock.defeated.size() == 1, "Shock did not report its defeated enemy")
	_check(is_equal_approx(near_enemy.hp, 0.0), "Shock damage was not capped at zero health")
	_check(is_equal_approx(sturdy_enemy.hp, 20.0), "Shock damage was not applied")
	_check(is_equal_approx(far_enemy.hp, 50.0), "Shock damaged an out-of-range enemy")
	_check(not abilities.activate_shock(Vector2.ZERO, enemies).activated, "Shock ignored its cooldown")
	_check(is_equal_approx(abilities.get_shock_ready_ratio(), 0.0), "Shock HUD ratio should be empty after use")

	abilities.update_cooldowns(2.0)
	_check(is_equal_approx(abilities.get_shock_ready_ratio(), 0.5), "Shock HUD ratio did not advance")
	abilities.update_cooldowns(2.0)
	_check(abilities.can_activate_shock(), "Shock did not become ready")

	var repair: Dictionary = abilities.activate_emergency_repair(12, 20, 36.0)
	_check(repair.activated, "Affordable emergency repair did not activate")
	_check(repair.repaired == 3, "Repair did not cap itself to affordable integrity")
	_check(repair.base_health == 15, "Repair returned the wrong vault health")
	_check(is_equal_approx(repair.credits, 6.0), "Repair returned the wrong credit balance")
	_check(not abilities.activate_emergency_repair(15, 20, 100.0).activated, "Repair ignored its cooldown")

	abilities.reset()
	_check(is_equal_approx(abilities.get_repair_ready_ratio(), 1.0), "Reset did not refill the repair HUD meter")
	var full_result: Dictionary = abilities.activate_emergency_repair(20, 20, 100.0)
	_check(full_result.reason == "vault_full", "Repair should reject a full-health vault")
	_check(abilities.get_hud_state().shock_pulse.ready, "HUD state did not report a ready shock")

	if failures.is_empty():
		print("ENGINEER ABILITIES TEST PASSED: shock pulse, repair economy, cooldowns, reset, and HUD state")
		quit(0)
	else:
		for failure in failures:
			push_error("ENGINEER ABILITIES TEST FAILED: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
