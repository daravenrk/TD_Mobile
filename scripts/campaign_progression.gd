class_name CampaignProgression
extends RefCounted

signal score_changed(score: int, reason: String)

const LEVELS := [
	{
		"id": "outer_grid", "name": "OUTER GRID", "subtitle": "Restore the abandoned perimeter network.",
		"map_seed": 7319, "starting_credits": 210.0, "starting_integrity": 20,
		"reserve_capacity": 60.0, "vision_radius": 4, "sensor_radius": 7, "enemy_health": 1.0,
		"enemy_speed": 1.0, "spawn_multiplier": 1.0, "reward_multiplier": 1.0,
		"repair_multiplier": 1.0, "score_multiplier": 1.0
	},
	{
		"id": "echo_tunnels", "name": "ECHO TUNNELS", "subtitle": "Fast contacts are probing the maintenance arteries.",
		"map_seed": 19427, "starting_credits": 190.0, "starting_integrity": 18,
		"reserve_capacity": 60.0, "vision_radius": 4, "sensor_radius": 7, "enemy_health": 1.12,
		"enemy_speed": 1.08, "spawn_multiplier": 1.15, "reward_multiplier": 1.0,
		"repair_multiplier": 0.95, "score_multiplier": 1.2
	},
	{
		"id": "blackout_depths", "name": "BLACKOUT DEPTHS", "subtitle": "Limited sensors conceal heavier sabotage teams.",
		"map_seed": 42061, "starting_credits": 175.0, "starting_integrity": 18,
		"reserve_capacity": 58.0, "vision_radius": 3, "sensor_radius": 6, "enemy_health": 1.25,
		"enemy_speed": 1.12, "spawn_multiplier": 1.30, "reward_multiplier": 0.95,
		"repair_multiplier": 0.90, "score_multiplier": 1.45
	},
	{
		"id": "red_foundry", "name": "RED FOUNDRY", "subtitle": "Armored swarms force hard choices across the power grid.",
		"map_seed": 88703, "starting_credits": 160.0, "starting_integrity": 16,
		"reserve_capacity": 58.0, "vision_radius": 3, "sensor_radius": 6, "enemy_health": 1.42,
		"enemy_speed": 1.18, "spawn_multiplier": 1.45, "reward_multiplier": 0.90,
		"repair_multiplier": 0.85, "score_multiplier": 1.75
	},
	{
		"id": "last_vault", "name": "LAST VAULT", "subtitle": "The deepest breach leaves no reserve and no margin for error.",
		"map_seed": 135791, "starting_credits": 145.0, "starting_integrity": 15,
		"reserve_capacity": 56.0, "vision_radius": 3, "sensor_radius": 5, "enemy_health": 1.65,
		"enemy_speed": 1.25, "spawn_multiplier": 1.65, "reward_multiplier": 0.85,
		"repair_multiplier": 0.80, "score_multiplier": 2.20
	}
]

const ENEMY_POINTS := {
	"drone": 100, "runner": 125, "stalker": 160, "sapper": 180,
	"armored": 220, "shielded": 240, "brute": 300, "burrower": 260
}

var save_path := "user://deepwatch_scores.json"
var current_level_index := 0
var score := 0
var elapsed_time := 0.0
var run_active := false
var high_scores: Dictionary = {}
var completed_levels: Dictionary = {}


func _init(configured_save_path: String = "user://deepwatch_scores.json") -> void:
	save_path = configured_save_path


func get_level_count() -> int:
	return LEVELS.size()


func set_level(index: int) -> Dictionary:
	current_level_index = clampi(index, 0, LEVELS.size() - 1)
	return get_current_level()


func get_current_level() -> Dictionary:
	return LEVELS[current_level_index].duplicate(true)


func has_next_level() -> bool:
	return current_level_index + 1 < LEVELS.size()


func advance_level() -> Dictionary:
	if has_next_level():
		current_level_index += 1
	else:
		current_level_index = 0
	_save()
	return get_current_level()


func begin_run(level_index: int = -1) -> Dictionary:
	if level_index >= 0:
		set_level(level_index)
	score = 0
	elapsed_time = 0.0
	run_active = true
	return get_hud_state()


func update(delta: float) -> void:
	if run_active:
		elapsed_time += maxf(0.0, delta)


func award_kill(enemy_type: String, sector: int) -> int:
	var base_points := int(ENEMY_POINTS.get(enemy_type, 100)) + maxi(0, sector - 1) * 20
	return _award(base_points, "hostile neutralized")


func award_objective() -> int:
	return _award(700, "facility restored")


func award_incursion(final_breach: bool = false) -> int:
	return _award(1600 if final_breach else 450, "breach repelled")


func finish_run(victory: bool, vault_integrity: int, engineer_health: float) -> Dictionary:
	if run_active:
		if victory:
			_award(4000, "level secured")
			_award(maxi(0, vault_integrity) * 160, "vault integrity")
			_award(floori(maxf(0.0, engineer_health)) * 8, "engineer survival")
			_award(floori(maxf(0.0, 420.0 - elapsed_time) * 5.0), "response time")
		run_active = false
	var level: Dictionary = get_current_level()
	var level_id := str(level.id)
	var previous_best := int(high_scores.get(level_id, 0))
	var new_record := score > previous_best
	if new_record:
		high_scores[level_id] = score
	if victory:
		completed_levels[level_id] = true
	_save()
	return {
		"score": score,
		"high_score": int(high_scores.get(level_id, score)),
		"new_record": new_record,
		"victory": victory,
		"elapsed_time": elapsed_time,
		"level": level
	}


func scale_composition(composition: Array) -> Array:
	if composition.is_empty():
		return []
	var target_count := maxi(composition.size(), ceili(composition.size() * float(get_current_level().spawn_multiplier)))
	var result := composition.duplicate()
	var cursor := 0
	while result.size() < target_count:
		result.append(composition[cursor % composition.size()])
		cursor += 1
	return result


func get_high_score(level_id: String = "") -> int:
	var resolved_id := level_id if not level_id.is_empty() else str(get_current_level().id)
	return int(high_scores.get(resolved_id, 0))


func get_total_score() -> int:
	var result := 0
	for value in high_scores.values():
		result += int(value)
	return result


func get_hud_state() -> Dictionary:
	return {
		"level_number": current_level_index + 1,
		"level_count": LEVELS.size(),
		"level": get_current_level(),
		"score": score,
		"high_score": get_high_score(),
		"total_score": get_total_score(),
		"elapsed_time": elapsed_time
	}


func load_progress() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return get_hud_state()
	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return get_hud_state()
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		high_scores = parsed.get("high_scores", {}).duplicate(true)
		completed_levels = parsed.get("completed_levels", {}).duplicate(true)
		current_level_index = clampi(int(parsed.get("current_level_index", 0)), 0, LEVELS.size() - 1)
	return get_hud_state()


func _award(base_points: int, reason: String) -> int:
	if not run_active or base_points <= 0:
		return 0
	var awarded := maxi(1, roundi(base_points * float(get_current_level().score_multiplier)))
	score += awarded
	score_changed.emit(score, reason)
	return awarded


func _save() -> bool:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({
		"version": 1,
		"current_level_index": current_level_index,
		"high_scores": high_scores,
		"completed_levels": completed_levels
	}, "  "))
	return true
