class_name RoomMapGenerator
extends RefCounted

## Deterministic room-and-corridor generator for a 30x22 Deepwatch sector.
##
## `generate(seed)` returns a data-only Dictionary. Cells use Vector2i keys and
## values, so the result can be consumed by a renderer, navigation layer, or the
## current dictionary-based prototype without creating any Nodes.

const GRID_SIZE := Vector2i(30, 22)
const MIN_ROOMS := 8
const MAX_ROOMS := 12
const CARDINAL_DIRECTIONS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]

var _rng := RandomNumberGenerator.new()
var _walkable := {}
var _corridor_cells := {}


func generate(seed_value: int) -> Dictionary:
	_rng.seed = seed_value
	_walkable.clear()
	_corridor_cells.clear()

	var rooms := _create_rooms()
	for room in rooms:
		_carve_room(room.rect)

	_connect_all_rooms(rooms)
	_add_loop_connections(rooms)

	var vault_room: Dictionary = rooms[0]
	var vault_cell: Vector2i = vault_room.center
	var breaches := _create_breaches(rooms)
	var routes: Array = []
	var enemy_path_lookup := {}
	for breach in breaches:
		var route := _find_path(breach.cell, vault_cell)
		routes.append(route)
		for cell in route:
			enemy_path_lookup[cell] = true

	var facility_cells := _select_facility_cells(rooms, vault_cell, breaches)
	var build_pad_cells := _select_build_pad_cells(enemy_path_lookup, facility_cells, vault_cell, breaches)
	var floor_cells: Array = _sorted_cells(_walkable.keys())
	var solid_cells: Array = []
	for y in range(GRID_SIZE.y):
		for x in range(GRID_SIZE.x):
			var cell := Vector2i(x, y)
			if not _walkable.has(cell):
				solid_cells.append(cell)

	return {
		"seed": seed_value,
		"grid_size": GRID_SIZE,
		"rooms": rooms,
		"vault_room": vault_room,
		"vault_cell": vault_cell,
		"breaches": breaches,
		"routes": routes,
		"floor_cells": floor_cells,
		"walkable_cells": _cells_to_lookup(floor_cells),
		"corridor_cells": _sorted_cells(_corridor_cells.keys()),
		"path_cells": _sorted_cells(enemy_path_lookup.keys()),
		"solid_cells": solid_cells,
		"blocked_cells": _cells_to_lookup(solid_cells),
		"facility_cells": facility_cells,
		"build_pad_cells": build_pad_cells
	}


func _create_rooms() -> Array:
	# Twelve non-overlapping placement bays make room count and bounds guaranteed,
	# while randomized offsets and dimensions prevent a rigid visual grid.
	var bays: Array = []
	var x_starts := [1, 8, 15, 22]
	var y_starts := [1, 8, 15]
	for row in range(3):
		for column in range(4):
			bays.append(Rect2i(x_starts[column], y_starts[row], 7, 6))

	# The middle-right bay is always the command vault and is kept first.
	var vault_bay_index := 7
	var selected_indices: Array = [vault_bay_index]
	var candidates: Array = []
	for index in range(bays.size()):
		if index != vault_bay_index:
			candidates.append(index)
	_shuffle(candidates)
	var target_count := _rng.randi_range(MIN_ROOMS, MAX_ROOMS)
	for index in candidates:
		if selected_indices.size() >= target_count:
			break
		selected_indices.append(index)

	var rooms: Array = []
	for room_index in range(selected_indices.size()):
		var bay: Rect2i = bays[selected_indices[room_index]]
		var width := _rng.randi_range(4, 6)
		var height := _rng.randi_range(3, 5)
		var offset_x := _rng.randi_range(0, bay.size.x - width)
		var offset_y := _rng.randi_range(0, bay.size.y - height)
		var rect := Rect2i(bay.position + Vector2i(offset_x, offset_y), Vector2i(width, height))
		var room_type := "command_vault" if room_index == 0 else "sector"
		rooms.append({
			"id": room_index,
			"type": room_type,
			"rect": rect,
			"center": rect.position + Vector2i(rect.size.x / 2, rect.size.y / 2)
		})
	return rooms


