extends SceneTree

const CampaignScript = preload("res://scripts/campaign_progression.gd")

var failures: Array[String] = []
var save_path := "/tmp/deepwatch_campaign_progression_test_%d.json" % Time.get_ticks_usec()


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var campaign = CampaignScript.new(save_path)
	_check(campaign.get_level_count() == 5, "Campaign did not define five levels")
	var prior_health := 0.0
	var prior_spawns := 0.0
	var prior_score := 0.0
	for index in range(campaign.get_level_count()):
		var level: Dictionary = campaign.set_level(index)
		_check(not str(level.name).is_empty(), "Level %d has no name" % index)
		_check(float(level.enemy_health) >= prior_health, "Enemy health difficulty fell at level %d" % index)
		_check(float(level.spawn_multiplier) >= prior_spawns, "Spawn pressure fell at level %d" % index)
		_check(float(level.score_multiplier) >= prior_score, "Score multiplier fell at level %d" % index)
		prior_health = level.enemy_health
		prior_spawns = level.spawn_multiplier
		prior_score = level.score_multiplier

	campaign.begin_run(0)
	var kill_points := campaign.award_kill("drone", 1)
	var objective_points := campaign.award_objective()
	campaign.update(30.0)
	var result: Dictionary = campaign.finish_run(true, 18, 75.0)
	_check(kill_points == 100, "Base drone score was incorrect")
	_check(objective_points == 700, "Base objective score was incorrect")
	_check(result.score > kill_points + objective_points, "Victory bonuses were not applied")
	_check(result.new_record, "First completed run did not set a record")
	_check(campaign.get_high_score() == result.score, "High score did not match the completed run")

	var loaded = CampaignScript.new(save_path)
	loaded.load_progress()
	_check(loaded.get_high_score("outer_grid") == result.score, "Persisted high score did not reload")
	_check(loaded.completed_levels.get("outer_grid", false), "Completed level did not persist")
	loaded.begin_run(4)
	var hard_points := loaded.award_kill("drone", 1)
	_check(hard_points > kill_points, "Harder level did not award a larger score multiplier")
	var scaled: Array = loaded.scale_composition(["drone", "runner", "brute", "drone"])
	_check(scaled.size() == 7, "Final level did not increase enemy count deterministically")
	loaded.finish_run(false, 0, 0.0)

	if failures.is_empty():
		print("CAMPAIGN PROGRESSION TEST PASSED: levels, scaling, scoring, records, and persistence")
		quit(0)
	else:
		for failure in failures:
			push_error("CAMPAIGN PROGRESSION TEST FAILED: " + failure)
		quit(1)
