class_name LockdownDirector
extends RefCounted

## Data-only run state machine for the Blacksite Protocol lockdown campaign.
##
## Scene code remains responsible for spawning enemies, presenting directive
## cards, and applying damage. This module owns progression and exposes small
## command/query APIs so it can initially sit beside the existing wave loop.

const STATE_RECON := "recon"
const STATE_PREP := "prep"
const STATE_INCURSION := "incursion"
const STATE_DIRECTIVE := "directive"
const STATE_FINAL := "final"
const STATE_VICTORY := "victory"
const STATE_DEFEAT := "defeat"

const OBJECTIVE_DEFINITIONS := [
	{"id": "outer_grid", "name": "Restore Outer Power Grid"},
	{"id": "sensor_lock", "name": "Recalibrate Sensor Lock"},
	{"id": "vault_seal", "name": "Engage Vault Seal"}
]

const SECTOR_COMPOSITIONS := [
	["drone", "drone", "runner", "drone", "drone", "runner", "drone", "brute"],
	["runner", "drone", "shielded", "drone", "runner", "brute", "drone", "armored", "runner", "drone", "shielded"],
	["shielded", "runner", "armored", "drone", "brute", "runner", "shielded", "armored", "drone", "brute", "runner", "armored", "shielded", "drone"]
]

const FINAL_COMPOSITION := [
	"shielded", "runner", "armored", "brute", "drone", "shielded",
	"armored", "runner", "brute", "shielded", "armored", "drone",
	"runner", "brute", "armored", "shielded", "brute", "armored"
]

const DIRECTIVE_CATALOG := [
	{
		"id": "overclock_protocol",
		"name": "Overclock Protocol",
		"description": "+18% turret damage, +15% turret power draw.",
		"modifiers": {"turret_damage": 1.18, "turret_power_draw": 1.15}
	},
	{
		"id": "salvage_rights",
		"name": "Salvage Rights",
		"description": "+22% credits from defeated hostiles.",
		"modifiers": {"enemy_reward": 1.22}
	},
	{
		"id": "hardened_relays",
		"name": "Hardened Relays",
		"description": "Infrastructure takes 25% less damage.",
		"modifiers": {"infrastructure_damage_taken": 0.75}
	},
	{
		"id": "sensor_mesh",
		"name": "Distributed Sensor Mesh",
		"description": "+30% sensor range and longer threat warning.",
		"modifiers": {"sensor_range": 1.30, "telegraph_duration": 1.20}
	},
	{
		"id": "rapid_fabrication",
		"name": "Rapid Fabrication",
		"description": "Construction and upgrades cost 15% fewer credits.",
		"modifiers": {"construction_cost": 0.85}
	},
	{
		"id": "darkrunner_rig",
		"name": "Darkrunner Rig",
		"description": "+20% engineer speed in unpowered sectors.",
		"modifiers": {"dark_engineer_speed": 1.20}
	}
]

var state := STATE_RECON
var run_seed: int
var objective_repair_target: float
var incursion_telegraph_duration: float
var final_telegraph_duration: float

var objectives: Array[Dictionary] = []
var active_objective_index := -1
var incursions_completed := 0
var elapsed_run_time := 0.0
var telegraph_remaining := 0.0
var final_breach_active := false
var defeat_reason := ""

var _directive_round := 0
var _directive_choices: Array[Dictionary] = []
var _selected_directives: Array[String] = []
var _modifiers: Dictionary = {}


func _init(
	configured_seed: int = 1,
	configured_repair_target: float = 100.0,
	configured_incursion_telegraph: float = 6.0,
	configured_final_telegraph: float = 10.0
) -> void:
	run_seed = configured_seed
	objective_repair_target = maxf(1.0, configured_repair_target)
	incursion_telegraph_duration = maxf(0.0, configured_incursion_telegraph)
	final_telegraph_duration = maxf(0.0, configured_final_telegraph)
	reset()


func reset() -> void:
	state = STATE_RECON
	active_objective_index = -1
	incursions_completed = 0
	elapsed_run_time = 0.0
	telegraph_remaining = 0.0
	final_breach_active = false
	defeat_reason = ""
	_directive_round = 0
	_directive_choices.clear()
	_selected_directives.clear()
	_modifiers.clear()
	objectives.clear()
	for definition_variant in OBJECTIVE_DEFINITIONS:
		var definition: Dictionary = definition_variant
		objectives.append({
			"id": definition.id,
			"name": definition.name,
			"status": "offline",
			"repair_progress": 0.0,
			"repair_target": objective_repair_target
		})


