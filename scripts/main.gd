extends Node2D

const EngineerAbilitiesScript = preload("res://scripts/engineer_abilities.gd")
const ExplorationSystemScript = preload("res://scripts/exploration_system.gd")
const CombatCatalogScript = preload("res://scripts/combat_catalog.gd")

const GRID_SIZE := Vector2i(30, 22)
const TILE_W := 64.0
const TILE_H := 32.0
const PLAYER_SPEED := 3.4
const MAX_WAVES := 6
const BUILD_PAD_COUNT := 14
const RANDOM_BLOCKER_COUNT := 46

const FLOOR_A := Color("#26343d")
const FLOOR_B := Color("#2b3b45")
const PATH_COLOR := Color("#59636b")
const EDGE_COLOR := Color("#142027")
const CYAN := Color("#45e0d0")
const ORANGE := Color("#ffad42")
const RED := Color("#f25b5b")
const CREAM := Color("#ecf4e8")
const DIM := Color("#9aabb0")

var BASE_CELL := Vector2(26, 11)
var player_pos := Vector2(24.0, 14.0)
var player_facing := Vector2(0.0, 1.0)
var tap_target := Vector2.ZERO
var has_tap_target := false
var camera_pos := player_pos
var map_seed := 0
var map_rng := RandomNumberGenerator.new()
var abilities = EngineerAbilitiesScript.new()
var exploration = ExplorationSystemScript.new(GRID_SIZE, 5)

var credits := 190.0
var base_health := 20
var wave := 0
var game_state := "briefing"
var wave_active := false
var enemies_to_spawn := 0
var spawned_this_wave := 0
var spawn_timer := 0.0
var intermission_timer := 0.0
var status_message := ""
var status_timer := 0.0
var total_kills := 0

var paths: Array = []
var path_cells := {}
var pads: Array = []
var enemies: Array = []
var tracers: Array = []
var particles: Array = []
var shock_waves: Array = []
var blocked_cells := {}

var title_label: Label
var resources_label: Label
var wave_label: Label
var objective_label: Label
var prompt_label: Label
var message_label: Label
var intel_label: Label
var wave_button: Button
var shock_button: Button
var repair_button: Button
var overlay: ColorRect
var overlay_title: Label
var overlay_body: Label
var overlay_button: Button


func _ready() -> void:
	_generate_map()
	_build_hud()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()
	queue_redraw()


func _generate_map(forced_seed: int = -1) -> void:
	paths.clear()
	path_cells.clear()
	pads.clear()
	blocked_cells.clear()
	map_seed = forced_seed if forced_seed >= 0 else randi()
	map_rng.seed = map_seed

	BASE_CELL = Vector2(GRID_SIZE.x - 4, map_rng.randi_range(9, 13))
	var entries := [
		Vector2(0, map_rng.randi_range(3, 9)),
		Vector2(map_rng.randi_range(7, 17), 0),
		Vector2(map_rng.randi_range(3, 15), GRID_SIZE.y - 1)
	]
	for entry in entries:
		var path := _generate_route(entry, BASE_CELL)
		paths.append(path)
		for cell in path:
			path_cells[Vector2i(cell)] = true

	player_pos = Vector2(BASE_CELL.x - 2.0, clampf(BASE_CELL.y + 3.0, 1.0, GRID_SIZE.y - 2.0))
	_place_build_pads()
	_place_blockers()
	camera_pos = player_pos
	has_tap_target = false
	exploration.reset(GRID_SIZE, 5)
	exploration.update_from_grid_position(player_pos, true)


func _generate_route(start: Vector2, destination: Vector2) -> Array:
	# A randomized monotone walk always reaches the vault, never loops, and
	# produces a different set of corners for every sector seed.
	var route: Array = [start]
	var current := Vector2i(start)
	var goal := Vector2i(destination)
	while current != goal:
		var can_move_x := current.x != goal.x
		var can_move_y := current.y != goal.y
		var move_x := can_move_x and (not can_move_y or map_rng.randf() < 0.58)
		if move_x:
			current.x += signi(goal.x - current.x)
		else:
			current.y += signi(goal.y - current.y)
		route.append(Vector2(current))
	return route


func _place_build_pads() -> void:
	var candidates := {}
	var directions := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for path in paths:
		for path_point in path:
			var cell := Vector2i(path_point)
			for direction in directions:
				var candidate: Vector2i = cell + direction
				if candidate.x <= 0 or candidate.y <= 0 or candidate.x >= GRID_SIZE.x - 1 or candidate.y >= GRID_SIZE.y - 1:
					continue
				if path_cells.has(candidate) or Vector2(candidate).distance_to(BASE_CELL) < 2.2:
					continue
				candidates[candidate] = true

	var available: Array = candidates.keys()
	_shuffle_with_rng(available)
	for candidate in available:
		var separated := true
		for existing_pad in pads:
			if existing_pad.pos.distance_to(Vector2(candidate)) < 2.0:
				separated = false
				break
		if not separated:
			continue
		pads.append({
			"pos": Vector2(candidate),
			"level": 0,
			"progress": 0.0,
			"cooldown": map_rng.randf_range(0.0, 0.5),
			"pulse": map_rng.randf_range(0.0, TAU)
		})
		if pads.size() >= BUILD_PAD_COUNT:
			break