func _carve_room(rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			_walkable[Vector2i(x, y)] = true


func _connect_all_rooms(rooms: Array) -> void:
	# Prim-like nearest-room links give every room a connection without relying
	# on favorable random placement.
	var connected: Array = [0]
	var remaining: Array = []
	for index in range(1, rooms.size()):
		remaining.append(index)
	while not remaining.is_empty():
		var best_from := 0
		var best_to: int = remaining[0]
		var best_distance := 1000000
		for from_index in connected:
			for to_index in remaining:
				var from_cell: Vector2i = rooms[from_index].center
				var to_cell: Vector2i = rooms[to_index].center
				var distance := _manhattan(from_cell, to_cell)
				if distance < best_distance:
					best_distance = distance
					best_from = from_index
					best_to = to_index
		_carve_corridor(rooms[best_from].center, rooms[best_to].center)
		connected.append(best_to)
		remaining.erase(best_to)


func _add_loop_connections(rooms: Array) -> void:
	# Extra links create alternate routes through the blacksite. Duplicate or
	# crossing corridors are harmless and still preserve determinism.
	var loop_count := 2 if rooms.size() < 11 else 3
	for loop_index in range(loop_count):
		var first := _rng.randi_range(0, rooms.size() - 1)
		var second := _rng.randi_range(0, rooms.size() - 1)
		while second == first:
			second = _rng.randi_range(0, rooms.size() - 1)
		_carve_corridor(rooms[first].center, rooms[second].center)


func _carve_corridor(start: Vector2i, finish: Vector2i) -> void:
	var current := start
	var horizontal_first := _rng.randf() < 0.5
	_carve_corridor_cell(current)
	if horizontal_first:
		while current.x != finish.x:
			current.x += signi(finish.x - current.x)
			_carve_corridor_cell(current)
		while current.y != finish.y:
			current.y += signi(finish.y - current.y)
			_carve_corridor_cell(current)
	else:
		while current.y != finish.y:
			current.y += signi(finish.y - current.y)
			_carve_corridor_cell(current)
		while current.x != finish.x:
			current.x += signi(finish.x - current.x)
			_carve_corridor_cell(current)


func _carve_corridor_cell(cell: Vector2i) -> void:
	if _in_bounds(cell):
		_walkable[cell] = true
		_corridor_cells[cell] = true


func _create_breaches(rooms: Array) -> Array:
	var breach_specs := [
		{"edge": "left", "cell": Vector2i(0, _rng.randi_range(2, GRID_SIZE.y - 3))},
		{"edge": "top", "cell": Vector2i(_rng.randi_range(2, GRID_SIZE.x - 7), 0)},
		{"edge": "bottom", "cell": Vector2i(_rng.randi_range(2, GRID_SIZE.x - 7), GRID_SIZE.y - 1)}
	]
	var breaches: Array = []
	for spec in breach_specs:
		var entry: Vector2i = spec.cell
		var nearest_center: Vector2i = rooms[0].center
		var nearest_distance := 1000000
		for room in rooms:
			var distance := _manhattan(entry, room.center)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_center = room.center
		_carve_corridor(entry, nearest_center)
		breaches.append({"edge": spec.edge, "cell": entry})
	return breaches


func _find_path(start: Vector2i, finish: Vector2i) -> Array:
	var frontier: Array = [start]
	var cursor := 0
	var came_from := {start: start}
	while cursor < frontier.size():
		var current: Vector2i = frontier[cursor]
		cursor += 1
		if current == finish:
			break
		for direction in CARDINAL_DIRECTIONS:
			var next: Vector2i = current + direction
			if _walkable.has(next) and not came_from.has(next):
				came_from[next] = current
				frontier.append(next)

	if not came_from.has(finish):
		return []
	var reversed_path: Array = [finish]
	var step := finish
	while step != start:
		step = came_from[step]
		reversed_path.append(step)
	reversed_path.reverse()
	return reversed_path


func _select_facility_cells(rooms: Array, vault_cell: Vector2i, breaches: Array) -> Array:
	var facilities: Array = []
	var reserved := {vault_cell: true}
	for breach in breaches:
		reserved[breach.cell] = true
	for index in range(1, rooms.size()):
		var candidate: Vector2i = rooms[index].center
		if not reserved.has(candidate):
			facilities.append(candidate)
	return facilities


func _select_build_pad_cells(path_lookup: Dictionary, facility_cells: Array, vault_cell: Vector2i, breaches: Array) -> Array:
	var reserved := {vault_cell: true}
	for cell in facility_cells:
		reserved[cell] = true
	for breach in breaches:
		reserved[breach.cell] = true

	var candidate_lookup := {}
	for path_cell in path_lookup:
		for direction in CARDINAL_DIRECTIONS:
			var candidate: Vector2i = path_cell + direction
			if _walkable.has(candidate) and not path_lookup.has(candidate) and not reserved.has(candidate):
				candidate_lookup[candidate] = true
	var candidates: Array = candidate_lookup.keys()
	_shuffle(candidates)

	var pads: Array = []
	for candidate in candidates:
		var separated := true
		for existing in pads:
			if _manhattan(candidate, existing) < 2:
				separated = false
				break
		if separated:
			pads.append(candidate)
	# Room geometry normally produces many candidates; this fallback guarantees
	# useful output even if future room dimensions become unusually narrow.
	if pads.size() < 8:
		for candidate in candidates:
			if not pads.has(candidate):
				pads.append(candidate)
			if pads.size() >= 8:
				break
	return _sorted_cells(pads)


func _cells_to_lookup(cells: Array) -> Dictionary:
	var result := {}
	for cell in cells:
		result[cell] = true
	return result


func _sorted_cells(cells: Array) -> Array:
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x)
	)
	return cells


func _shuffle(values: Array) -> void:
	for index in range(values.size() - 1, 0, -1):
		var other := _rng.randi_range(0, index)
		var temporary = values[index]
		values[index] = values[other]
		values[other] = temporary


func _manhattan(first: Vector2i, second: Vector2i) -> int:
	return absi(first.x - second.x) + absi(first.y - second.y)


func _in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < GRID_SIZE.x and cell.y < GRID_SIZE.y
