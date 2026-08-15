extends Node2D

const EngineerAbilitiesScript = preload("res://scripts/engineer_abilities.gd")
const ExplorationSystemScript = preload("res://scripts/exploration_system.gd")
const CombatCatalogScript = preload("res://scripts/combat_catalog.gd")
const RoomMapGeneratorScript = preload("res://scripts/room_map_generator.gd")
const PowerNetworkScript = preload("res://scripts/power_network.gd")
const LockdownDirectorScript = preload("res://scripts/lockdown_director.gd")
const DefenseLoadoutScript = preload("res://scripts/defense_loadout.gd")
const EngineerToolkitScript = preload("res://scripts/engineer_toolkit.gd")
const EnemyBehaviorScript = preload("res://scripts/enemy_behavior.gd")
const CampaignProgressionScript = preload("res://scripts/campaign_progression.gd")

const GRID_SIZE := Vector2i(30, 22)
const TILE_W := 64.0
const TILE_H := 32.0
const PLAYER_SPEED := 3.4
const MAX_WAVES := 4
const BUILD_PAD_COUNT := 8
const RANDOM_BLOCKER_COUNT := 46 # Retained for the legacy generator helper.

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
var tap_route: Array = []
var camera_pos := player_pos
var map_seed := 0
var map_rng := RandomNumberGenerator.new()
var abilities = EngineerAbilitiesScript.new()
var exploration = ExplorationSystemScript.new(GRID_SIZE, 5)
var room_generator = RoomMapGeneratorScript.new()
var power_network = PowerNetworkScript.new()
var lockdown_director = LockdownDirectorScript.new()
var defense_loadout = DefenseLoadoutScript.new()
var engineer_toolkit = EngineerToolkitScript.new()
var campaign = CampaignProgressionScript.new()
var map_data: Dictionary = {}

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
var current_composition: Array = []
var current_incursion_final := false
var current_difficulty := 1.0

var paths: Array = []
var path_cells := {}
var walkable_cells := {}
var pads: Array = []
var enemies: Array = []
var tracers: Array = []
var particles: Array = []
var shock_waves: Array = []
var blocked_cells := {}
var wall_cells := {}
var facility_ids_by_objective := ["grid_relay", "sensor_lock", "blast_lock"]

var title_label: Label
var resources_label: Label
var wave_label: Label
var objective_label: Label
var prompt_label: Label
var message_label: Label
var intel_label: Label
var top_bar: Panel
var wave_button: Button
var shock_button: Button
var repair_button: Button
var barricade_button: Button
var mobile_context_buttons: Array[Button] = []
var is_compact_layout := false
var mobile_interact_held := false
var overlay: ColorRect
var overlay_card: Panel
var overlay_title: Label
var overlay_body: Label
var overlay_button: Button
var directive_buttons: Array[Button] = []


func _ready() -> void:
	campaign.load_progress()
	_prepare_campaign_level()
	_build_hud()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()
	queue_redraw()


func _prepare_campaign_level() -> void:
	var level: Dictionary = campaign.get_current_level()
	credits = float(level.starting_credits)
	base_health = int(level.starting_integrity)
	total_kills = 0
	campaign.begin_run()
	_generate_map(int(level.map_seed))
	if title_label != null:
		_apply_responsive_layout()


func _generate_map(forced_seed: int = -1) -> void:
	paths.clear()
	path_cells.clear()
	walkable_cells.clear()
	pads.clear()
	blocked_cells.clear()
	wall_cells.clear()
	map_seed = forced_seed if forced_seed >= 0 else randi()
	map_rng.seed = map_seed
	map_data = room_generator.generate(map_seed)
	BASE_CELL = Vector2(map_data.vault_cell)
	paths = map_data.routes.duplicate(true)
	walkable_cells = map_data.walkable_cells.duplicate()
	blocked_cells = map_data.blocked_cells.duplicate()
	for cell in map_data.path_cells:
		path_cells[cell] = true
	for solid_cell in blocked_cells:
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if walkable_cells.has(solid_cell + direction):
				wall_cells[solid_cell] = true
				break

	var selected_pad_cells := _select_balanced_pad_cells(map_data.build_pad_cells, BUILD_PAD_COUNT)
	for index in range(selected_pad_cells.size()):
		pads.append({
			"pos": Vector2(selected_pad_cells[index]),
			"level": 0,
			"progress": 0.0,
			"cooldown": map_rng.randf_range(0.0, 0.5),
			"pulse": map_rng.randf_range(0.0, TAU),
			"tower_family": "ballistic",
			"specialization": ""
		})
		defense_loadout.initialize_pad(pads[pads.size() - 1], "ballistic")

	_configure_infrastructure()
	player_pos = BASE_CELL
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.UP]:
		var candidate: Vector2i = Vector2i(BASE_CELL) + direction
		if walkable_cells.has(candidate):
			player_pos = Vector2(candidate)
			break
	camera_pos = player_pos
	has_tap_target = false
	tap_route.clear()
	lockdown_director = LockdownDirectorScript.new(map_seed)
	engineer_toolkit.reset()
	exploration.reset(GRID_SIZE, int(campaign.get_current_level().vision_radius))
	exploration.update_from_grid_position(player_pos, true)


func _configure_infrastructure() -> void:
	var facility_cells: Array = map_data.facility_cells
	var definitions: Array = [{"id": "vault_generator", "type": "generator", "position": BASE_CELL, "capacity": 20.0}]
	var types := ["substation", "sensor", "armory", "blast_control"]
	var ids := ["grid_relay", "sensor_lock", "armory_lock", "blast_lock"]
	for index in range(types.size()):
		var position: Vector2 = Vector2(facility_cells[index])
		var hp := 100.0 if index == 2 else 0.0
		definitions.append({"id": ids[index], "type": types[index], "position": position, "hp": hp, "enabled": true})
	var links := [
		{"a": "vault_generator", "b": "grid_relay", "exposed": false},
		{"a": "grid_relay", "b": "sensor_lock"},
		{"a": "grid_relay", "b": "armory_lock"},
		{"a": "grid_relay", "b": "blast_lock"}
	]
	power_network.reset(definitions, links, 20.0)