func _place_blockers() -> void:
	var pad_cells := {}
	for pad in pads:
		pad_cells[Vector2i(pad.pos)] = true
	var attempts := 0
	while blocked_cells.size() < RANDOM_BLOCKER_COUNT and attempts < 2000:
		attempts += 1
		var cell := Vector2i(map_rng.randi_range(0, GRID_SIZE.x - 1), map_rng.randi_range(0, GRID_SIZE.y - 1))
		if path_cells.has(cell) or pad_cells.has(cell):
			continue
		if Vector2(cell).distance_to(BASE_CELL) < 3.0 or Vector2(cell).distance_to(player_pos) < 2.0:
			continue
		blocked_cells[cell] = true


func _shuffle_with_rng(values: Array) -> void:
	for i in range(values.size() - 1, 0, -1):
		var swap_index := map_rng.randi_range(0, i)
		var temporary = values[i]
		values[i] = values[swap_index]
		values[swap_index] = temporary


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var top_bar := Panel.new()
	top_bar.position = Vector2(20, 18)
	top_bar.size = Vector2(1240, 70)
	top_bar.add_theme_stylebox_override("panel", _panel_style(Color("#0d171dcc"), CYAN, 1))
	layer.add_child(top_bar)

	title_label = Label.new()
	title_label.text = "DEEPWATCH  //  SECTOR K-12"
	title_label.position = Vector2(22, 12)
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", CREAM)
	top_bar.add_child(title_label)

	resources_label = Label.new()
	resources_label.position = Vector2(22, 39)
	resources_label.add_theme_font_size_override("font_size", 14)
	top_bar.add_child(resources_label)

	wave_label = Label.new()
	wave_label.position = Vector2(655, 14)
	wave_label.size = Vector2(320, 42)
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wave_label.add_theme_font_size_override("font_size", 16)
	top_bar.add_child(wave_label)

	wave_button = Button.new()
	wave_button.text = "START WAVE"
	wave_button.position = Vector2(990, 12)
	wave_button.size = Vector2(225, 46)
	wave_button.add_theme_font_size_override("font_size", 16)
	wave_button.pressed.connect(_request_wave)
	top_bar.add_child(wave_button)

	objective_label = Label.new()
	objective_label.position = Vector2(22, 104)
	objective_label.size = Vector2(370, 116)
	objective_label.text = "MISSION\nExplore and hold all three access tunnels.\nStand on cyan pads to fund them.\nMove: WASD/tap  •  Q: shock  •  F: repair"
	objective_label.add_theme_font_size_override("font_size", 15)
	objective_label.add_theme_color_override("font_color", CREAM)
	objective_label.add_theme_stylebox_override("normal", _panel_style(Color("#0d171dbb"), Color("#334851"), 1))
	objective_label.add_theme_constant_override("outline_size", 4)
	objective_label.add_theme_color_override("font_outline_color", Color("#0d171d"))
	layer.add_child(objective_label)

	prompt_label = Label.new()
	prompt_label.position = Vector2(420, 630)
	prompt_label.size = Vector2(440, 54)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt_label.add_theme_font_size_override("font_size", 18)
	prompt_label.add_theme_stylebox_override("normal", _panel_style(Color("#0d171de6"), CYAN, 1))
	layer.add_child(prompt_label)

	message_label = Label.new()
	message_label.position = Vector2(440, 104)
	message_label.size = Vector2(400, 40)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 18)
	message_label.add_theme_color_override("font_color", ORANGE)
	layer.add_child(message_label)

	intel_label = Label.new()
	intel_label.position = Vector2(22, 630)
	intel_label.size = Vector2(360, 62)
	intel_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	intel_label.add_theme_font_size_override("font_size", 14)
	intel_label.add_theme_color_override("font_color", DIM)
	intel_label.add_theme_stylebox_override("normal", _panel_style(Color("#0d171dcc"), Color("#334851"), 1))
	layer.add_child(intel_label)

	shock_button = Button.new()
	shock_button.position = Vector2(890, 642)
	shock_button.size = Vector2(165, 48)
	shock_button.add_theme_font_size_override("font_size", 14)
	shock_button.pressed.connect(_activate_shock_pulse)
	layer.add_child(shock_button)

	repair_button = Button.new()
	repair_button.position = Vector2(1065, 642)
	repair_button.size = Vector2(190, 48)
	repair_button.add_theme_font_size_override("font_size", 14)
	repair_button.pressed.connect(_activate_emergency_repair)
	layer.add_child(repair_button)

	overlay = ColorRect.new()
	overlay.color = Color("#071015e8")
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(overlay)

	var card := Panel.new()
	card.position = Vector2(350, 160)
	card.size = Vector2(580, 400)
	card.add_theme_stylebox_override("panel", _panel_style(Color("#14242c"), CYAN, 2))
	overlay.add_child(card)

	overlay_title = Label.new()
	overlay_title.position = Vector2(36, 35)
	overlay_title.size = Vector2(508, 62)
	overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_title.add_theme_font_size_override("font_size", 32)
	overlay_title.add_theme_color_override("font_color", CREAM)
	card.add_child(overlay_title)

	overlay_body = Label.new()
	overlay_body.position = Vector2(58, 112)
	overlay_body.size = Vector2(464, 170)
	overlay_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_body.add_theme_font_size_override("font_size", 17)
	overlay_body.add_theme_color_override("font_color", DIM)
	card.add_child(overlay_body)

	overlay_button = Button.new()
	overlay_button.position = Vector2(165, 315)
	overlay_button.size = Vector2(250, 54)
	overlay_button.add_theme_font_size_override("font_size", 18)
	overlay_button.pressed.connect(_overlay_action)
	card.add_child(overlay_button)

	_show_briefing()
	_update_hud()


