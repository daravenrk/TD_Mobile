extends SceneTree

const DefenseLoadoutScript = preload("res://scripts/defense_loadout.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var loadout = DefenseLoadoutScript.new()
	_check(loadout.FAMILIES.size() == 4, "Expected four tower families")

	for family in loadout.FAMILIES:
		var display: Dictionary = loadout.get_family_display_data(family)
		_check(not display.is_empty(), "%s has no display data" % family)
		_check(display.specializations.size() == 2, "%s does not have two branches" % family)
		_check(loadout.get_build_cost(family) > 0, "%s has no build cost" % family)

		var pad := {"pos": Vector2(4, 5), "level": 0, "progress": 0.4, "cooldown": 0.2, "pulse": 1.0}
		var initialized: Dictionary = loadout.initialize_pad(pad, family)
		_check(initialized.ok and pad.tower_family == family, "%s pad initialization failed" % family)
		_check(pad.pulse == 1.0, "%s initialization discarded existing pad data" % family)

		var too_poor: Dictionary = loadout.upgrade(pad, 0.0)
		_check(not too_poor.ok and int(pad.level) == 0, "%s ignored insufficient credits" % family)
		var built: Dictionary = loadout.upgrade(pad, 1000.0)
		_check(built.ok and int(pad.level) == 1, "%s failed to build" % family)
		var level_two: Dictionary = loadout.upgrade(pad, 1000.0)
		_check(level_two.ok and int(pad.level) == 2, "%s failed its second upgrade" % family)

		var branch_ids: Array = loadout.get_specialization_ids(family)
		var specialized: Dictionary = loadout.specialize(pad, branch_ids[0], 1000.0)
		_check(specialized.ok and pad.specialization == branch_ids[0], "%s specialization failed" % family)
		_check(not loadout.specialize(pad, branch_ids[1], 1000.0).ok, "%s allowed two specializations" % family)

		var base_stats: Dictionary = loadout.get_effective_stats(pad)
		var modified_stats: Dictionary = loadout.get_effective_stats(pad, 1.5, 0.2)
		_check(modified_stats.damage == base_stats.damage * 1.5, "%s damage modifier was not applied" % family)
		_check(is_equal_approx(modified_stats.pierce, minf(base_stats.pierce + 0.2, 1.0)), "%s pierce modifier was not applied" % family)
		_check(base_stats.power_cost > 0.0, "%s consumes no power when built" % family)
		_check(str(base_stats.target_preference) != "", "%s has no target preference" % family)

		_check(loadout.upgrade(pad, 1000.0).ok and int(pad.level) == 3, "%s failed to reach MK-3" % family)
		_check(not loadout.upgrade(pad, 1000.0).ok, "%s upgraded beyond MK-3" % family)
		var hud: Dictionary = loadout.get_pad_display_data(pad)
		_check(hud.level_label == "MK-3" and hud.next_upgrade_cost == -1, "%s HUD state is incorrect" % family)

	var empty_pad := {"level": 0}
	_check(not loadout.assign_family(empty_pad, "invalid").ok, "Accepted an invalid family")
	_check(loadout.assign_family(empty_pad, "arc").ok, "Could not assign a valid family")
	_check(empty_pad.tower_family == "arc", "Family assignment did not mutate the pad")
	loadout.upgrade(empty_pad, 999.0)
	_check(not loadout.assign_family(empty_pad, "cryo").ok, "Changed the family of a built tower")
	_check(not loadout.specialize({"level": 1, "tower_family": "arc"}, "storm", 999.0).ok, "Specialized below MK-2")
	_check(loadout.validate_cost(10.0, 20.0).shortfall == 10.0, "Cost validation returned the wrong shortfall")

	if failures.is_empty():
		print("DEFENSE LOADOUT TEST PASSED: four families, upgrades, branches, modifiers, and HUD data")
		quit(0)
	else:
		for failure in failures:
			push_error("DEFENSE LOADOUT TEST FAILED: " + failure)
		quit(1)