func _select_balanced_pad_cells(candidates: Array, desired_count: int) -> Array:
	var selected: Array = []
	for route in paths:
		for fraction in [0.28, 0.58, 0.82]:
			var route_cell := Vector2(route[clampi(roundi((route.size() - 1) * fraction), 0, route.size() - 1)])
			var best_cell = null
			var best_distance := INF
			for candidate in candidates:
				if candidate in selected:
					continue
				var distance: float = Vector2(candidate).distance_to(route_cell)
				if distance < best_distance:
					best_distance = distance
					best_cell = candidate
			if best_cell != null:
				selected.append(best_cell)
			if selected.size() >= desired_count:
				return selected
	for candidate in candidates:
		if candidate not in selected:
			selected.append(candidate)
		if selected.size() >= desired_count:
			break
	return selected


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

	top_bar = Panel.new()
	top_bar.position = Vector2(20, 18)
	top_bar.size = Vector2(1240, 70)
	top_bar.add_theme_stylebox_override("panel", _panel_style(Color("#0d171dcc"), CYAN, 1))
	layer.add_child(top_bar)

	title_label = Label.new()
	title_label.text = "DEEPWATCH  //  L%d %s" % [campaign.current_level_index + 1, campaign.get_current_level().name]
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
	prompt_label.position = Vector2(390, 630)
	prompt_label.size = Vector2(350, 62)
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
	shock_button.position = Vector2(755, 642)
	shock_button.size = Vector2(145, 48)
	shock_button.add_theme_font_size_override("font_size", 14)
	shock_button.pressed.connect(_activate_shock_pulse)
	layer.add_child(shock_button)

	repair_button = Button.new()
	repair_button.position = Vector2(910, 642)
	repair_button.size = Vector2(170, 48)
	repair_button.add_theme_font_size_override("font_size", 14)
	repair_button.pressed.connect(_activate_emergency_repair)
	layer.add_child(repair_button)

	barricade_button = Button.new()
	barricade_button.position = Vector2(1090, 642)
	barricade_button.size = Vector2(165, 48)
	barricade_button.add_theme_font_size_override("font_size", 14)
	barricade_button.pressed.connect(_deploy_barricade)
	layer.add_child(barricade_button)

	for index in range(4):
		var context_button := Button.new()
		context_button.visible = false
		context_button.focus_mode = Control.FOCUS_NONE
		context_button.add_theme_font_size_override("font_size", 13)
		context_button.button_down.connect(_mobile_context_button_down.bind(index))
		context_button.button_up.connect(_mobile_context_button_up.bind(index))
		layer.add_child(context_button)
		mobile_context_buttons.append(context_button)

	overlay = ColorRect.new()
	overlay.color = Color("#071015e8")
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(overlay)

	var card := Panel.new()
	overlay_card = card
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
	var level: Dictionary = campaign.get_current_level()
	overlay.visible = true
	overlay_title.text = "LEVEL %d  //  %s" % [campaign.current_level_index + 1, level.name]
	overlay_body.text = "%s\n\nThe blacksite grid is offline. Explore connected rooms, restore three strategic facilities, and defend each system while it synchronizes.\n\nHigh score: %d" % [level.subtitle, campaign.get_high_score()]
	overlay_button.text = "ENTER THE BASE"


func _overlay_action() -> void:
	if game_state == "briefing":
		game_state = "playing"
		overlay.visible = false
		_flash_message("Sector link established")
	elif game_state == "victory":
		campaign.advance_level()
		_prepare_campaign_level()
		game_state = "playing"
		overlay.visible = false
		_flash_message("Entering level %d: %s" % [campaign.current_level_index + 1, campaign.get_current_level().name])
	elif game_state == "defeat":
		_reset_game()


func _show_directive_choices(choices: Array) -> void:
	overlay.visible = true
	overlay_title.text = "FIELD DIRECTIVE"
	overlay_body.text = "Choose one protocol for the remainder of this shift."
	overlay_button.visible = false
	for old_button in directive_buttons:
		old_button.queue_free()
	directive_buttons.clear()
	for index in range(mini(3, choices.size())):
		var choice: Dictionary = choices[index]
		var button := Button.new()
		button.position = Vector2(22 + index * 180, 282)
		button.size = Vector2(170, 88)
		button.text = "%s\n%s" % [choice.name, choice.description]
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 12)
		button.pressed.connect(_choose_directive.bind(str(choice.id)))
		overlay_card.add_child(button)
		directive_buttons.append(button)
	_layout_directive_buttons()


func _choose_directive(directive_id: String) -> void:
	var result: Dictionary = lockdown_director.choose_directive(directive_id)
	if not result.success:
		return
	for button in directive_buttons:
		button.queue_free()
	directive_buttons.clear()
	overlay_button.visible = true
	overlay.visible = false
	_flash_message("Directive active: %s" % result.directive.name)


func _reset_game() -> void:
	_prepare_campaign_level()
	game_state = "playing"
	overlay.visible = false
	_flash_message("Level restarted")


func _on_viewport_resized() -> void:
	_apply_responsive_layout()
	queue_redraw()


func _apply_responsive_layout(requested_size: Vector2 = Vector2.ZERO) -> void:
	var viewport_size := requested_size if requested_size != Vector2.ZERO else get_viewport_rect().size
	var was_compact := is_compact_layout
	is_compact_layout = OS.has_feature("mobile") or viewport_size.x < 900.0 or viewport_size.y > viewport_size.x
	if was_compact and not is_compact_layout and mobile_interact_held:
		Input.action_release("interact")
		mobile_interact_held = false
	var safe_rect := _get_safe_layout_rect(viewport_size)
	if is_compact_layout:
		_apply_compact_layout(safe_rect)
	else:
		_apply_desktop_layout(safe_rect)
	_layout_overlay(safe_rect)
	_layout_directive_buttons()


func _get_safe_layout_rect(viewport_size: Vector2) -> Rect2:
	var result := Rect2(Vector2.ZERO, viewport_size)
	if not OS.has_feature("mobile"):
		return result
	var safe_pixels := DisplayServer.get_display_safe_area()
	var window_pixels := Vector2(get_window().size)
	if safe_pixels.size.x <= 0 or safe_pixels.size.y <= 0 or window_pixels.x <= 0 or window_pixels.y <= 0:
		return result
	var scale := viewport_size / window_pixels
	return Rect2(Vector2(safe_pixels.position) * scale, Vector2(safe_pixels.size) * scale)


func _apply_desktop_layout(safe_rect: Rect2) -> void:
	var width := safe_rect.size.x
	var bottom := safe_rect.end.y
	top_bar.position = safe_rect.position + Vector2(20, 18)
	top_bar.size = Vector2(maxf(720.0, width - 40.0), 70)
	title_label.text = "DEEPWATCH  //  SECTOR K-12"
	title_label.position = Vector2(22, 12)
	title_label.size = Vector2(560, 26)
	title_label.add_theme_font_size_override("font_size", 20)
	resources_label.position = Vector2(22, 39)
	resources_label.size = Vector2(maxf(480.0, width - 560.0), 24)
	resources_label.add_theme_font_size_override("font_size", 14)
	wave_button.size = Vector2(225, 46)
	wave_button.position = Vector2(top_bar.size.x - 250, 12)
	wave_label.position = Vector2(maxf(430.0, top_bar.size.x - 585.0), 14)
	wave_label.size = Vector2(320, 42)
	wave_label.add_theme_font_size_override("font_size", 16)
	objective_label.visible = true
	objective_label.position = safe_rect.position + Vector2(22, 104)
	objective_label.size = Vector2(370, 116)
	message_label.position = Vector2(safe_rect.position.x + (width - 400.0) * 0.5, safe_rect.position.y + 104)
	message_label.size = Vector2(400, 40)
	intel_label.position = Vector2(safe_rect.position.x + 22, bottom - 90)
	intel_label.size = Vector2(360, 62)
	prompt_label.position = Vector2(safe_rect.position.x + (width - 350.0) * 0.5, bottom - 90)
	prompt_label.size = Vector2(350, 62)
	barricade_button.position = Vector2(safe_rect.end.x - 190, bottom - 78)
	barricade_button.size = Vector2(165, 48)
	repair_button.position = barricade_button.position - Vector2(180, 0)
	repair_button.size = Vector2(170, 48)
	shock_button.position = repair_button.position - Vector2(155, 0)
	shock_button.size = Vector2(145, 48)
	shock_button.visible = true
	repair_button.visible = true
	barricade_button.visible = true
	for button in mobile_context_buttons:
		button.visible = false