func _panel_style(color: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _show_briefing() -> void:
	overlay.visible = true
	overlay_title.text = "DEEPWATCH"
	overlay_body.text = "You are the last combat engineer below Sector K-12. Three breached access tunnels converge on the command vault.\n\nMove onto construction pads to transfer credits and assemble sentry turrets. Stay longer to upgrade them. Survive six incursions."
	overlay_button.text = "ENTER THE BASE"


func _overlay_action() -> void:
	if game_state == "briefing":
		game_state = "playing"
		overlay.visible = false
		_flash_message("Sector link established")
	elif game_state == "victory" or game_state == "defeat":
		_reset_game()


func _reset_game() -> void:
	credits = 190.0
	base_health = 20
	wave = 0
	total_kills = 0
	wave_active = false
	enemies.clear()
	tracers.clear()
	particles.clear()
	shock_waves.clear()
	abilities.reset()
	_generate_map()
	game_state = "playing"
	overlay.visible = false
	_flash_message("Defense grid reset")


func _on_viewport_resized() -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("start_wave"):
		_request_wave()
	if event.is_action_pressed("restart") and (game_state == "victory" or game_state == "defeat"):
		_reset_game()
	if game_state != "playing":
		return
	if event.is_action_pressed("shock_pulse"):
		_activate_shock_pulse()
	if event.is_action_pressed("emergency_repair"):
		_activate_emergency_repair()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if event.position.y > 100.0 and event.position.y < get_viewport_rect().size.y - 70.0:
			tap_target = screen_to_grid(event.position)
			tap_target.x = clampf(tap_target.x, 0.0, GRID_SIZE.x - 1.0)
			tap_target.y = clampf(tap_target.y, 0.0, GRID_SIZE.y - 1.0)
			has_tap_target = true
	if event is InputEventScreenTouch and event.pressed:
		tap_target = screen_to_grid(event.position)
		tap_target.x = clampf(tap_target.x, 0.0, GRID_SIZE.x - 1.0)
		tap_target.y = clampf(tap_target.y, 0.0, GRID_SIZE.y - 1.0)
		has_tap_target = true


func _physics_process(delta: float) -> void:
	if game_state != "playing":
		queue_redraw()
		return

	_update_player(delta)
	var camera_weight := 1.0 - exp(-5.5 * delta)
	camera_pos = camera_pos.lerp(player_pos, camera_weight)
	exploration.update_from_grid_position(player_pos)
	abilities.update_cooldowns(delta)
	_update_construction(delta)
	_update_wave(delta)
	_update_enemies(delta)
	_update_turrets(delta)
	_update_effects(delta)
	_update_hud()
	queue_redraw()


func _update_player(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var move := Vector2.ZERO
	if input.length() > 0.05:
		# Screen-aligned controls converted into grid axes for an isometric floor.
		move = Vector2(input.x + input.y, input.y - input.x).normalized()
		has_tap_target = false
	elif has_tap_target:
		var offset := tap_target - player_pos
		if offset.length() < 0.08:
			has_tap_target = false
		else:
			move = offset.normalized()

	if move != Vector2.ZERO:
		player_facing = move
		var next := player_pos + move * PLAYER_SPEED * delta
		next.x = clampf(next.x, 0.15, GRID_SIZE.x - 1.15)
		next.y = clampf(next.y, 0.15, GRID_SIZE.y - 1.15)
		if not blocked_cells.has(Vector2i(roundi(next.x), roundi(next.y))):
			player_pos = next


func _activate_shock_pulse() -> void:
	if game_state != "playing":
		return
	var result: Dictionary = abilities.activate_shock(player_pos, enemies)
	if not result.activated:
		_flash_message("Shock recharging  %.1fs" % result.cooldown_remaining)
		return
	shock_waves.append({"pos": player_pos, "life": 0.55, "max_life": 0.55, "radius": abilities.shock_radius})
	for defeated_enemy in result.defeated:
		if defeated_enemy in enemies:
			credits += defeated_enemy.reward
			total_kills += 1
			_spawn_burst(defeated_enemy.pos, CYAN, 9)
			enemies.erase(defeated_enemy)
	_flash_message("Shock pulse hit %d hostiles" % result.affected.size())


func _activate_emergency_repair() -> void:
	if game_state != "playing":
		return
	if player_pos.distance_to(BASE_CELL) > 2.6:
		_flash_message("Return to the command vault to repair")
		return
	var result: Dictionary = abilities.activate_emergency_repair(base_health, 20, credits)
	if not result.activated:
		var reason: String = result.reason
		if reason == "vault_full":
			_flash_message("Vault integrity already full")
		elif reason == "insufficient_credits":
			_flash_message("Need at least 14 credits for repairs")
		else:
			_flash_message("Repair rig recharging  %.1fs" % result.cooldown_remaining)
		return
	base_health = result.base_health
	credits = result.credits
	_spawn_burst(BASE_CELL, CYAN, 18)
	_flash_message("Emergency repair restored %d integrity" % result.repaired)


func _update_construction(delta: float) -> void:
	var active_pad = null
	for pad in pads:
		if player_pos.distance_to(pad.pos) < 0.48 and pad.level < 3:
			active_pad = pad
			break

	if active_pad == null:
		return

	var level: int = active_pad.level
	var required := _upgrade_cost(level)
	if credits <= 0.0:
		return
	var transfer_rate := 48.0 + level * 15.0
	var amount := minf(credits, transfer_rate * delta)
	amount = minf(amount, required - active_pad.progress)
	credits -= amount
	active_pad.progress += amount
	active_pad.pulse += delta * 7.0

	if active_pad.progress >= required - 0.01:
		active_pad.level += 1
		active_pad.progress = 0.0
		_flash_message("Sentry upgraded to MK-%d" % active_pad.level)
		_spawn_burst(active_pad.pos, CYAN, 12)


func _upgrade_cost(current_level: int) -> float:
	return [70.0, 105.0, 150.0][current_level]


func _request_wave() -> void:
	if game_state != "playing" or wave_active or wave >= MAX_WAVES:
		return
	wave += 1
	wave_active = true
	spawned_this_wave = 0
	enemies_to_spawn = CombatCatalogScript.get_wave_composition(wave).size()
	spawn_timer = 0.25
	wave_button.disabled = true
	_flash_message("Incursion %d detected" % wave)


func _update_wave(delta: float) -> void:
	if not wave_active:
		return
	if spawned_this_wave < enemies_to_spawn:
		spawn_timer -= delta
		if spawn_timer <= 0.0:
			_spawn_enemy(spawned_this_wave % paths.size())
			spawned_this_wave += 1
			spawn_timer = maxf(0.34, 0.88 - wave * 0.065)
	elif enemies.is_empty():
		wave_active = false
		credits += 35.0 + wave * 8.0
		if wave >= MAX_WAVES:
			_end_game(true)
		else:
			wave_button.disabled = false
			_flash_message("Wave clear  •  resupply received")


func _spawn_enemy(path_index: int) -> void:
	var enemy_type := CombatCatalogScript.get_wave_enemy_id(wave, spawned_this_wave)
	var enemy: Dictionary = CombatCatalogScript.make_enemy_state(enemy_type, wave, path_index)
	enemy.pos = paths[path_index][0]
	enemy.shield_regen_remaining = 0.0
	enemy.slow_remaining = 0.0
	enemy.slow_strength = 0.0
	enemy.armor_break_remaining = 0.0
	enemy.armor_break_amount = 0.0
	enemies.append(enemy)


func _update_enemies(delta: float) -> void:
	for i in range(enemies.size() - 1, -1, -1):
		var enemy = enemies[i]
		enemy.hit = maxf(0.0, enemy.hit - delta)
		enemy.slow_remaining = maxf(0.0, enemy.slow_remaining - delta)
		enemy.armor_break_remaining = maxf(0.0, enemy.armor_break_remaining - delta)
		if enemy.shield_regen_remaining > 0.0:
			enemy.shield_regen_remaining = maxf(0.0, enemy.shield_regen_remaining - delta)
		elif enemy.max_shield > 0.0 and enemy.shield < enemy.max_shield:
			enemy.shield = minf(enemy.max_shield, enemy.shield + enemy.shield_regen * delta)
		var path: Array = paths[enemy.path]
		if enemy.segment >= path.size() - 1:
			base_health -= enemy.damage
			_spawn_burst(BASE_CELL, RED, 14)
			enemies.remove_at(i)
			_flash_message("Vault perimeter hit  -%d" % enemy.damage)
			if base_health <= 0:
				_end_game(false)
			return
		var target: Vector2 = path[enemy.segment + 1]
		var distance: float = enemy.pos.distance_to(target)
		var slow_multiplier: float = 1.0 - enemy.slow_strength if enemy.slow_remaining > 0.0 else 1.0
		var travel: float = enemy.speed * slow_multiplier * delta
		if travel >= distance:
			enemy.pos = target
			enemy.segment += 1
		else:
			enemy.pos += enemy.pos.direction_to(target) * travel


func _update_turrets(delta: float) -> void:
	for pad in pads:
		if pad.level <= 0:
			continue
		pad.cooldown -= delta
		if pad.cooldown > 0.0:
			continue
		var tier: Dictionary = CombatCatalogScript.get_turret_tier(pad.level)
		var target = _find_target(pad.pos, tier.range)
		if target == null:
			continue
		var raw_damage: float = tier.damage
		if target.shield > 0.0:
			var absorbed := minf(target.shield, raw_damage)
			target.shield -= absorbed
			raw_damage -= absorbed
		var armor_break: float = target.armor_break_amount if target.armor_break_remaining > 0.0 else 0.0
		var effective_armor: float = maxf(0.0, target.armor - armor_break)
		target.hp -= CombatCatalogScript.calculate_hit(raw_damage, effective_armor, tier.armor_pierce)
		target.shield_regen_remaining = target.shield_regen_delay
		if tier.effect == "armor_break":
			target.armor_break_amount = maxf(target.armor_break_amount, tier.effect_strength)
			target.armor_break_remaining = tier.effect_duration
		elif tier.effect == "slow":
			target.slow_strength = maxf(target.slow_strength, tier.effect_strength)
			target.slow_remaining = tier.effect_duration
		target.hit = 0.12
		pad.cooldown = tier.cooldown
		tracers.append({"from": pad.pos, "to": target.pos, "life": 0.10, "max_life": 0.10})
		if target.hp <= 0.0:
			credits += target.reward
			total_kills += 1
			_spawn_burst(target.pos, ORANGE, 7)
			enemies.erase(target)


func _find_target(from: Vector2, range_tiles: float):
	var best = null
	var best_progress := -1.0
	for enemy in enemies:
		if from.distance_to(enemy.pos) <= range_tiles:
			var progress: float = enemy.segment + (enemy.pos - paths[enemy.path][enemy.segment]).length()
			if progress > best_progress:
				best_progress = progress
				best = enemy
	return best


func _update_effects(delta: float) -> void:
	for i in range(tracers.size() - 1, -1, -1):
		tracers[i].life -= delta
		if tracers[i].life <= 0.0:
			tracers.remove_at(i)
	for i in range(particles.size() - 1, -1, -1):
		particles[i].life -= delta
		particles[i].offset += particles[i].velocity * delta
		particles[i].velocity *= 0.92
		if particles[i].life <= 0.0:
			particles.remove_at(i)
	for i in range(shock_waves.size() - 1, -1, -1):
		shock_waves[i].life -= delta
		if shock_waves[i].life <= 0.0:
			shock_waves.remove_at(i)
	if status_timer > 0.0:
		status_timer -= delta


func _spawn_burst(world_pos: Vector2, color: Color, count: int) -> void:
	for i in count:
		particles.append({
			"pos": world_pos,
			"offset": Vector2.ZERO,
			"velocity": Vector2.from_angle(randf() * TAU) * randf_range(25.0, 80.0),
			"life": randf_range(0.25, 0.65),
			"color": color
		})


func _flash_message(text: String) -> void:
	status_message = text
	status_timer = 2.3


func _end_game(won: bool) -> void:
	game_state = "victory" if won else "defeat"
	wave_active = false
	wave_button.disabled = true
	overlay.visible = true
	if won:
		overlay_title.text = "SECTOR SECURED"
		overlay_body.text = "All six incursions were repelled. The command vault remains sealed.\n\nHostiles neutralized: %d\nVault integrity: %d / 20" % [total_kills, base_health]
		overlay_button.text = "RUN NEW SHIFT"
	else:
		overlay_title.text = "VAULT BREACHED"
		overlay_body.text = "The defense line collapsed before relief arrived. Reposition your early sentries and upgrade the convergence points.\n\nHostiles neutralized: %d\nIncursion reached: %d / %d" % [total_kills, wave, MAX_WAVES]
		overlay_button.text = "RETRY SHIFT"


func _update_hud() -> void:
	var visible_contacts := 0
	for enemy in enemies:
		if exploration.is_visible(Vector2i(roundi(enemy.pos.x), roundi(enemy.pos.y))):
			visible_contacts += 1
	resources_label.text = "CREDITS  %03d     VAULT INTEGRITY  %02d / 20     LOCAL CONTACTS  %02d" % [floori(credits), base_health, visible_contacts]
	wave_label.text = "SECTOR %08X   •   INCURSION  %d / %d" % [map_seed & 0xFFFFFFFF, wave, MAX_WAVES]
	wave_button.visible = not wave_active and wave < MAX_WAVES
	wave_button.disabled = game_state != "playing"
	message_label.text = status_message if status_timer > 0.0 else ""
	var explored_percent := floori(100.0 * exploration.get_explored_count() / float(GRID_SIZE.x * GRID_SIZE.y))
	intel_label.text = "LOCAL SCAN  %d CONTACTS\nSECTOR MAPPED  %d%%" % [visible_contacts, explored_percent]
	var ability_state: Dictionary = abilities.get_hud_state()
	var shock_state: Dictionary = ability_state.shock_pulse
	var repair_state: Dictionary = ability_state.emergency_repair
	shock_button.text = "Q  SHOCK  %s" % ("READY" if shock_state.ready else "%.1fs" % shock_state.cooldown_remaining)
	repair_button.text = "F  VAULT REPAIR  %s" % ("READY" if repair_state.cooldown_ready else "%.1fs" % repair_state.cooldown_remaining)
	shock_button.disabled = not shock_state.ready
	repair_button.disabled = not repair_state.cooldown_ready

	var nearby = null
	for pad in pads:
		if player_pos.distance_to(pad.pos) < 0.55:
			nearby = pad
			break
	if nearby != null and nearby.level < 3:
		var cost := _upgrade_cost(nearby.level)
		var target_name := "CONSTRUCT MK-1" if nearby.level == 0 else "UPGRADE TO MK-%d" % (nearby.level + 1)
		prompt_label.text = "%s  •  %d / %d CREDITS" % [target_name, floori(nearby.progress), floori(cost)]
		prompt_label.visible = true
	elif nearby != null:
		prompt_label.text = "SENTRY AT MAXIMUM OUTPUT"
		prompt_label.visible = true
	else:
		prompt_label.visible = false


func grid_to_screen(grid_pos: Vector2) -> Vector2:
	var viewport_center := get_viewport_rect().size * Vector2(0.5, 0.52)
	return viewport_center + _grid_to_iso(grid_pos) - _grid_to_iso(camera_pos)


func screen_to_grid(screen_pos: Vector2) -> Vector2:
	var viewport_center := get_viewport_rect().size * Vector2(0.5, 0.52)
	var local := screen_pos - viewport_center + _grid_to_iso(camera_pos)
	return Vector2(local.x / TILE_W + local.y / TILE_H, local.y / TILE_H - local.x / TILE_W)


func _grid_to_iso(grid_pos: Vector2) -> Vector2:
	return Vector2((grid_pos.x - grid_pos.y) * TILE_W * 0.5, (grid_pos.x + grid_pos.y) * TILE_H * 0.5)


func _draw() -> void:
	_draw_backdrop()
	_draw_floor()
	_draw_world_objects()
	_draw_effects()


func _draw_backdrop() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Color("#071015"))
	for i in 18:
		var y := 110.0 + i * 34.0
		draw_line(Vector2(0, y), Vector2(size.x, y), Color("#102029"), 1.0)


func _draw_floor() -> void:
	for sum in range(GRID_SIZE.x + GRID_SIZE.y - 1):
		for x in range(GRID_SIZE.x):
			var y := sum - x
			if y < 0 or y >= GRID_SIZE.y:
				continue
			var cell := Vector2i(x, y)
			var screen_position := grid_to_screen(Vector2(cell))
			var viewport_size := get_viewport_rect().size
			if screen_position.x < -TILE_W or screen_position.x > viewport_size.x + TILE_W or screen_position.y < 70.0 or screen_position.y > viewport_size.y + TILE_H:
				continue
			var color := FLOOR_A if (x + y) % 2 == 0 else FLOOR_B
			var fog_state := exploration.get_cell_state(cell)
			if fog_state == exploration.UNSEEN:
				color = Color("#091116")
			elif path_cells.has(cell):
				color = PATH_COLOR.darkened(0.04 if (x + y) % 2 == 0 else 0.11)
			if fog_state == exploration.EXPLORED:
				color = color.darkened(0.55)
			_draw_tile(Vector2(cell), color)
			if path_cells.has(cell) and fog_state != exploration.UNSEEN:
				var center := grid_to_screen(Vector2(cell))
				draw_circle(center, 2.3, Color("#82919888"))


func _draw_tile(cell: Vector2, color: Color) -> void:
	var p := grid_to_screen(cell)
	var points := PackedVector2Array([
		p + Vector2(0, -TILE_H * 0.5),
		p + Vector2(TILE_W * 0.5, 0),
		p + Vector2(0, TILE_H * 0.5),
		p + Vector2(-TILE_W * 0.5, 0)
	])
	draw_colored_polygon(points, color)
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), EDGE_COLOR, 1.0)


