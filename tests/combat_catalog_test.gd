extends SceneTree

const CombatCatalog = preload("res://scripts/combat_catalog.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var ids := CombatCatalog.get_enemy_ids()
	_check(ids.size() >= 5, "Catalog should contain at least five enemy archetypes")
	for required_id in ["drone", "runner", "brute", "armored", "shielded"]:
		_check(CombatCatalog.has_enemy(required_id), "Missing enemy archetype: " + required_id)
		var stats: Dictionary = CombatCatalog.get_enemy_stats(required_id, 1)
		for field in ["hp", "speed", "damage", "reward", "armor", "shield"]:
			_check(stats.has(field), "%s is missing %s" % [required_id, field])
		_check(float(stats.get("hp", 0.0)) > 0.0, required_id + " should have positive HP")
		_check(float(stats.get("speed", 0.0)) > 0.0, required_id + " should have positive speed")

	_check(CombatCatalog.get_enemy_base("unknown").is_empty(), "Unknown enemies should return an empty definition")
	_check(float(CombatCatalog.get_enemy_stats("armored", 6).hp) > float(CombatCatalog.get_enemy_stats("armored", 1).hp), "Enemy HP should scale by wave")
	_check(float(CombatCatalog.get_enemy_stats("runner", 6).reward) > float(CombatCatalog.get_enemy_stats("runner", 1).reward), "Enemy rewards should scale by wave")
	_check(float(CombatCatalog.get_enemy_stats("shielded", 1).shield) > 0.0, "Shielded enemies should have a shield pool")
	_check(float(CombatCatalog.get_enemy_stats("armored", 1).armor) > 0.25, "Armored enemies should resist normal damage")

	for level in range(1, 4):
		var tier: Dictionary = CombatCatalog.get_turret_tier(level)
		_check(not tier.is_empty(), "Missing turret tier %d" % level)
		_check(float(tier.get("damage", 0.0)) > 0.0, "Turret tier %d has no damage" % level)
		_check(float(tier.get("range", 0.0)) > 0.0, "Turret tier %d has no range" % level)
	_check(CombatCatalog.get_turret_tier(3).effect == "slow", "Tier 3 should expose its slow effect")
	_check(CombatCatalog.calculate_hit(100.0, 0.4, 0.2) == 80.0, "Armor-piercing damage calculation is incorrect")

	for wave in range(1, 11):
		var first := CombatCatalog.get_wave_composition(wave)
		var second := CombatCatalog.get_wave_composition(wave)
		_check(first == second, "Wave %d composition is not deterministic" % wave)
		_check(first.size() == 5 + wave * 3, "Wave %d has an unexpected enemy count" % wave)
		for enemy_id in first:
			_check(CombatCatalog.has_enemy(enemy_id), "Wave %d contains unknown enemy %s" % [wave, enemy_id])

	_check("armored" in CombatCatalog.get_wave_composition(3), "Armored enemy should debut by wave 3")
	_check("shielded" in CombatCatalog.get_wave_composition(4), "Shielded enemy should debut by wave 4")

	var plan := CombatCatalog.get_wave_spawn_plan(6, 3)
	_check(plan.size() == 23, "Wave 6 spawn plan should contain 23 entries")
	for index in range(plan.size()):
		var entry: Dictionary = plan[index]
		var enemy: Dictionary = entry.enemy
		_check(int(entry.spawn_index) == index, "Spawn plan indexes should be sequential")
		_check(int(entry.path_index) == index % 3, "Spawn plan should rotate through paths")
		_check(int(enemy.path) == int(entry.path_index), "Enemy state path should match plan path")
		_check(enemy.has("max_hp") and enemy.has("segment") and enemy.has("hit"), "Enemy state is not compatible with the current combat loop")

	# Definitions returned to callers must not mutate the catalog.
	var mutable_stats := CombatCatalog.get_enemy_base("drone")
	mutable_stats.hp = -1.0
	_check(float(CombatCatalog.get_enemy_base("drone").hp) > 0.0, "Catalog definitions leaked mutable state")

	if failures.is_empty():
		print("COMBAT CATALOG TEST PASSED: archetypes, scaling, tiers, waves, and spawn plans")
		quit(0)
	else:
		for failure in failures:
			push_error("COMBAT CATALOG TEST FAILED: " + failure)
		quit(1)