func _apply_compact_layout(safe_rect: Rect2) -> void:
	var margin := 8.0
	var width := safe_rect.size.x
	var bottom := safe_rect.end.y
	var portrait := safe_rect.size.y > width
	var header_height := 104.0 if portrait else 78.0
	top_bar.position = safe_rect.position + Vector2(margin, margin)
	top_bar.size = Vector2(width - margin * 2.0, header_height)
	title_label.text = "DEEPWATCH  L%d" % (campaign.current_level_index + 1)
	title_label.position = Vector2(12, 7)
	title_label.size = Vector2(top_bar.size.x * 0.43, 24)
	title_label.add_theme_font_size_override("font_size", 16)
	resources_label.position = Vector2(12, 31)
	resources_label.size = Vector2(top_bar.size.x * (0.58 if portrait else 0.48), header_height - 34)
	resources_label.add_theme_font_size_override("font_size", 12)
	wave_button.size = Vector2(minf(180.0, top_bar.size.x * 0.42), 42)
	wave_button.position = Vector2(top_bar.size.x - wave_button.size.x - 10, header_height - 49)
	wave_button.add_theme_font_size_override("font_size", 12)
	wave_label.position = Vector2(top_bar.size.x * 0.48, 7)
	wave_label.size = Vector2(top_bar.size.x * 0.49 - 10, 30)
	wave_label.add_theme_font_size_override("font_size", 12)
	objective_label.visible = false
	message_label.position = Vector2(safe_rect.position.x + 12, top_bar.position.y + header_height + 5)
	message_label.size = Vector2(width - 24, 34)
	message_label.add_theme_font_size_override("font_size", 15)
	var action_height := 54.0
	var action_y := bottom - action_height - margin
	var gap := 6.0
	var button_width := (width - margin * 2.0 - gap * 3.0) / 4.0
	for index in range(mobile_context_buttons.size()):
		var button := mobile_context_buttons[index]
		button.position = Vector2(safe_rect.position.x + margin + index * (button_width + gap), action_y)
		button.size = Vector2(button_width, action_height)
		button.visible = true
	shock_button.visible = false
	repair_button.visible = false
	barricade_button.visible = false
	intel_label.position = Vector2(safe_rect.position.x + margin, action_y - 48)
	intel_label.size = Vector2(width - margin * 2.0, 42)
	intel_label.add_theme_font_size_override("font_size", 11)
	prompt_label.position = Vector2(safe_rect.position.x + margin, action_y - 100)
	prompt_label.size = Vector2(width - margin * 2.0, 46)
	prompt_label.add_theme_font_size_override("font_size", 13)


func _layout_overlay(safe_rect: Rect2) -> void:
	if overlay_card == null:
		return
	var card_width := minf(580.0, safe_rect.size.x - 32.0)
	var card_height := minf(500.0 if is_compact_layout else 400.0, safe_rect.size.y - 32.0)
	overlay_card.size = Vector2(card_width, card_height)
	overlay_card.position = safe_rect.position + (safe_rect.size - overlay_card.size) * 0.5
	overlay_title.position = Vector2(24, 24)
	overlay_title.size = Vector2(card_width - 48, 58)
	overlay_title.add_theme_font_size_override("font_size", 26 if is_compact_layout else 32)
	overlay_body.position = Vector2(36, 88)
	overlay_body.size = Vector2(card_width - 72, card_height - 190)
	overlay_body.add_theme_font_size_override("font_size", 15 if is_compact_layout else 17)
	overlay_button.size = Vector2(minf(250.0, card_width - 48.0), 54)
	overlay_button.position = Vector2((card_width - overlay_button.size.x) * 0.5, card_height - 78)


func _layout_directive_buttons() -> void:
	if overlay_card == null or directive_buttons.is_empty():
		return
	var card_width := overlay_card.size.x
	if card_width >= 540.0:
		var gap := 10.0
		var button_width := (card_width - 44.0 - gap * 2.0) / 3.0
		for index in range(directive_buttons.size()):
			directive_buttons[index].position = Vector2(22 + index * (button_width + gap), overlay_card.size.y - 118)
			directive_buttons[index].size = Vector2(button_width, 88)
	else:
		var button_height := 68.0
		var start_y := maxf(172.0, overlay_card.size.y - 30.0 - directive_buttons.size() * (button_height + 6.0))
		for index in range(directive_buttons.size()):
			directive_buttons[index].position = Vector2(20, start_y + index * (button_height + 6.0))
			directive_buttons[index].size = Vector2(card_width - 40, button_height)


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
	if event.is_action_pressed("deploy_barricade"):
		_deploy_barricade()
	for option_index in range(4):
		if event.is_action_pressed("tower_%d" % (option_index + 1)):
			_select_tower_option(option_index)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if event.position.y > 100.0 and event.position.y < get_viewport_rect().size.y - 70.0:
			_set_tap_destination(screen_to_grid(event.position))
	if event is InputEventScreenTouch and event.pressed:
		_set_tap_destination(screen_to_grid(event.position))


func _set_tap_destination(destination: Vector2) -> void:
	var destination_cell := Vector2i(roundi(destination.x), roundi(destination.y))
	destination_cell.x = clampi(destination_cell.x, 0, GRID_SIZE.x - 1)
	destination_cell.y = clampi(destination_cell.y, 0, GRID_SIZE.y - 1)
	if not walkable_cells.has(destination_cell):
		_flash_message("Destination is behind a sealed wall")
		return
	tap_route = _find_walkable_route(Vector2i(roundi(player_pos.x), roundi(player_pos.y)), destination_cell)
	if tap_route.size() <= 1:
		has_tap_target = false
		tap_route.clear()
		return
	tap_route.remove_at(0)
	tap_target = Vector2(tap_route[0])
	has_tap_target = true


func _physics_process(delta: float) -> void:
	if game_state != "playing":
		queue_redraw()
		return

	campaign.update(delta)
	_update_player(delta)
	var camera_weight := 1.0 - exp(-5.5 * delta)
	camera_pos = camera_pos.lerp(player_pos, camera_weight)
	exploration.update_from_grid_position(player_pos)
	abilities.update_cooldowns(delta)
	var toolkit_events: Array[Dictionary] = engineer_toolkit.update(delta)
	for toolkit_event in toolkit_events:
		if toolkit_event.type == "engineer_recovered":
			player_pos = BASE_CELL
			camera_pos = player_pos
			_flash_message("Engineer recovered at the command vault")
	_update_lockdown(delta)
	power_network.update(delta)
	_update_power_capacity()
	_update_sensor_range()
	_update_construction(delta)
	_update_wave(delta)
	_update_enemies(delta)
	_update_turrets(delta)
	_update_effects(delta)
	_update_hud()
	queue_redraw()