func _draw_world_objects() -> void:
	var drawables: Array = []
	for cell in blocked_cells:
		if exploration.is_explored(cell):
			drawables.append({"depth": cell.x + cell.y, "kind": "block", "data": cell})
	for pad in pads:
		if exploration.is_explored(Vector2i(pad.pos)):
			drawables.append({"depth": pad.pos.x + pad.pos.y + 0.05, "kind": "pad", "data": pad})
	for enemy in enemies:
		if exploration.is_visible(Vector2i(roundi(enemy.pos.x), roundi(enemy.pos.y))):
			drawables.append({"depth": enemy.pos.x + enemy.pos.y + 0.18, "kind": "enemy", "data": enemy})
	if exploration.is_explored(Vector2i(BASE_CELL)):
		drawables.append({"depth": BASE_CELL.x + BASE_CELL.y + 0.2, "kind": "base", "data": null})
	drawables.append({"depth": player_pos.x + player_pos.y + 0.3, "kind": "player", "data": null})
	drawables.sort_custom(func(a, b): return a.depth < b.depth)
	for item in drawables:
		match item.kind:
			"block": _draw_block(Vector2(item.data))
			"pad": _draw_pad(item.data)
			"enemy": _draw_enemy(item.data)
			"base": _draw_base()
			"player": _draw_player()


