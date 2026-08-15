extends SceneTree

const GameScript = preload("res://scripts/main.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var game = GameScript.new()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.game_state = "playing"
	game.overlay.visible = false

	_check(game.paths.size() == 3, "Expected three enemy access paths")
	_check(game.pads.size() == game.BUILD_PAD_COUNT, "Expected %d construction pads" % game.BUILD_PAD_COUNT)
	_check(game.base_health == 20, "Vault should begin with 20 integrity")
	_check(game.GRID_SIZE.x > 20 and game.GRID_SIZE.y > 16, "Map is not larger than the gameplay viewport")

	# Validate several deterministic procedural layouts and every route step.
	var route_signatures: Array[String] = []
	for seed in range(101, 126):
		game._generate_map(seed)
		_check(game.paths.size() == 3, "Seed %d did not generate three routes" % seed)
		_check(game.pads.size() == game.BUILD_PAD_COUNT, "Seed %d generated too few build pads" % seed)
		var signature := ""
		for path in game.paths:
			_check(path.size() > 1, "Seed %d generated an empty route" % seed)
			_check(path[path.size() - 1] == game.BASE_CELL, "Seed %d route did not reach the vault" % seed)
			for index in range(1, path.size()):
				_check(path[index].distance_to(path[index - 1]) == 1.0, "Seed %d route contains a disconnected step" % seed)
			signature += str(path)
		route_signatures.append(signature)
	_check(route_signatures[0] != route_signatures[1], "Different seeds generated identical routes")

	game._generate_map(8675309)
	var initial_explored: int = game.exploration.get_explored_count()
	_check(initial_explored > 0, "The starting area was not revealed")
	_check(game.exploration.get_cell_state(Vector2i.ZERO) == game.exploration.UNSEEN, "Distant terrain should begin unobservable")
	game.exploration.update_visibility(Vector2i.ZERO)
	_check(game.exploration.get_explored_count() > initial_explored, "Exploration memory did not grow after movement")
	game.exploration.update_from_grid_position(game.player_pos, true)

	# Exercise both engineer abilities through the integrated game methods.
	game.wave = 1
	game.spawned_this_wave = 0
	game._spawn_enemy(0)
	var pulse_target: Dictionary = game.enemies[0]
	pulse_target.pos = game.player_pos + Vector2(1, 0)
	var health_before_shock: float = pulse_target.hp
	game._activate_shock_pulse()
	_check(pulse_target.hp < health_before_shock, "Integrated shock pulse did not damage a nearby enemy")
	game.enemies.clear()
	game.abilities.reset()
	game.player_pos = game.BASE_CELL
	game.base_health = 12
	game.credits = 100.0
	game._activate_emergency_repair()
	_check(game.base_health > 12 and game.credits < 100.0, "Integrated emergency repair did not exchange credits for integrity")
	game.base_health = 20
	game.wave = 0
	game.abilities.reset()

	# Exercise stand-to-fund construction.
	var test_pad: Dictionary = game.pads[0]
	game.player_pos = test_pad.pos
	game.credits = 1000.0
	for step in 40:
		game._update_construction(0.05)
	_check(test_pad.level >= 1, "Standing on a pad did not build a sentry")
	_check(game.credits < 1000.0, "Construction did not spend credits")

	# Max all pads so six full waves can exercise spawning, path traversal,
	# targeting, damage, rewards, wave completion, and the victory transition.
	for pad in game.pads:
		pad.level = 3
		pad.progress = 0.0
	game.credits = 500.0

	for expected_wave in range(1, game.MAX_WAVES + 1):
		game._request_wave()
		_check(game.wave == expected_wave, "Wave %d did not start" % expected_wave)
		var simulation_steps := 0
		while game.wave_active and game.game_state == "playing" and simulation_steps < 12000:
			game._update_wave(0.05)
			game._update_enemies(0.05)
			game._update_turrets(0.05)
			game._update_effects(0.05)
			simulation_steps += 1
		_check(simulation_steps < 12000, "Wave %d did not terminate" % expected_wave)
		if game.game_state == "defeat":
			failures.append("Vault was unexpectedly defeated during wave %d" % expected_wave)
			break

	_check(game.game_state == "victory", "Completing six waves did not trigger victory")
	_check(game.total_kills > 0, "Turrets did not destroy any enemies")
	_check(game.enemies.is_empty(), "Enemies remained after the final wave")
	_check("armored" in game.CombatCatalogScript.get_wave_composition(3), "Integrated campaign never introduced armored enemies")
	_check("shielded" in game.CombatCatalogScript.get_wave_composition(4), "Integrated campaign never introduced shielded enemies")

	if failures.is_empty():
		print("SMOKE TEST PASSED: random maps, fog, abilities, expanded combat, six waves, and victory")
		quit(0)
	else:
		for failure in failures:
			push_error("SMOKE TEST FAILED: " + failure)
		quit(1)
