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

	var signatures: Dictionary = {}
	for seed in range(101, 126):
		game._generate_map(seed)
		_check(game.map_data.rooms.size() >= 8, "Seed %d generated too few rooms" % seed)
		_check(game.paths.size() == 3, "Seed %d did not generate three breach routes" % seed)
		_check(game.pads.size() == game.BUILD_PAD_COUNT, "Seed %d generated the wrong pad count" % seed)
		_check(game.power_network.facilities.size() == 5, "Seed %d did not configure strategic facilities" % seed)
		for path in game.paths:
			_check(path[path.size() - 1] == Vector2i(game.BASE_CELL), "Seed %d route missed the vault" % seed)
			for index in range(1, path.size()):
				_check(Vector2(path[index]).distance_to(Vector2(path[index - 1])) == 1.0, "Seed %d has a disconnected route" % seed)
		signatures[str(game.map_data.floor_cells)] = true
	_check(signatures.size() >= 23, "Generated room layouts lack variety")

	game._generate_map(8675309)
	var initial_explored: int = game.exploration.get_explored_count()
	_check(initial_explored > 0, "Starting room was not revealed")
	game.exploration.update_visibility(Vector2i.ZERO)
	_check(game.exploration.get_explored_count() > initial_explored, "Exploration memory did not grow")
	game.exploration.update_from_grid_position(game.player_pos, true)

	var test_pad: Dictionary = game.pads[0]
	game.player_pos = test_pad.pos
	game._select_tower_option(1)
	_check(test_pad.tower_family == "arc", "Tower family selection was not integrated")
	game.credits = 2000.0
	for step in 90:
		game._update_construction(0.05)
	_check(test_pad.level == 2, "Tower did not pause at its specialization choice")
	game._select_tower_option(0)
	_check(not str(test_pad.specialization).is_empty(), "Tower specialization was not installed")

	game.wave = 1
	game.current_composition = ["drone"]
	game._spawn_enemy(0)
	var pulse_target: Dictionary = game.enemies[0]
	pulse_target.pos = game.player_pos + Vector2(1, 0)
	var health_before_shock: float = pulse_target.hp
	game._activate_shock_pulse()
	_check(pulse_target.hp < health_before_shock, "Shock pulse did not damage a nearby enemy")
	game.enemies.clear()
	game.abilities.reset()

	game.player_pos = game.BASE_CELL
	game.base_health = 12
	game.credits = 100.0
	game._activate_emergency_repair()
	_check(game.base_health > 12 and game.credits < 100.0, "Emergency repair did not exchange credits for integrity")
	game.base_health = 20
	game.engineer_toolkit.reset()
	var barrier_cell: Vector2i = game.map_data.routes[0][1]
	var barrier_result: Dictionary = game.engineer_toolkit.deploy_barricade(barrier_cell, game.walkable_cells, {})
	_check(barrier_result.success, "Barricade could not be deployed on a valid route")

	game.credits = 5000.0
	for index in range(game.pads.size()):
		var pad: Dictionary = game.pads[index]
		pad.level = 0
		game.defense_loadout.assign_family(pad, game.defense_loadout.FAMILIES[index % 3])
		pad.level = 3
		var branches: Array = game.defense_loadout.get_specialization_ids(pad.tower_family)
		pad.specialization = branches[0]

	# A fully restored reserve bus must sustain a normal late-game load. If a
	# sapper destroys the relay, maintenance during combat must bring every pad
	# back online instead of leaving the later-index weapons permanently silent.
	for facility_id in game.power_network.facilities:
		game.power_network.repair_facility(facility_id, 1000.0)
	game._update_power_capacity()
	game.power_network.update(0.0)
	var late_game_pad: Dictionary = game.pads[game.pads.size() - 1]
	_check(game.power_network.capacity == 60.0, "Restored grid relay did not connect reserve capacity")
	_check(game._is_pad_powered(late_game_pad), "Late-game tower was shed under the normal upgraded load")
	game.power_network.damage_facility("grid_relay", 1000.0)
	game._update_power_capacity()
	game.power_network.update(0.0)
	_check(not game._is_pad_powered(late_game_pad), "Tower remained powered after its grid relay was destroyed")
	game.player_pos = Vector2(game.power_network.facilities["grid_relay"].position)
	Input.action_press("interact")
	game._repair_nearby_facility(4.0)
	Input.action_release("interact")
	game._update_power_capacity()
	game.power_network.update(0.0)
	_check(game.power_network.is_online("grid_relay"), "Engineer could not repair the grid relay during an incursion")
	_check(game._is_pad_powered(late_game_pad), "Late-game tower did not recover after grid relay repair")

	game.power_network.capacity = 100.0
	game.engineer_toolkit.barricades.clear()
	game.wave = 0
	game.total_kills = 0
	game.lockdown_director.reset()

	for sector_index in range(3):
		var objective_start: Dictionary = game.lockdown_director.activate_next_objective()
		_check(objective_start.success, "Sector %d objective did not activate" % (sector_index + 1))
		game.lockdown_director.add_objective_repair(1000.0)
		var facility_id: String = game.facility_ids_by_objective[sector_index]
		game.power_network.repair_facility(facility_id, 1000.0)
		game.lockdown_director.begin_incursion()
		game._update_lockdown(30.0)
		_check(game.wave_active, "Sector %d incursion did not begin after its telegraph" % (sector_index + 1))
		_simulate_incursion(game, "sector %d" % (sector_index + 1))
		if game.lockdown_director.state == game.lockdown_director.STATE_DIRECTIVE:
			var choices: Array = game.lockdown_director.get_directive_choices()
			game.lockdown_director.choose_directive(choices[0].id)

	_check(game.lockdown_director.can_trigger_final_breach(), "Three secured objectives did not unlock the final breach")
	game._request_wave()
	game._update_lockdown(30.0)
	_check(game.wave_active and game.current_incursion_final, "Final breach did not begin")
	_simulate_incursion(game, "final breach")

	_check(game.game_state == "victory", "Completing lockdown did not trigger victory")
	_check(game.total_kills > 0, "Defenses did not destroy any enemies")
	_check(game.enemies.is_empty(), "Enemies remained after victory")
	_check(game.campaign.score > 0, "Completed level did not produce a score")
	_check("SCORE" in game.overlay_body.text, "Victory screen did not present the final score")
	_check(game.overlay_button.text == "NEXT LEVEL", "First victory did not offer campaign progression")
	game._overlay_action()
	_check(game.campaign.current_level_index == 1, "Victory did not advance to campaign level two")
	_check(game.map_seed == int(game.campaign.get_current_level().map_seed), "Next level did not load its authored map seed")
	_check(game.base_health == int(game.campaign.get_current_level().starting_integrity), "Next level did not apply its integrity challenge")

	if failures.is_empty():
		print("LOCKDOWN SMOKE TEST PASSED: rooms, power, fog, tools, towers, objectives, directives, sappers, and final breach")
		quit(0)
	else:
		for failure in failures:
			push_error("LOCKDOWN SMOKE TEST FAILED: " + failure)
		quit(1)


func _simulate_incursion(game, label: String) -> void:
	var steps := 0
	while game.wave_active and game.game_state == "playing" and steps < 16000:
		game._update_wave(0.05)
		game._update_enemies(0.05)
		game._update_turrets(0.05)
		game._update_effects(0.05)
		game.power_network.update(0.05)
		game.engineer_toolkit.update(0.05)
		steps += 1
	_check(steps < 16000, "%s did not terminate" % label)
	_check(game.game_state != "defeat", "%s unexpectedly destroyed the vault" % label)