func _draw_block(cell: Vector2) -> void:
	var p := grid_to_screen(cell)
	var top := p - Vector2(0, 17)
	var left := PackedVector2Array([p + Vector2(-23, -1), p + Vector2(0, 11), top + Vector2(0, 3), top + Vector2(-23, -9)])
	var right := PackedVector2Array([p + Vector2(23, -1), p + Vector2(0, 11), top + Vector2(0, 3), top + Vector2(23, -9)])
	var cap := PackedVector2Array([top + Vector2(0, -11), top + Vector2(23, 0), top + Vector2(0, 12), top + Vector2(-23, 0)])
	draw_colored_polygon(left, Color("#18262e"))
	draw_colored_polygon(right, Color("#22343d"))
	draw_colored_polygon(cap, Color("#3a4b52"))
	draw_circle(top, 3, ORANGE.darkened(0.2))


func _draw_pad(pad: Dictionary) -> void:
	var p := grid_to_screen(pad.pos)
	var glow := 0.65 + sin(Time.get_ticks_msec() * 0.004 + pad.pulse) * 0.2
	var ring_color := CYAN * glow
	draw_set_transform(p, 0.0, Vector2(1.0, 0.48))
	draw_circle(Vector2.ZERO, 21, Color("#11272d"))
	draw_arc(Vector2.ZERO, 21, 0, TAU, 32, ring_color, 3.0)
	draw_arc(Vector2.ZERO, 14, 0, TAU, 24, Color("#45e0d066"), 2.0)
	draw_set_transform(Vector2.ZERO)

	if pad.level == 0:
		var cost := _upgrade_cost(0)
		if pad.progress > 0:
			_draw_progress_arc(p, pad.progress / cost)
		return
	_draw_turret(p, pad.level)
	if pad.level < 3 and pad.progress > 0:
		_draw_progress_arc(p, pad.progress / _upgrade_cost(pad.level))