func update(delta: float) -> Dictionary:
	var elapsed := maxf(0.0, delta)
	elapsed_run_time += elapsed
	var event := "none"
	if state == STATE_PREP or (state == STATE_FINAL and not final_breach_active):
		telegraph_remaining = maxf(0.0, telegraph_remaining - elapsed)
		if is_zero_approx(telegraph_remaining):
			if state == STATE_PREP:
				state = STATE_INCURSION
				event = "incursion_started"
			else:
				final_breach_active = true
				event = "final_breach_started"
	return {"event": event, "state": state, "telegraph_remaining": telegraph_remaining}


func activate_next_objective() -> Dictionary:
	if state != STATE_RECON or active_objective_index >= 0:
		return _failure("objective_unavailable")
	for index in range(objectives.size()):
		if objectives[index].status == "offline":
			active_objective_index = index
			objectives[index].status = "repairing"
			return {"success": true, "objective": objectives[index].duplicate(true)}
	return _failure("all_objectives_secured")


func add_objective_repair(amount: float) -> Dictionary:
	if state != STATE_RECON or active_objective_index < 0:
		return _failure("no_active_objective")
	var objective := objectives[active_objective_index]
	if objective.status != "repairing":
		return _failure("objective_not_repairing")
	objective.repair_progress = minf(
		objective_repair_target,
		float(objective.repair_progress) + maxf(0.0, amount)
	)
	if is_equal_approx(float(objective.repair_progress), objective_repair_target):
		objective.status = "online"
	return {
		"success": true,
		"completed": objective.status == "online",
		"progress": objective.repair_progress,
		"target": objective_repair_target,
		"objective": objective.duplicate(true)
	}


func begin_incursion() -> Dictionary:
	if state != STATE_RECON or active_objective_index < 0:
		return _failure("incursion_unavailable")
	if objectives[active_objective_index].status != "online":
		return _failure("objective_requires_repair")
	state = STATE_PREP
	telegraph_remaining = incursion_telegraph_duration * get_modifier("telegraph_duration")
	return {
		"success": true,
		"state": state,
		"telegraph_remaining": telegraph_remaining,
		"plan": get_current_incursion_plan()
	}


func complete_incursion() -> Dictionary:
	if state != STATE_INCURSION or active_objective_index < 0:
		return _failure("no_active_incursion")
	objectives[active_objective_index].status = "secured"
	incursions_completed += 1
	active_objective_index = -1
	if incursions_completed < objectives.size():
		state = STATE_DIRECTIVE
		_directive_round += 1
		_directive_choices = _make_directive_choices(_directive_round)
	else:
		state = STATE_RECON
		_directive_choices.clear()
	return {
		"success": true,
		"state": state,
		"secured": incursions_completed,
		"directive_choices": get_directive_choices(),
		"final_available": can_trigger_final_breach()
	}


func get_directive_choices() -> Array[Dictionary]:
	return _directive_choices.duplicate(true)


func choose_directive(directive_id: String) -> Dictionary:
	if state != STATE_DIRECTIVE:
		return _failure("directive_unavailable")
	var selected: Dictionary = {}
	for choice in _directive_choices:
		if choice.id == directive_id:
			selected = choice
			break
	if selected.is_empty():
		return _failure("directive_not_offered")
	_selected_directives.append(directive_id)
	for modifier_key in selected.modifiers:
		_modifiers[modifier_key] = get_modifier(modifier_key) * float(selected.modifiers[modifier_key])
	_directive_choices.clear()
	state = STATE_RECON
	return {"success": true, "state": state, "directive": selected.duplicate(true)}


func get_modifier(modifier_id: String) -> float:
	return float(_modifiers.get(modifier_id, 1.0))


func has_directive(directive_id: String) -> bool:
	return directive_id in _selected_directives


func get_selected_directives() -> Array[String]:
	return _selected_directives.duplicate()


func can_trigger_final_breach() -> bool:
	return state == STATE_RECON and incursions_completed == objectives.size()


func trigger_final_breach() -> Dictionary:
	if not can_trigger_final_breach():
		return _failure("lockdown_incomplete")
	state = STATE_FINAL
	final_breach_active = false
	telegraph_remaining = final_telegraph_duration * get_modifier("telegraph_duration")
	return {
		"success": true,
		"state": state,
		"telegraph_remaining": telegraph_remaining,
		"plan": get_final_breach_plan()
	}


