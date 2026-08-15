extends SceneTree

const GameScript = preload("res://scripts/main.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = GameScript.new()
	root.add_child(game)
	await process_frame
	game._overlay_action()
	var start: Vector2 = game.player_pos

	# Exercise the real Input singleton and physics loop from the generated
	# starting room. At least one screen direction must move the engineer.
	for action in ["move_up", "move_right", "move_down", "move_left"]:
		Input.action_press(action)
		for frame in range(8):
			await physics_frame
		Input.action_release(action)
		if game.player_pos.distance_to(start) > 0.05:
			break
	if game.player_pos.distance_to(start) <= 0.05:
		push_error("MOVEMENT FLOW TEST FAILED: keyboard input could not leave the generated start cell")
		quit(1)
		return

	# Choose a distant walkable room cell and verify routed tap movement reaches it
	# without becoming stuck against solid room walls.
	var destination: Vector2i = game.map_data.floor_cells[0]
	for cell in game.map_data.floor_cells:
		if Vector2(cell).distance_to(game.player_pos) > 10.0:
			destination = cell
			break
	game._set_tap_destination(Vector2(destination))
	if game.tap_route.is_empty():
		push_error("MOVEMENT FLOW TEST FAILED: tap destination did not produce a route")
		quit(1)
		return
	var steps := 0
	while game.has_tap_target and steps < 2000:
		game._update_player(0.05)
		steps += 1
	if game.has_tap_target or game.player_pos.distance_to(Vector2(destination)) > 0.2:
		push_error("MOVEMENT FLOW TEST FAILED: routed tap movement became stuck")
		quit(1)
		return

	print("MOVEMENT FLOW TEST PASSED: keyboard wall sliding and routed tap navigation")
	quit(0)