func _draw_progress_arc(p: Vector2, ratio: float) -> void:
	draw_set_transform(p, 0.0, Vector2(1.0, 0.48))
	draw_arc(Vector2.ZERO, 25, -PI * 0.5, -PI * 0.5 + TAU * ratio, 32, CREAM, 4.0)
	draw_set_transform(Vector2.ZERO)


func _draw_turret(p: Vector2, level: int) -> void:
	draw_colored_polygon(PackedVector2Array([p + Vector2(-15, -2), p + Vector2(0, 7), p + Vector2(15, -2), p + Vector2(0, -10)]), Color("#52646c"))
	draw_rect(Rect2(p + Vector2(-9, -24), Vector2(18, 18)), Color("#24343c"))
	draw_rect(Rect2(p + Vector2(-5, -28), Vector2(10, 12)), CYAN.darkened(0.25))
	draw_line(p + Vector2(1, -24), p + Vector2(17 + level * 3, -32), CREAM, 4.0)
	for i in level:
		draw_circle(p + Vector2(-7 + i * 7, 1), 2.0, ORANGE)


func _draw_enemy(enemy: Dictionary) -> void:
	var p := grid_to_screen(enemy.pos)
	var body_color := Color("#d65353")
	var scale_factor := 1.0
	if enemy.type == "runner":
		body_color = Color("#ff9d42")
		scale_factor = 0.78
	elif enemy.type == "brute":
		body_color = Color("#9b526f")
		scale_factor = 1.35
	elif enemy.type == "armored":
		body_color = Color("#77858d")
		scale_factor = 1.28
	elif enemy.type == "shielded":
		body_color = Color("#477a91")
		scale_factor = 1.08
	if enemy.hit > 0.0:
		body_color = Color.WHITE
	var w := 14.0 * scale_factor
	var h := 20.0 * scale_factor
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -h - 6), p + Vector2(w, -h * 0.55), p + Vector2(w, -4), p + Vector2(0, 3), p + Vector2(-w, -4), p + Vector2(-w, -h * 0.55)]), body_color)
	draw_circle(p + Vector2(-4 * scale_factor, -h * 0.65), 2.2, Color("#ffe673"))
	draw_circle(p + Vector2(4 * scale_factor, -h * 0.65), 2.2, Color("#ffe673"))
	var bar_width := 30.0 * scale_factor
	draw_rect(Rect2(p + Vector2(-bar_width * 0.5, -h - 14), Vector2(bar_width, 4)), Color("#121a1e"))
	draw_rect(Rect2(p + Vector2(-bar_width * 0.5, -h - 14), Vector2(bar_width * maxf(0.0, enemy.hp / enemy.max_hp), 4)), RED)
	if enemy.max_shield > 0.0:
		draw_rect(Rect2(p + Vector2(-bar_width * 0.5, -h - 19), Vector2(bar_width, 3)), Color("#121a1e"))
		draw_rect(Rect2(p + Vector2(-bar_width * 0.5, -h - 19), Vector2(bar_width * maxf(0.0, enemy.shield / enemy.max_shield), 3)), CYAN)
		if enemy.shield > 0.0:
			draw_arc(p + Vector2(0, -h * 0.5), w + 5.0, PI, TAU, 16, Color("#67f1ff99"), 2.0)
	if enemy.slow_remaining > 0.0:
		draw_circle(p + Vector2(0, 5), 4.0, CYAN.darkened(0.15))