func complete_final_breach() -> Dictionary:
	if state != STATE_FINAL or not final_breach_active:
		return _failure("final_breach_not_active")
	state = STATE_VICTORY
	return {"success": true, "state": state, "summary": get_run_summary()}


func report_defeat(reason: String = "vault_destroyed") -> Dictionary:
	if state == STATE_VICTORY or state == STATE_DEFEAT:
		return _failure("run_already_finished")
	defeat_reason = reason
	telegraph_remaining = 0.0
	state = STATE_DEFEAT
	return {"success": true, "state": state, "reason": defeat_reason}


func get_current_incursion_plan() -> Dictionary:
	var sector_index := active_objective_index
	if sector_index < 0:
		sector_index = mini(incursions_completed, SECTOR_COMPOSITIONS.size() - 1)
	return get_sector_plan(sector_index)


func get_sector_plan(sector_index: int) -> Dictionary:
	var safe_index := clampi(sector_index, 0, SECTOR_COMPOSITIONS.size() - 1)
	return {
		"sector": safe_index + 1,
		"composition": SECTOR_COMPOSITIONS[safe_index].duplicate(),
		"difficulty_multiplier": snappedf(1.0 + safe_index * 0.28, 0.01),
		"spawn_interval_multiplier": snappedf(1.0 - safe_index * 0.10, 0.01)
	}


func get_final_breach_plan() -> Dictionary:
	return {
		"sector": 4,
		"composition": FINAL_COMPOSITION.duplicate(),
		"difficulty_multiplier": 1.95,
		"spawn_interval_multiplier": 0.68,
		"final": true
	}


func get_hud_state() -> Dictionary:
	var current_objective: Dictionary = {}
	if active_objective_index >= 0:
		current_objective = objectives[active_objective_index].duplicate(true)
	return {
		"state": state,
		"state_label": _get_state_label(),
		"objectives": objectives.duplicate(true),
		"current_objective": current_objective,
		"lockdown_progress": float(incursions_completed) / float(objectives.size()),
		"secured_sectors": incursions_completed,
		"total_sectors": objectives.size(),
		"telegraph_remaining": telegraph_remaining,
		"telegraph_active": telegraph_remaining > 0.0,
		"final_available": can_trigger_final_breach(),
		"final_breach_active": final_breach_active,
		"directive_choices": get_directive_choices(),
		"selected_directives": get_selected_directives()
	}


func get_run_summary() -> Dictionary:
	return {
		"outcome": state,
		"secured_sectors": incursions_completed,
		"total_sectors": objectives.size(),
		"directives": get_selected_directives(),
		"elapsed_time": elapsed_run_time,
		"defeat_reason": defeat_reason,
		"seed": run_seed
	}


func _make_directive_choices(round_number: int) -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	var start := posmod(run_seed * 7 + round_number * 3, DIRECTIVE_CATALOG.size())
	var stride := 1 + posmod(abs(run_seed) + round_number, 2)
	var cursor := start
	while choices.size() < 3:
		var candidate: Dictionary = DIRECTIVE_CATALOG[cursor]
		var duplicate := false
		for existing in choices:
			if existing.id == candidate.id:
				duplicate = true
				break
		if not duplicate and candidate.id not in _selected_directives:
			choices.append(candidate.duplicate(true))
		cursor = posmod(cursor + stride, DIRECTIVE_CATALOG.size())
		# If selected directives eventually exhaust the catalog, allow repeats as
		# a safe endless-mode fallback. The three-sector campaign never needs it.
		if cursor == start and choices.size() < 3:
			for fallback in DIRECTIVE_CATALOG:
				if choices.size() >= 3:
					break
				var already_offered := false
				for existing in choices:
					if existing.id == fallback.id:
						already_offered = true
				if not already_offered:
					choices.append(fallback.duplicate(true))
	return choices


func _get_state_label() -> String:
	match state:
		STATE_RECON:
			return "Survey and Restore"
		STATE_PREP:
			return "Breach Warning"
		STATE_INCURSION:
			return "Incursion in Progress"
		STATE_DIRECTIVE:
			return "Select Field Directive"
		STATE_FINAL:
			return "Final Breach"
		STATE_VICTORY:
			return "Blacksite Secured"
		STATE_DEFEAT:
			return "Lockdown Failed"
	return state.capitalize()


func _failure(reason: String) -> Dictionary:
	return {"success": false, "reason": reason, "state": state}