func _update_lockdown(delta: float) -> void:
	var director_event: Dictionary = lockdown_director.update(delta)
	if director_event.event == "incursion_started":
		_start_directed_incursion(false)
	elif director_event.event == "final_breach_started":
		_start_directed_incursion(true)

	_repair_nearby_facility(delta)
	if lockdown_director.state != lockdown_director.STATE_RECON or lockdown_director.can_trigger_final_breach():
		return
	var objective_index: int = lockdown_director.incursions_completed
	if objective_index < 0 or objective_index >= facility_ids_by_objective.size():
		return
	var facility_id: String = facility_ids_by_objective[objective_index]
	var facility: Dictionary = power_network.get_facility(facility_id)
	if facility.is_empty() or player_pos.distance_to(Vector2(facility.position)) > 0.7:
		return
	if not Input.is_action_pressed("interact"):
		return
	if lockdown_director.active_objective_index < 0:
		lockdown_director.activate_next_objective()
	var objective_rate := 34.0 * float(campaign.get_current_level().repair_multiplier) * delta
	var repair_result: Dictionary = lockdown_director.add_objective_repair(objective_rate)
	if repair_result.get("completed", false):
		campaign.award_objective()
		power_network.repair_facility(facility_id, 1000.0)
		lockdown_director.begin_incursion()
		_spawn_burst(Vector2(facility.position), CYAN, 18)
		_flash_message("%s restored  •  breach inbound" % facility_id.replace("_", " ").capitalize())


func _repair_nearby_facility(delta: float) -> void:
	if not Input.is_action_pressed("interact"):
		return
	for facility_id in power_network.facilities:
		var facility: Dictionary = power_network.facilities[facility_id]
		if player_pos.distance_to(Vector2(facility.position)) > 0.72:
			continue
		if facility.hp < facility.max_hp:
			var repair_rate := 34.0 * float(campaign.get_current_level().repair_multiplier) * delta
			var hp_before := float(facility.hp)
			power_network.repair_facility(facility_id, repair_rate)
			if hp_before + repair_rate >= float(facility.max_hp):
				_flash_message("%s restored to service" % str(facility.type).replace("_", " ").capitalize())
		return


func _update_power_capacity() -> void:
	# Restoring the grid relay connects the generator's reserve bus. Losing the
	# relay drops capacity again, but the engineer can now repair it in combat.
	power_network.capacity = float(campaign.get_current_level().reserve_capacity) if power_network.is_online("grid_relay") else 20.0


func _update_sensor_range() -> void:
	var desired_radius := int(campaign.get_current_level().vision_radius)
	var coverage: Array[Dictionary] = power_network.get_sensor_coverage()
	if not coverage.is_empty():
		desired_radius = roundi(float(campaign.get_current_level().sensor_radius) * lockdown_director.get_modifier("sensor_range"))
	if exploration.vision_radius != desired_radius:
		exploration.set_vision_radius(desired_radius)
		exploration.update_from_grid_position(player_pos, true)


func _update_player(delta: float) -> void:
	if engineer_toolkit.downed:
		return
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var move := Vector2.ZERO
	if input.length() > 0.05:
		# Screen-aligned controls converted into grid axes for an isometric floor.
		move = Vector2(input.x + input.y, input.y - input.x).normalized()
		has_tap_target = false
		tap_route.clear()
	elif has_tap_target:
		var offset := tap_target - player_pos
		if offset.length() < 0.08:
			player_pos = tap_target
			if not tap_route.is_empty():
				tap_route.remove_at(0)
			if tap_route.is_empty():
				has_tap_target = false
			else:
				tap_target = Vector2(tap_route[0])
		else:
			move = offset.normalized()

	if move != Vector2.ZERO:
		player_facing = move
		var speed_multiplier := lockdown_director.get_modifier("dark_engineer_speed") if power_network.get_sensor_coverage().is_empty() else 1.0
		var step := move * PLAYER_SPEED * speed_multiplier * delta
		var next := player_pos + step
		if walkable_cells.has(Vector2i(roundi(next.x), roundi(next.y))):
			player_pos = next
		else:
			# Screen-aligned isometric input is diagonal in grid space. Sliding
			# along either valid axis keeps one-tile maintenance corridors usable.
			var slide_x := player_pos + Vector2(step.x, 0.0)
			var slide_y := player_pos + Vector2(0.0, step.y)
			if absf(step.x) >= absf(step.y) and walkable_cells.has(Vector2i(roundi(slide_x.x), roundi(slide_x.y))):
				player_pos = slide_x
			elif walkable_cells.has(Vector2i(roundi(slide_y.x), roundi(slide_y.y))):
				player_pos = slide_y
			elif walkable_cells.has(Vector2i(roundi(slide_x.x), roundi(slide_x.y))):
				player_pos = slide_x


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
			_award_enemy_defeat(defeated_enemy)
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


func _deploy_barricade() -> void:
	if game_state != "playing":
		return
	var facing := Vector2i.ZERO
	if absf(player_facing.x) > absf(player_facing.y):
		facing.x = signi(roundi(player_facing.x))
	else:
		facing.y = signi(roundi(player_facing.y))
	if facing == Vector2i.ZERO:
		facing = Vector2i.DOWN
	var target_cell := Vector2i(roundi(player_pos.x), roundi(player_pos.y)) + facing
	var reserved := {Vector2i(BASE_CELL): true}
	for pad in pads:
		reserved[Vector2i(pad.pos)] = true
	for facility_id in power_network.facilities:
		reserved[Vector2i(power_network.facilities[facility_id].position)] = true
	var result: Dictionary = engineer_toolkit.deploy_barricade(target_cell, walkable_cells, reserved)
	if result.success:
		_spawn_burst(Vector2(target_cell), ORANGE, 10)
		_flash_message("Barricade deployed")
	else:
		_flash_message("Cannot deploy: %s" % str(result.reason).replace("_", " "))


func _select_tower_option(option_index: int) -> void:
	var nearby_pad = null
	for pad in pads:
		if player_pos.distance_to(pad.pos) < 0.65:
			nearby_pad = pad
			break
	if nearby_pad == null:
		return
	if nearby_pad.level == 0:
		var family: String = defense_loadout.FAMILIES[option_index]
		defense_loadout.assign_family(nearby_pad, family)
		_flash_message("Blueprint selected: %s" % defense_loadout.get_family_display_data(family).display_name)
	elif nearby_pad.level >= 2 and str(nearby_pad.specialization).is_empty() and option_index < 2:
		var branches: Array = defense_loadout.get_specialization_ids(nearby_pad.tower_family)
		var result: Dictionary = defense_loadout.specialize(nearby_pad, branches[option_index], credits)
		if result.ok:
			credits = result.credits_remaining
			_flash_message("Specialization installed: %s" % defense_loadout.get_pad_display_data(nearby_pad).specialization_name)
		else:
			_flash_message(result.reason)


func _mobile_context_button_down(index: int) -> void:
	if index < 0 or index >= mobile_context_buttons.size():
		return
	var action := str(mobile_context_buttons[index].get_meta("action", ""))
	match action:
		"work":
			mobile_interact_held = true
			Input.action_press("interact")
		"shock":
			_activate_shock_pulse()
		"repair":
			_activate_emergency_repair()
		"barrier":
			_deploy_barricade()
		_:
			if action.begins_with("tower_"):
				_select_tower_option(int(action.trim_prefix("tower_")))
			elif action.begins_with("specialize_"):
				_select_tower_option(int(action.trim_prefix("specialize_")))