func _draw_base() -> void:
	var p := grid_to_screen(BASE_CELL)
	draw_colored_polygon(PackedVector2Array([p + Vector2(-32, -5), p + Vector2(0, 12), p + Vector2(32, -5), p + Vector2(0, -22)]), Color("#41535b"))
	draw_rect(Rect2(p + Vector2(-22, -45), Vector2(44, 34)), Color("#17272f"))
	draw_colored_polygon(PackedVector2Array([p + Vector2(-22, -45), p + Vector2(0, -58), p + Vector2(22, -45), p + Vector2(0, -32)]), Color("#5b6a70"))
	draw_rect(Rect2(p + Vector2(-6, -38), Vector2(12, 27)), Color("#070d10"))
	draw_circle(p + Vector2(0, -46), 5, CYAN if base_health > 6 else RED)


func _draw_player() -> void:
	var p := grid_to_screen(player_pos)
	draw_set_transform(p, 0.0, Vector2(1.0, 0.48))
	draw_circle(Vector2.ZERO, 16, Color("#07101588"))
	draw_set_transform(Vector2.ZERO)
	draw_line(p + Vector2(-7, -9), p + Vector2(-10, 4), Color("#bcc9c7"), 5.0)
	draw_line(p + Vector2(7, -9), p + Vector2(10, 4), Color("#bcc9c7"), 5.0)
	draw_rect(Rect2(p + Vector2(-12, -35), Vector2(24, 25)), Color("#e0a43e"))
	draw_rect(Rect2(p + Vector2(-16, -31), Vector2(6, 18)), Color("#71868c"))
	draw_circle(p + Vector2(0, -41), 10, Color("#d6b18a"))
	draw_arc(p + Vector2(0, -42), 11, PI, TAU, 14, Color("#f1c84b"), 6.0)
	draw_rect(Rect2(p + Vector2(-8, -44), Vector2(16, 5)), Color("#26343d"))
	draw_circle(p + Vector2(5, -41), 2, CYAN)
	var tool_dir := Vector2(signf(player_facing.x - player_facing.y), 0.4).normalized()
	draw_line(p + Vector2(6, -24), p + Vector2(6, -24) + tool_dir * 18, Color("#d8edef"), 4.0)


func _draw_effects() -> void:
	for shock_wave in shock_waves:
		var progress: float = 1.0 - shock_wave.life / shock_wave.max_life
		var center := grid_to_screen(shock_wave.pos) + Vector2(0, -12)
		var radius: float = shock_wave.radius * TILE_W * 0.5 * progress
		draw_set_transform(center, 0.0, Vector2(1.0, 0.5))
		draw_arc(Vector2.ZERO, radius, 0, TAU, 48, Color(0.27, 0.95, 0.9, 1.0 - progress), 5.0)
		draw_set_transform(Vector2.ZERO)
	for tracer in tracers:
		var alpha: float = tracer.life / tracer.max_life
		draw_line(grid_to_screen(tracer.from) + Vector2(0, -28), grid_to_screen(tracer.to) + Vector2(0, -15), Color(0.4, 1.0, 0.9, alpha), 3.0)
	for particle in particles:
		var alpha: float = clampf(particle.life * 2.0, 0.0, 1.0)
		var color: Color = particle.color
		color.a = alpha
		draw_circle(grid_to_screen(particle.pos) + particle.offset + Vector2(0, -15), 2.5, color)
