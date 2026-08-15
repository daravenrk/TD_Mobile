extends SceneTree

const RoomMapGeneratorScript = preload("res://scripts/room_map_generator.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _run() -> void:
	var signatures := {}
	for seed_value in range(50, 110):
		var generated: Dictionary = RoomMapGeneratorScript.new().generate(seed_value)
		_validate_map(generated, seed_value)
		var repeated: Dictionary = RoomMapGeneratorScript.new().generate(seed_value)
		_check(generated == repeated, "Seed %d was not deterministic" % seed_value)
		signatures[str(generated.floor_cells)] = true
	_check(signatures.size() > 45, "Sixty seeds produced too few distinct layouts")

	if failures.is_empty():
		print("ROOM MAP GENERATOR TEST PASSED: 60 deterministic, connected sectors")
		quit(0)
	else:
		for failure in failures:
			push_error("ROOM MAP GENERATOR TEST FAILED: " + failure)
		quit(1)


func _validate_map(map_data: Dictionary, seed_value: int) -> void:
	_check(map_data.grid_size == Vector2i(30, 22), "Seed %d has the wrong grid size" % seed_value)
	_check(map_data.rooms.size() >= 8 and map_data.rooms.size() <= 12, "Seed %d has an invalid room count" % seed_value)
	_check(map_data.vault_room.type == "command_vault", "Seed %d lacks a command vault" % seed_value)
	_check(map_data.vault_cell.x >= 22, "Seed %d command vault is not near the right edge" % seed_value)
	_check(map_data.breaches.size() == 3, "Seed %d lacks three breaches" % seed_value)
	_check(map_data.routes.size() == 3, "Seed %d lacks three routes" % seed_value)
	_check(map_data.facility_cells.size() >= 7, "Seed %d lacks facility candidates" % seed_value)
	_check(map_data.build_pad_cells.size() >= 8, "Seed %d lacks build-pad candidates" % seed_value)
	_check(map_data.floor_cells.size() + map_data.solid_cells.size() == 30 * 22, "Seed %d does not partition the grid" % seed_value)

	var edges := {}
	for breach in map_data.breaches:
		edges[breach.edge] = true
		_check(map_data.walkable_cells.has(breach.cell), "Seed %d breach is not walkable" % seed_value)
	_check(edges.size() == 3, "Seed %d breaches do not use distinct edges" % seed_value)

	for route_index in range(map_data.routes.size()):
		var route: Array = map_data.routes[route_index]
		_check(not route.is_empty(), "Seed %d route %d is empty" % [seed_value, route_index])
		if route.is_empty():
			continue
		_check(route[0] == map_data.breaches[route_index].cell, "Seed %d route %d begins away from its breach" % [seed_value, route_index])
		_check(route[route.size() - 1] == map_data.vault_cell, "Seed %d route %d misses the vault" % [seed_value, route_index])
		for index in range(route.size()):
			_check(map_data.walkable_cells.has(route[index]), "Seed %d route %d leaves the floor" % [seed_value, route_index])
			if index > 0:
				_check(_manhattan(route[index - 1], route[index]) == 1, "Seed %d route %d is not cardinally contiguous" % [seed_value, route_index])

	for facility in map_data.facility_cells:
		_check(map_data.walkable_cells.has(facility), "Seed %d facility candidate is blocked" % seed_value)
	for pad in map_data.build_pad_cells:
		_check(map_data.walkable_cells.has(pad), "Seed %d build-pad candidate is blocked" % seed_value)
		_check(not map_data.path_cells.has(pad), "Seed %d build pad overlaps an enemy route" % seed_value)

	# Flood-fill from the vault proves every carved floor cell is part of the
	# navigable blacksite, including rooms not used by the shortest enemy paths.
	var reached := {map_data.vault_cell: true}
	var frontier: Array = [map_data.vault_cell]
	var cursor := 0
	while cursor < frontier.size():
		var current: Vector2i = frontier[cursor]
		cursor += 1
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = current + direction
			if map_data.walkable_cells.has(next) and not reached.has(next):
				reached[next] = true
				frontier.append(next)
	_check(reached.size() == map_data.walkable_cells.size(), "Seed %d has disconnected floor cells" % seed_value)


func _manhattan(first: Vector2i, second: Vector2i) -> int:
	return absi(first.x - second.x) + absi(first.y - second.y)