func _mobile_context_button_up(_index: int) -> void:
	if mobile_interact_held:
		Input.action_release("interact")
		mobile_interact_held = false


func _set_mobile_button(index: int, text: String, action: String, disabled: bool = false) -> void:
	var button := mobile_context_buttons[index]
	button.text = text
	button.set_meta("action", action)
	button.disabled = disabled


func _update_mobile_context(nearby_pad, can_work: bool, ability_state: Dictionary) -> void:
	if not is_compact_layout:
		return
	if mobile_interact_held and not can_work:
		Input.action_release("interact")
		mobile_interact_held = false
	if nearby_pad != null and int(nearby_pad.level) == 0:
		for index in range(4):
			var family: String = defense_loadout.FAMILIES[index]
			var family_data: Dictionary = defense_loadout.get_family_display_data(family)
			_set_mobile_button(index, str(family_data.short_name), "tower_%d" % index)
		return
	if nearby_pad != null and int(nearby_pad.level) >= 2 and str(nearby_pad.specialization).is_empty():
		var branches: Array = defense_loadout.get_specialization_ids(nearby_pad.tower_family)
		for index in range(2):
			var branch: Dictionary = defense_loadout.FAMILY_DATA[nearby_pad.tower_family].specializations[branches[index]]
			_set_mobile_button(index, str(branch.display_name), "specialize_%d" % index)
		_set_mobile_button(2, "SHOCK", "shock", not bool(ability_state.shock_pulse.ready))
		_set_mobile_button(3, "BARRIER", "barrier", engineer_toolkit.barricade_charges <= 0 or engineer_toolkit.downed)
		return
	_set_mobile_button(0, "HOLD\nWORK" if can_work else "WORK", "work", not can_work)
	_set_mobile_button(1, "SHOCK", "shock", not bool(ability_state.shock_pulse.ready))
	_set_mobile_button(2, "VAULT\nREPAIR", "repair", not bool(ability_state.emergency_repair.cooldown_ready))
	_set_mobile_button(3, "BARRIER", "barrier", engineer_toolkit.barricade_charges <= 0 or engineer_toolkit.downed)


func _update_construction(delta: float) -> void:
	var active_pad = null
	for pad in pads:
		if player_pos.distance_to(pad.pos) < 0.48 and pad.level < 3:
			active_pad = pad
			break

	if active_pad == null:
		return

	var level: int = active_pad.level
	if level >= 2 and str(active_pad.specialization).is_empty():
		return
	var required := _upgrade_cost(level, active_pad)
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


func _upgrade_cost(current_level: int, pad: Dictionary = {}) -> float:
	var family := str(pad.get("tower_family", "ballistic"))
	var base_cost: float = defense_loadout.get_upgrade_cost(family, current_level + 1)
	return base_cost * lockdown_director.get_modifier("construction_cost")


func _request_wave() -> void:
	if game_state != "playing" or wave_active:
		return
	if lockdown_director.can_trigger_final_breach():
		lockdown_director.trigger_final_breach()
		_flash_message("Final breach signature detected")
	else:
		_flash_message("Restore the highlighted lockdown facility")


func _start_directed_incursion(is_final: bool) -> void:
	var plan: Dictionary = lockdown_director.get_final_breach_plan() if is_final else lockdown_director.get_current_incursion_plan()
	var level: Dictionary = campaign.get_current_level()
	wave = int(plan.sector)
	current_composition = campaign.scale_composition(plan.composition)
	current_difficulty = float(plan.difficulty_multiplier) * float(level.enemy_health)
	current_incursion_final = is_final
	wave_active = true
	spawned_this_wave = 0
	enemies_to_spawn = current_composition.size()
	spawn_timer = 0.25
	wave_button.disabled = true
	_flash_message("%s detected" % ("Final breach" if is_final else "Sector %d incursion" % wave))


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
		credits += (35.0 + wave * 8.0) * float(campaign.get_current_level().reward_multiplier)
		if current_incursion_final:
			campaign.award_incursion(true)
			lockdown_director.complete_final_breach()
			_end_game(true)
		else:
			campaign.award_incursion(false)
			var completion: Dictionary = lockdown_director.complete_incursion()
			if lockdown_director.state == lockdown_director.STATE_DIRECTIVE:
				_show_directive_choices(completion.directive_choices)
			elif lockdown_director.can_trigger_final_breach():
				wave_button.disabled = false
				_flash_message("Lockdown grid restored  •  authorize final breach")
			else:
				_flash_message("Sector secured  •  locate the next facility")


func _spawn_enemy(path_index: int) -> void:
	var base_enemy_type := str(current_composition[spawned_this_wave]) if spawned_this_wave < current_composition.size() else "drone"
	var enemy_type := EnemyBehaviorScript.choose_archetype(base_enemy_type, wave, spawned_this_wave)
	var stat_type := "runner" if enemy_type == "sapper" else "drone" if enemy_type == "stalker" else base_enemy_type
	var enemy: Dictionary = CombatCatalogScript.make_enemy_state(stat_type, wave, path_index)
	enemy.type = enemy_type
	enemy.display_name = "Grid Sapper" if enemy_type == "sapper" else "Signal Stalker" if enemy_type == "stalker" else enemy.display_name
	enemy.hp *= current_difficulty
	enemy.max_hp = enemy.hp
	enemy.speed *= float(campaign.get_current_level().enemy_speed)
	enemy.pos = Vector2(paths[path_index][0])
	enemy.shield_regen_remaining = 0.0
	enemy.slow_remaining = 0.0
	enemy.slow_strength = 0.0
	enemy.armor_break_remaining = 0.0
	enemy.armor_break_amount = 0.0
	enemy.route = paths[path_index].duplicate()
	enemy.barricade_attack_remaining = 0.0
	EnemyBehaviorScript.initialize_enemy(enemy, enemy_type)
	var target: Dictionary = EnemyBehaviorScript.assign_target(enemy, {"id": "vault", "position": BASE_CELL}, power_network.facilities)
	if target.kind == "facility":
		enemy.route = _find_walkable_route(Vector2i(enemy.pos), Vector2i(target.position))
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
		if enemy.pos.distance_to(player_pos) < 0.48 and not engineer_toolkit.downed:
			var player_hit: Dictionary = engineer_toolkit.take_damage(8.0, enemy.type)
			if player_hit.success:
				_spawn_burst(player_pos, RED, 5)
				if engineer_toolkit.downed:
					_flash_message("Engineer down  •  emergency recovery in 6s")
		var path: Array = enemy.route
		if path.is_empty():
			path = paths[enemy.path]
			enemy.route = path
		if enemy.segment >= path.size() - 1:
			if enemy.target_kind == "facility" and power_network.facilities.has(enemy.target_id):
				var attack: Dictionary = EnemyBehaviorScript.update_attack(enemy, delta, true)
				if attack.get("attack_ready", false):
					var damage_amount: float = attack.damage * lockdown_director.get_modifier("infrastructure_damage_taken")
					power_network.damage_facility(enemy.target_id, damage_amount)
					_spawn_burst(enemy.pos, RED, 6)
					if power_network.facilities[enemy.target_id].hp <= 0.0:
						enemy.target_kind = "vault"
						enemy.target_id = "vault"
						enemy.segment = 0
						enemy.route = _find_walkable_route(Vector2i(enemy.pos), Vector2i(BASE_CELL))
				continue
			base_health -= enemy.damage
			_spawn_burst(BASE_CELL, RED, 14)
			enemies.remove_at(i)
			_flash_message("Vault perimeter hit  -%d" % enemy.damage)
			if base_health <= 0:
				_end_game(false)
			return
		var target := Vector2(path[enemy.segment + 1])
		var target_cell := Vector2i(target)
		if engineer_toolkit.is_cell_blocked(target_cell):
			enemy.barricade_attack_remaining -= delta
			if enemy.barricade_attack_remaining <= 0.0:
				var contact: Dictionary = engineer_toolkit.handle_enemy_contact(target_cell, enemy, current_difficulty)
				enemy.barricade_attack_remaining = 0.7
				if contact.destroyed:
					_spawn_burst(Vector2(target_cell), ORANGE, 9)
			continue
		var distance: float = enemy.pos.distance_to(target)
		var slow_multiplier: float = 1.0 - enemy.slow_strength if enemy.slow_remaining > 0.0 else 1.0
		var travel: float = enemy.speed * slow_multiplier * delta
		if travel >= distance:
			enemy.pos = Vector2(target)
			enemy.segment += 1
		else:
			enemy.pos += enemy.pos.direction_to(target) * travel


