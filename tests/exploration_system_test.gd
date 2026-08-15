extends SceneTree

const ExplorationSystemScript = preload("res://scripts/exploration_system.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var exploration = ExplorationSystemScript.new(Vector2i(30, 22), 2)
	_check(exploration.get_explored_count() == 0, "A new map should begin unexplored")
	_check(exploration.update_visibility(Vector2i(10, 10)), "The initial visibility update should run")
	_check(exploration.get_visible_count() == 13, "Radius two should reveal a 13-cell circular footprint")
	_check(exploration.get_explored_count() == 13, "Visible cells should become explored")
	_check(exploration.is_visible(Vector2i(10, 10)), "Observer cell should be visible")
	_check(exploration.get_cell_state(Vector2i(10, 10)) == exploration.VISIBLE, "Observer cell should report VISIBLE")
	_check(not exploration.update_visibility(Vector2i(10, 10)), "Remaining in one cell should skip recalculation")

	# Moving replaces local visibility while preserving memory of old terrain.
	exploration.update_visibility(Vector2i(15, 10))
	_check(not exploration.is_visible(Vector2i(10, 10)), "Old terrain should leave local visibility")
	_check(exploration.is_explored(Vector2i(10, 10)), "Old terrain should remain explored")
	_check(exploration.get_cell_state(Vector2i(10, 10)) == exploration.EXPLORED, "Old terrain should report EXPLORED")
	_check(exploration.get_explored_count() == 26, "Separated vision footprints should accumulate")

	# Threat helpers must not leak information about enemies in the fog.
	var threats: Array = [Vector2i(16, 10), Vector2i(29, 21), Vector2(15.0, 12.0)]
	_check(exploration.get_nearest_visible_threat(Vector2i(15, 10), threats) == Vector2i(16, 10), "Nearest visible threat was not selected")
	var threat_direction := exploration.get_visible_threat_direction(Vector2i(15, 10), threats)
	_check(threat_direction.is_equal_approx(Vector2.RIGHT), "Visible threat direction should point right")
	_check(exploration.get_visible_threat_direction(Vector2i(0, 0), [Vector2i(29, 21)]) == Vector2.ZERO, "Hidden threats should not produce a direction")

	var frontier := exploration.get_frontier_cells()
	_check(not frontier.is_empty(), "Explored territory should expose an exploration frontier")
	for frontier_cell in frontier:
		_check(exploration.is_in_bounds(frontier_cell), "Frontier contained an out-of-bounds cell")
		_check(not exploration.is_explored(frontier_cell), "Frontier contained an explored cell")

	# Edge clipping, floating-point positions, runtime radius changes, and reset.
	exploration.reset(Vector2i(30, 22), 2)
	exploration.update_from_grid_position(Vector2(0.2, 0.2))
	_check(exploration.get_visible_count() == 6, "Vision should clip cleanly at map corners")
	exploration.set_vision_radius(0)
	exploration.update_visibility(Vector2i(4, 4))
	_check(exploration.get_visible_count() == 1, "Radius zero should reveal only the observer cell")
	exploration.reset(Vector2i(8, 6), 3)
	_check(exploration.grid_size == Vector2i(8, 6), "Reset should adopt new map bounds")
	_check(exploration.get_visible_count() == 0 and exploration.get_explored_count() == 0, "Reset should clear all fog state")
	_check(not exploration.update_visibility(Vector2i(8, 6)), "Out-of-bounds observer updates should be rejected")

	if failures.is_empty():
		print("EXPLORATION TEST PASSED: visibility, memory, frontier, threats, bounds, and reset")
		quit(0)
	else:
		for failure in failures:
			push_error("EXPLORATION TEST FAILED: " + failure)
		quit(1)
