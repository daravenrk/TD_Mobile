extends SceneTree

const Director = preload("res://scripts/lockdown_director.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_full_victory_run()
	_test_determinism_and_defeat()
	if failures.is_empty():
		print("LOCKDOWN DIRECTOR TEST PASSED: objectives, telegraphs, directives, final breach, victory, and defeat")
		quit(0)
	else:
		for failure in failures:
			push_error("LOCKDOWN DIRECTOR TEST FAILED: " + failure)
		quit(1)


func _test_full_victory_run() -> void:
	var director = Director.new(42, 100.0, 2.0, 3.0)
	_check(director.state == Director.STATE_RECON, "A run should begin in recon")
	_check(not director.begin_incursion().success, "Incursion began without a restored objective")

	for sector_index in range(3):
		var activation: Dictionary = director.activate_next_objective()
		_check(activation.success, "Sector %d objective did not activate" % (sector_index + 1))
		_check(not director.add_objective_repair(60.0).completed, "Partial repair completed an objective")
		var repaired: Dictionary = director.add_objective_repair(60.0)
		_check(repaired.completed, "Repair did not cap and complete the objective")
		_check(is_equal_approx(float(repaired.progress), 100.0), "Repair exceeded its target")

		var prep: Dictionary = director.begin_incursion()
		_check(prep.success and director.state == Director.STATE_PREP, "Objective did not enter prep")
		var plan: Dictionary = prep.plan
		_check(int(plan.sector) == sector_index + 1, "Incursion used the wrong sector plan")
		_check(not plan.composition.is_empty(), "Incursion composition was empty")
		_check(float(plan.difficulty_multiplier) > 0.0, "Incursion has no difficulty multiplier")
		director.update(1.0)
		_check(director.state == Director.STATE_PREP, "Telegraph ended too early")
		var transition: Dictionary = director.update(100.0)
		_check(transition.event == "incursion_started", "Telegraph did not emit incursion start")
		_check(director.state == Director.STATE_INCURSION, "Prep did not become incursion")

		var completion: Dictionary = director.complete_incursion()
		_check(completion.success, "Incursion could not be completed")
		if sector_index < 2:
			_check(director.state == Director.STATE_DIRECTIVE, "Mid-run incursion did not offer a directive")
			var choices := director.get_directive_choices()
			_check(choices.size() == 3, "Director did not offer exactly three directives")
			var chosen: Dictionary = choices[0]
			var modifier_key: String = chosen.modifiers.keys()[0]
			var expected_modifier := float(chosen.modifiers[modifier_key])
			_check(director.choose_directive(chosen.id).success, "Offered directive could not be selected")
			_check(director.has_directive(chosen.id), "Selected directive was not recorded")
			_check(is_equal_approx(director.get_modifier(modifier_key), expected_modifier), "Directive modifier was not applied")
			_check(director.state == Director.STATE_RECON, "Directive choice did not return to recon")

	_check(director.can_trigger_final_breach(), "Three secured objectives did not unlock the final breach")
	var final_start: Dictionary = director.trigger_final_breach()
	_check(final_start.success and director.state == Director.STATE_FINAL, "Final breach did not enter final state")
	_check(final_start.plan.final, "Final plan was not marked final")
	_check(not director.complete_final_breach().success, "Final breach completed during its warning")
	var final_transition: Dictionary = director.update(100.0)
	_check(final_transition.event == "final_breach_started", "Final breach telegraph did not complete")
	_check(director.final_breach_active, "Final breach was not marked active")
	_check(director.complete_final_breach().success, "Active final breach could not complete")
	_check(director.state == Director.STATE_VICTORY, "Final breach did not produce victory")
	var summary := director.get_run_summary()
	_check(summary.secured_sectors == 3, "Victory summary has the wrong secured sector count")
	_check(summary.outcome == Director.STATE_VICTORY, "Victory summary has the wrong outcome")
	_check(director.get_hud_state().lockdown_progress == 1.0, "HUD lockdown progress is not complete")


func _test_determinism_and_defeat() -> void:
	var first = Director.new(777, 1.0, 0.0, 0.0)
	var second = Director.new(777, 1.0, 0.0, 0.0)
	for director in [first, second]:
		director.activate_next_objective()
		director.add_objective_repair(1.0)
		director.begin_incursion()
		director.update(0.0)
		director.complete_incursion()
	_check(first.get_directive_choices() == second.get_directive_choices(), "Same seed produced different directive choices")
	_check(first.get_sector_plan(2) == second.get_sector_plan(2), "Sector plans are not deterministic")
	_check(first.report_defeat("power_core_lost").success, "Active run could not report defeat")
	_check(first.state == Director.STATE_DEFEAT, "Defeat did not enter defeat state")
	_check(first.get_run_summary().defeat_reason == "power_core_lost", "Defeat reason was not summarized")
	_check(not first.report_defeat().success, "Finished run accepted a second defeat")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