func _find_walkable_route(start: Vector2i, finish: Vector2i) -> Array:
	var frontier: Array = [start]
	var came_from := {start: start}
	var cursor := 0
	while cursor < frontier.size():
		var current: Vector2i = frontier[cursor]
		cursor += 1
		if current == finish:
			break
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = current + direction
			if walkable_cells.has(next) and not came_from.has(next):
				came_from[next] = current
				frontier.append(next)
	if not came_from.has(finish):
		return []
	var route: Array = [finish]
	var step := finish
	while step != start:
		step = came_from[step]
		route.append(step)
	route.reverse()
	return route


func _update_turrets(delta: float) -> void:
	for pad in pads:
		if pad.level <= 0 or not _is_pad_powered(pad):
			continue
		pad.cooldown -= delta
		if pad.cooldown > 0.0:
			continue
		var armory_bonuses: Dictionary = power_network.get_armory_bonuses()
		var damage_modifier: float = armory_bonuses.damage_multiplier * lockdown_director.get_modifier("turret_damage")
		var stats: Dictionary = defense_loadout.get_effective_stats(pad, damage_modifier, armory_bonuses.armor_pierce_bonus)
		if pad.tower_family == "support":
			for facility_id in power_network.facilities:
				var facility: Dictionary = power_network.facilities[facility_id]
				if facility.hp < facility.max_hp and pad.pos.distance_to(Vector2(facility.position)) <= stats.range:
					power_network.repair_facility(facility_id, stats.repair_per_second)
					tracers.append({"from": pad.pos, "to": facility.position, "life": 0.18, "max_life": 0.18})
					break
			pad.cooldown = 1.0
			continue
		var target = _find_target(pad.pos, stats.range)
		if target == null:
			continue
		_apply_turret_hit(target, stats)
		if pad.tower_family == "arc":
			var jumps := maxi(0, int(stats.get("chain_targets", 1.0)) - 1)
			for secondary in enemies:
				if jumps <= 0:
					break
				if secondary != target and secondary.pos.distance_to(target.pos) <= 1.7:
					var chain_stats := stats.duplicate()
					chain_stats.damage *= 0.62
					_apply_turret_hit(secondary, chain_stats)
					tracers.append({"from": target.pos, "to": secondary.pos, "life": 0.10, "max_life": 0.10})
					jumps -= 1
		pad.cooldown = 1.0 / maxf(0.05, stats.shots_per_second)
		tracers.append({"from": pad.pos, "to": target.pos, "life": 0.10, "max_life": 0.10})
		_resolve_enemy_deaths()


func _apply_turret_hit(target: Dictionary, stats: Dictionary) -> void:
	var raw_damage: float = stats.damage
	if target.shield > 0.0:
		raw_damage *= float(stats.get("shield_damage", 1.0))
		if target.shield > 0.0:
			var absorbed := minf(target.shield, raw_damage)
			target.shield -= absorbed
			raw_damage -= absorbed
	var armor_break: float = target.armor_break_amount if target.armor_break_remaining > 0.0 else 0.0
	var effective_armor: float = maxf(0.0, target.armor - armor_break)
	target.hp -= CombatCatalogScript.calculate_hit(raw_damage, effective_armor, stats.pierce)
	target.shield_regen_remaining = target.shield_regen_delay
	if stats.get("slow_fraction", 0.0) > 0.0:
		target.slow_strength = maxf(target.slow_strength, stats.slow_fraction)
		target.slow_remaining = maxf(target.slow_remaining, stats.slow_seconds)
	target.hit = 0.12


func _resolve_enemy_deaths() -> void:
	for index in range(enemies.size() - 1, -1, -1):
		var enemy: Dictionary = enemies[index]
		if enemy.hp > 0.0:
			continue
		_award_enemy_defeat(enemy)
		_spawn_burst(enemy.pos, ORANGE, 7)
		enemies.remove_at(index)


func _award_enemy_defeat(enemy: Dictionary) -> void:
	credits += float(enemy.reward) * lockdown_director.get_modifier("enemy_reward") * float(campaign.get_current_level().reward_multiplier)
	total_kills += 1
	campaign.award_kill(str(enemy.type), wave)


func _is_pad_powered(target_pad: Dictionary) -> bool:
	if not power_network.is_online("vault_generator") or not power_network.is_online("grid_relay"):
		return false
	var remaining: float = power_network.capacity - power_network.power_used
	for pad in pads:
		if pad.level <= 0:
			continue
		var stats: Dictionary = defense_loadout.get_effective_stats(pad)
		remaining -= stats.power_cost
		if pad == target_pad:
			return remaining >= -0.001
	return false


func _get_tower_power_used() -> float:
	var used := 0.0
	for pad in pads:
		if pad.level > 0:
			used += defense_loadout.get_effective_stats(pad).power_cost
	return used


func _find_target(from: Vector2, range_tiles: float):
	var best = null
	var best_progress := -1.0
	for enemy in enemies:
		if from.distance_to(enemy.pos) <= range_tiles:
			var route: Array = enemy.get("route", paths[enemy.path])
			var progress: float = enemy.segment + (enemy.pos - Vector2(route[enemy.segment])).length()
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
	var run_result: Dictionary = campaign.finish_run(won, base_health, engineer_toolkit.health)
	var record_line := "NEW HIGH SCORE" if run_result.new_record else "HIGH SCORE  %d" % run_result.high_score
	if won:
		overlay_title.text = "%s SECURED" % str(run_result.level.name)
		overlay_body.text = "SCORE  %d  //  %s\n\nHostiles neutralized: %d\nVault integrity: %d / 20\nCompletion time: %.1fs" % [run_result.score, record_line, total_kills, base_health, run_result.elapsed_time]
		overlay_button.text = "NEXT LEVEL" if campaign.has_next_level() else "REPLAY CAMPAIGN"
	else:
		lockdown_director.report_defeat("vault_destroyed")
		overlay_title.text = "VAULT BREACHED"
		overlay_body.text = "SCORE  %d  //  %s\n\nHostiles neutralized: %d\nSectors secured: %d / 3\nRepair the grid and adapt the tower mix." % [run_result.score, record_line, total_kills, lockdown_director.incursions_completed]
		overlay_button.text = "RETRY LEVEL"


