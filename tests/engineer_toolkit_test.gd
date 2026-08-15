extends SceneTree

const EngineerToolkit = preload("res://scripts/engineer_toolkit.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var toolkit := EngineerToolkit.new({
		"max_health": 80.0,
		"downed_recovery_time": 2.0,
		"revive_health_fraction": 0.5,
		"damage_invulnerability": 0.25,
		"max_barricade_charges": 2,
		"barricade_cooldown": 0.5,
		"barricade_max_hp": 50.0,
		"dismantle_refund_threshold": 0.5
	})
	var walkable := {Vector2i(1, 1): true, Vector2i(2, 1): true, Vector2i(3, 1): true}
	var reserved := [Vector2i(3, 1)]

	_check(not bool(toolkit.can_place_barricade(Vector2i(0, 0), walkable).valid), "Placement should reject non-walkable cells")
	_check(toolkit.can_place_barricade(Vector2i(3, 1), walkable, reserved).reason == "reserved", "Placement should reject reserved cells")
	var deploy := toolkit.deploy_barricade(Vector2i(1, 1), walkable, reserved)
	_check(bool(deploy.success), "Valid barricade placement should succeed")
	_check(toolkit.is_cell_blocked(Vector2i(1, 1)), "Deployed barricade should block its cell")
	_check(int(toolkit.get_hud_state().barricade_charges) == 1, "Deployment should consume one charge")
	_check(toolkit.can_place_barricade(Vector2i(2, 1), walkable).reason == "cooldown", "Deployment should begin a cooldown")
	toolkit.update(0.5)
	_check(bool(toolkit.deploy_barricade(Vector2i(2, 1), walkable).success), "Placement should resume after cooldown")
	toolkit.update(0.5)
	_check(toolkit.can_place_barricade(Vector2i(1, 1), walkable).reason == "no_charges", "No charges should take priority once the stock is empty")

	var light_contact := toolkit.handle_enemy_contact(Vector2i(1, 1), {"type": "runner", "damage": 15.0})
	_check(bool(light_contact.blocked) and bool(light_contact.slowed), "Surviving barricade should block and slow an enemy")
	_check(is_equal_approx(float(toolkit.get_barricade(Vector2i(1, 1)).hp), 35.0), "Enemy damage should reduce barricade durability")
	toolkit.repair_barricade(Vector2i(1, 1), 10.0)
	_check(is_equal_approx(float(toolkit.get_barricade(Vector2i(1, 1)).hp), 45.0), "Barricade repair should restore durability")
	var dismantle := toolkit.dismantle_barricade(Vector2i(1, 1))
	_check(bool(dismantle.refunded) and int(toolkit.get_hud_state().barricade_charges) == 1, "Healthy dismantled barricade should refund its charge")

	var heavy_contact := toolkit.handle_enemy_contact(Vector2i(2, 1), {"id": 9, "structure_damage": 100.0})
	_check(bool(heavy_contact.destroyed) and not bool(heavy_contact.blocked), "Destroyed barricade should stop blocking")
	_check(not toolkit.is_cell_blocked(Vector2i(2, 1)), "Destroyed barricade should leave the cell")
	_check(int(toolkit.get_hud_state().barricade_charges) == 1, "Destroyed barricade should not refund a charge")

	# Damage invulnerability prevents rapid repeated hits; lethal damage starts a
	# timed downed state and recovery returns a configured fraction of health.
	var first_hit := toolkit.take_damage(30.0, "drone")
	_check(bool(first_hit.success) and is_equal_approx(float(toolkit.health), 50.0), "Engineer damage should reduce health")
	_check(toolkit.take_damage(30.0).reason == "invulnerable", "Damage grace period should reject immediate repeated hits")
	toolkit.update(0.25)
	toolkit.take_damage(100.0, "brute")
	_check(toolkit.downed and is_equal_approx(float(toolkit.health), 0.0), "Lethal damage should down the engineer")
	_check(toolkit.can_place_barricade(Vector2i(1, 1), walkable).reason == "engineer_downed", "Downed engineer should not deploy barricades")
	toolkit.update(1.0)
	_check(toolkit.downed, "Engineer should remain downed until recovery completes")
	var recovery_events := toolkit.update(1.0)
	_check(not toolkit.downed and is_equal_approx(float(toolkit.health), 40.0), "Recovery should revive engineer at configured health")
	_check(toolkit.take_damage(1.0).reason == "invulnerable", "Recovery should grant a brief invulnerability window")

	var hud := toolkit.get_hud_state()
	_check(hud.has("health") and hud.has("barricades") and hud.has("revision"), "HUD state should expose health, placements, and revision")
	_check(not recovery_events.is_empty(), "Update should return consumable recovery events")
	_check(toolkit.drain_events().is_empty(), "Event draining should clear queued events")

	toolkit.reset()
	_check(is_equal_approx(float(toolkit.health), 100.0), "Reset without overrides should restore default health")
	_check(int(toolkit.barricade_charges) == 3 and toolkit.barricades.is_empty(), "Reset should restore charges and clear barricades")

	if failures.is_empty():
		print("ENGINEER TOOLKIT TEST PASSED: health, recovery, placement, contact, repair, refunds, charges, and cooldowns")
		quit(0)
	else:
		for failure in failures:
			push_error("ENGINEER TOOLKIT TEST FAILED: " + failure)
		quit(1)
