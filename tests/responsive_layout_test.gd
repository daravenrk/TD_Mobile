extends SceneTree

const GameScript = preload("res://scripts/main.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _inside_view(control: Control, size: Vector2) -> bool:
	var rect := Rect2(control.position, control.size)
	return rect.position.x >= -0.01 and rect.position.y >= -0.01 and rect.end.x <= size.x + 0.01 and rect.end.y <= size.y + 0.01


func _run() -> void:
	var game = GameScript.new()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.game_state = "playing"
	game.overlay.visible = false

	var portrait_size := Vector2(720, 1280)
	game._apply_responsive_layout(portrait_size)
	game._update_hud()
	_check(game.is_compact_layout, "Portrait viewport did not activate the compact HUD")
	_check(not game.objective_label.visible, "Compact HUD did not collapse the objective panel")
	_check(not game.shock_button.visible and not game.repair_button.visible and not game.barricade_button.visible, "Desktop action rail remained visible on mobile")
	for button in game.mobile_context_buttons:
		_check(button.visible, "A mobile context button was hidden")
		_check(_inside_view(button, portrait_size), "A mobile context button escaped the portrait safe area")
	_check(_inside_view(game.top_bar, portrait_size), "Mobile header escaped the portrait safe area")
	_check(_inside_view(game.intel_label, portrait_size), "Mobile intel strip escaped the portrait safe area")

	var relay: Dictionary = game.power_network.facilities["grid_relay"]
	game.player_pos = Vector2(relay.position)
	game._update_hud()
	_check(game.mobile_context_buttons[0].get_meta("action") == "work", "Facility context did not expose the mobile work action")
	_check(not game.mobile_context_buttons[0].disabled, "Mobile work action was disabled beside a damaged facility")
	game._mobile_context_button_down(0)
	_check(Input.is_action_pressed("interact"), "Holding the mobile work button did not press interact")
	game._mobile_context_button_up(0)
	_check(not Input.is_action_pressed("interact"), "Releasing the mobile work button left interact stuck")

	var empty_pad: Dictionary = game.pads[0]
	empty_pad.level = 0
	empty_pad.tower_family = "ballistic"
	game.player_pos = empty_pad.pos
	game._update_hud()
	for index in range(4):
		_check(game.mobile_context_buttons[index].get_meta("action") == "tower_%d" % index, "Empty pad did not expose all four mobile blueprints")
	game._mobile_context_button_down(1)
	_check(empty_pad.tower_family == "arc", "Mobile ARC blueprint button did not select its tower family")

	var landscape_size := Vector2(854, 480)
	game._apply_responsive_layout(landscape_size)
	_check(game.is_compact_layout, "Narrow landscape viewport did not keep the compact HUD")
	for button in game.mobile_context_buttons:
		_check(_inside_view(button, landscape_size), "A mobile context button escaped the landscape safe area")

	var desktop_size := Vector2(1280, 720)
	game._apply_responsive_layout(desktop_size)
	game.player_pos = Vector2(relay.position)
	game._update_hud()
	_check(not game.is_compact_layout, "Desktop viewport retained the compact HUD")
	_check(game.objective_label.visible, "Desktop objective panel was not restored")
	_check(game.shock_button.visible and game.repair_button.visible and game.barricade_button.visible, "Desktop action buttons were not restored")
	for button in game.mobile_context_buttons:
		_check(not button.visible, "Mobile context controls remained visible on desktop")
	_check(game.prompt_label.text.begins_with("HOLD E"), "Desktop maintenance prompt lost its keyboard hint")

	game.overlay.visible = true
	game._apply_responsive_layout(portrait_size)
	_check(_inside_view(game.overlay_card, portrait_size), "Overlay card escaped the portrait viewport")

	Input.action_release("interact")
	if failures.is_empty():
		print("RESPONSIVE LAYOUT TEST PASSED: desktop, portrait, landscape, touch work, and tower context")
		quit(0)
	else:
		for failure in failures:
			push_error("RESPONSIVE LAYOUT TEST FAILED: " + failure)
		quit(1)