func _update_hud() -> void:
	var visible_contacts := 0
	for enemy in enemies:
		if exploration.is_visible(Vector2i(roundi(enemy.pos.x), roundi(enemy.pos.y))):
			visible_contacts += 1
	var campaign_hud: Dictionary = campaign.get_hud_state()
	if is_compact_layout:
		resources_label.text = "CR %03d  VAULT %02d/20\nSCORE %06d  ENG %03d" % [floori(credits), base_health, campaign_hud.score, floori(engineer_toolkit.health)]
	else:
		resources_label.text = "CREDITS %03d    VAULT %02d/20    ENGINEER %03d/100    SCORE %06d" % [floori(credits), base_health, floori(engineer_toolkit.health), campaign_hud.score]
	var director_hud: Dictionary = lockdown_director.get_hud_state()
	wave_label.text = "%d/3  •  %s" % [director_hud.secured_sectors, director_hud.state_label] if is_compact_layout else "LOCKDOWN  %d / 3   •   %s" % [director_hud.secured_sectors, director_hud.state_label]
	if director_hud.telegraph_active:
		wave_label.text += "  %.1fs" % director_hud.telegraph_remaining
	wave_button.text = "AUTHORIZE FINAL BREACH"
	wave_button.visible = director_hud.final_available and not wave_active
	wave_button.disabled = game_state != "playing"
	message_label.text = status_message if status_timer > 0.0 else ""
	var explored_percent := floori(100.0 * exploration.get_explored_count() / float(GRID_SIZE.x * GRID_SIZE.y))
	var power_hud: Dictionary = power_network.get_hud_state()
	var total_power_demand: float = power_hud.power_used + _get_tower_power_used()
	var power_status := "GRID OFFLINE" if not power_network.is_online("grid_relay") else "OVERLOAD" if total_power_demand > power_hud.capacity else "STABLE"
	intel_label.text = "PWR %.0f/%.0f %s  •  MAP %d%%  •  SENSOR %d" % [total_power_demand, power_hud.capacity, power_status, explored_percent, power_hud.sensor_count] if is_compact_layout else "POWER  %.0f / %.0f  %s\nMAPPED %d%%  •  CONTACTS %d  •  SENSORS %d" % [total_power_demand, power_hud.capacity, power_status, explored_percent, visible_contacts, power_hud.sensor_count]
	var objective_lines: Array[String] = []
	for objective in director_hud.objectives:
		var marker := "[X]" if objective.status == "secured" else "[>]" if objective.status in ["repairing", "online"] else "[ ]"
		objective_lines.append("%s %s" % [marker, objective.name])
	objective_label.text = "BLACKSITE LOCKDOWN\n" + "\n".join(objective_lines)
	var ability_state: Dictionary = abilities.get_hud_state()
	var shock_state: Dictionary = ability_state.shock_pulse
	var repair_state: Dictionary = ability_state.emergency_repair
	shock_button.text = "Q  SHOCK  %s" % ("READY" if shock_state.ready else "%.1fs" % shock_state.cooldown_remaining)
	repair_button.text = "F  VAULT REPAIR  %s" % ("READY" if repair_state.cooldown_ready else "%.1fs" % repair_state.cooldown_remaining)
	shock_button.disabled = not shock_state.ready
	repair_button.disabled = not repair_state.cooldown_ready
	barricade_button.text = "B  BARRIER  %d/%d" % [engineer_toolkit.barricade_charges, engineer_toolkit.config.max_barricade_charges]
	barricade_button.disabled = engineer_toolkit.barricade_charges <= 0 or engineer_toolkit.downed

	var maintenance_facility = null
	for facility_id in power_network.facilities:
		var nearby_facility: Dictionary = power_network.facilities[facility_id]
		if nearby_facility.hp < nearby_facility.max_hp and player_pos.distance_to(Vector2(nearby_facility.position)) < 0.8:
			maintenance_facility = nearby_facility
			break
	var objective_facility = null
	if lockdown_director.state == lockdown_director.STATE_RECON and not lockdown_director.can_trigger_final_breach():
		var objective_index: int = lockdown_director.incursions_completed
		if objective_index < facility_ids_by_objective.size():
			var target_facility: Dictionary = power_network.get_facility(facility_ids_by_objective[objective_index])
			if not target_facility.is_empty() and player_pos.distance_to(Vector2(target_facility.position)) < 0.8:
				objective_facility = target_facility
	var nearby = null
	for pad in pads:
		if player_pos.distance_to(pad.pos) < 0.55:
			nearby = pad
			break
	if objective_facility != null:
		var active_progress := 0.0
		if lockdown_director.active_objective_index >= 0:
			active_progress = lockdown_director.objectives[lockdown_director.active_objective_index].repair_progress
		prompt_label.text = "%s  •  RESTORE %s  %.0f%%" % ["HOLD WORK" if is_compact_layout else "HOLD E", str(objective_facility.type).replace("_", " ").to_upper(), active_progress]
		prompt_label.visible = true
	elif maintenance_facility != null:
		prompt_label.text = "%s  •  REPAIR %s  %.0f%%" % ["HOLD WORK" if is_compact_layout else "HOLD E", str(maintenance_facility.type).replace("_", " ").to_upper(), 100.0 * maintenance_facility.hp / maintenance_facility.max_hp]
		prompt_label.visible = true
	elif nearby != null and nearby.level >= 2 and str(nearby.specialization).is_empty():
		var branch_ids: Array = defense_loadout.get_specialization_ids(nearby.tower_family)
		var first_branch: Dictionary = defense_loadout.FAMILY_DATA[nearby.tower_family].specializations[branch_ids[0]]
		var second_branch: Dictionary = defense_loadout.FAMILY_DATA[nearby.tower_family].specializations[branch_ids[1]]
		prompt_label.text = "CHOOSE SPECIALIZATION BELOW" if is_compact_layout else "SPECIALIZE  1 %s  •  2 %s" % [first_branch.display_name, second_branch.display_name]
		prompt_label.visible = true
	elif nearby != null and nearby.level < 3:
		var cost := _upgrade_cost(nearby.level, nearby)
		var display: Dictionary = defense_loadout.get_pad_display_data(nearby)
		var target_name := ("CHOOSE TOWER BLUEPRINT BELOW" if is_compact_layout else "1 GUN  2 ARC  3 CRYO  4 SUPPORT") if nearby.level == 0 else "UPGRADE %s TO MK-%d" % [display.short_name, nearby.level + 1]
		prompt_label.text = "%s\n%d / %d CREDITS" % [target_name, floori(nearby.progress), floori(cost)]
		prompt_label.visible = true
	elif nearby != null:
		prompt_label.text = "SENTRY AT MAXIMUM OUTPUT"
		prompt_label.visible = true
	else:
		prompt_label.visible = false
	_update_mobile_context(nearby, objective_facility != null or maintenance_facility != null, ability_state)


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
	_draw_power_links()
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
			if not walkable_cells.has(cell):
				continue
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
	for cell in wall_cells:
		if exploration.is_explored(cell):
			drawables.append({"depth": cell.x + cell.y, "kind": "block", "data": cell})
	for facility_id in power_network.facilities:
		var facility: Dictionary = power_network.facilities[facility_id]
		if exploration.is_explored(Vector2i(facility.position)):
			drawables.append({"depth": facility.position.x + facility.position.y + 0.12, "kind": "facility", "data": facility})
	for pad in pads:
		if exploration.is_explored(Vector2i(pad.pos)):
			drawables.append({"depth": pad.pos.x + pad.pos.y + 0.05, "kind": "pad", "data": pad})
	for enemy in enemies:
		if exploration.is_visible(Vector2i(roundi(enemy.pos.x), roundi(enemy.pos.y))):
			drawables.append({"depth": enemy.pos.x + enemy.pos.y + 0.18, "kind": "enemy", "data": enemy})
	for barricade in engineer_toolkit.get_barricades():
		if exploration.is_explored(barricade.cell):
			drawables.append({"depth": barricade.cell.x + barricade.cell.y + 0.1, "kind": "barricade", "data": barricade})
	if exploration.is_explored(Vector2i(BASE_CELL)):
		drawables.append({"depth": BASE_CELL.x + BASE_CELL.y + 0.2, "kind": "base", "data": null})
	drawables.append({"depth": player_pos.x + player_pos.y + 0.3, "kind": "player", "data": null})
	drawables.sort_custom(func(a, b): return a.depth < b.depth)
	for item in drawables:
		match item.kind:
			"block": _draw_block(Vector2(item.data))
			"facility": _draw_facility(item.data)
			"pad": _draw_pad(item.data)
			"enemy": _draw_enemy(item.data)
			"barricade": _draw_barricade(item.data)
			"base": _draw_base()
			"player": _draw_player()


func _draw_power_links() -> void:
	for link_id in power_network.links:
		var link: Dictionary = power_network.links[link_id]
		var first: Dictionary = power_network.facilities[link.a]
		var second: Dictionary = power_network.facilities[link.b]
		if not exploration.is_explored(Vector2i(first.position)) or not exploration.is_explored(Vector2i(second.position)):
			continue
		var color := CYAN.darkened(0.35) if link.hp > 0.0 else RED.darkened(0.35)
		draw_dashed_line(grid_to_screen(Vector2(first.position)), grid_to_screen(Vector2(second.position)), color, 2.0, 8.0)


func _draw_facility(facility: Dictionary) -> void:
	var p := grid_to_screen(Vector2(facility.position))
	var online_color := CYAN if facility.online else RED if facility.hp <= 0.0 else ORANGE
	draw_set_transform(p, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 23.0, Color("#0c181e"))
	draw_arc(Vector2.ZERO, 23.0, 0, TAU, 28, online_color, 3.0)
	draw_set_transform(Vector2.ZERO)
	draw_rect(Rect2(p + Vector2(-14, -34), Vector2(28, 26)), Color("#263941"))
	match facility.type:
		"generator":
			draw_circle(p + Vector2(0, -23), 8.0, online_color)
		"substation":
			draw_line(p + Vector2(-8, -14), p + Vector2(0, -34), online_color, 4.0)
			draw_line(p + Vector2(0, -34), p + Vector2(8, -14), online_color, 4.0)
		"sensor":
			draw_arc(p + Vector2(0, -22), 10.0, PI, TAU, 18, online_color, 3.0)
			draw_circle(p + Vector2(0, -22), 3.0, online_color)
		"armory":
			draw_line(p + Vector2(-8, -29), p + Vector2(8, -16), online_color, 4.0)
			draw_line(p + Vector2(8, -29), p + Vector2(-8, -16), online_color, 4.0)
		"blast_control":
			draw_rect(Rect2(p + Vector2(-8, -29), Vector2(16, 14)), online_color)
	var hp_ratio: float = facility.hp / facility.max_hp
	draw_rect(Rect2(p + Vector2(-18, -42), Vector2(36, 4)), Color("#10171a"))
	draw_rect(Rect2(p + Vector2(-18, -42), Vector2(36 * hp_ratio, 4)), online_color)


func _draw_barricade(barricade: Dictionary) -> void:
	var p := grid_to_screen(Vector2(barricade.cell))
	var ratio: float = barricade.hp / barricade.max_hp
	draw_colored_polygon(PackedVector2Array([p + Vector2(-24, -3), p + Vector2(0, 9), p + Vector2(24, -3), p + Vector2(0, -15)]), Color("#795734"))
	draw_line(p + Vector2(-20, -7), p + Vector2(20, -7), ORANGE.darkened(0.2), 6.0)
	draw_rect(Rect2(p + Vector2(-18, -24), Vector2(36, 4)), Color("#12191b"))
	draw_rect(Rect2(p + Vector2(-18, -24), Vector2(36 * ratio, 4)), ORANGE)


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
		var cost := _upgrade_cost(0, pad)
		if pad.progress > 0:
			_draw_progress_arc(p, pad.progress / cost)
		return
	_draw_turret(p, pad)
	if pad.level < 3 and pad.progress > 0:
		_draw_progress_arc(p, pad.progress / _upgrade_cost(pad.level, pad))


func _draw_progress_arc(p: Vector2, ratio: float) -> void:
	draw_set_transform(p, 0.0, Vector2(1.0, 0.48))
	draw_arc(Vector2.ZERO, 25, -PI * 0.5, -PI * 0.5 + TAU * ratio, 32, CREAM, 4.0)
	draw_set_transform(Vector2.ZERO)


func _draw_turret(p: Vector2, pad: Dictionary) -> void:
	var level: int = pad.level
	var family_data: Dictionary = defense_loadout.get_family_display_data(pad.tower_family)
	var family_color: Color = family_data.color if _is_pad_powered(pad) else Color("#5c6668")
	draw_colored_polygon(PackedVector2Array([p + Vector2(-15, -2), p + Vector2(0, 7), p + Vector2(15, -2), p + Vector2(0, -10)]), Color("#52646c"))
	draw_rect(Rect2(p + Vector2(-9, -24), Vector2(18, 18)), Color("#24343c"))
	draw_rect(Rect2(p + Vector2(-5, -28), Vector2(10, 12)), family_color.darkened(0.25))
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
	elif enemy.type == "sapper":
		body_color = Color("#d9d052")
		scale_factor = 0.92
	elif enemy.type == "stalker":
		body_color = Color("#62528f")
		scale_factor = 0.84
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
	if engineer_toolkit.downed:
		draw_circle(p + Vector2(0, -8), 20.0, Color("#f25b5b55"))
		draw_line(p + Vector2(-13, -8), p + Vector2(13, -8), RED, 6.0)
		return
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
