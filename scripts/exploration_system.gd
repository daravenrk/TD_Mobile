class_name ExplorationSystem
extends RefCounted

## Grid-space fog-of-war state for a single observer.
##
## Cells inside [vision_radius] use a circular footprint. Visible cells are
## replaced whenever the observer changes cells, while explored cells persist
## until [reset] is called for a new map.

signal visibility_changed(center: Vector2i, newly_visible_count: int, newly_explored_count: int)

const UNSEEN := 0
const EXPLORED := 1
const VISIBLE := 2
const INVALID_CELL := Vector2i(-1, -1)
const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.UP,
	Vector2i.DOWN,
]

var grid_size := Vector2i(30, 22)
var vision_radius := 4
var observer_cell := INVALID_CELL

var _visible_cells: Dictionary = {}
var _explored_cells: Dictionary = {}
var _vision_offsets: Array[Vector2i] = []


func _init(initial_grid_size: Vector2i = Vector2i(30, 22), initial_vision_radius: int = 4) -> void:
	reset(initial_grid_size, initial_vision_radius)


## Clears all fog state and configures the bounds for a newly generated map.
func reset(new_grid_size: Vector2i = Vector2i(30, 22), new_vision_radius: int = 4) -> void:
	grid_size = Vector2i(maxi(1, new_grid_size.x), maxi(1, new_grid_size.y))
	vision_radius = maxi(0, new_vision_radius)
	observer_cell = INVALID_CELL
	_visible_cells.clear()
	_explored_cells.clear()
	_rebuild_vision_offsets()


func set_vision_radius(new_radius: int) -> void:
	var clamped_radius := maxi(0, new_radius)
	if clamped_radius == vision_radius:
		return
	vision_radius = clamped_radius
	_rebuild_vision_offsets()
	# Force the caller's next update to recalculate visibility.
	observer_cell = INVALID_CELL


## Updates fog state after the observer enters a grid cell.
## Returns false when no recalculation was needed or the cell is out of bounds.
func update_visibility(new_observer_cell: Vector2i, force: bool = false) -> bool:
	if not is_in_bounds(new_observer_cell):
		return false
	if not force and new_observer_cell == observer_cell:
		return false

	observer_cell = new_observer_cell
	var previous_visible := _visible_cells
	var next_visible: Dictionary = {}
	var newly_visible_count := 0
	var newly_explored_count := 0

	for offset in _vision_offsets:
		var cell := observer_cell + offset
		if not is_in_bounds(cell):
			continue
		next_visible[cell] = true
		if not previous_visible.has(cell):
			newly_visible_count += 1
		if not _explored_cells.has(cell):
			_explored_cells[cell] = true
			newly_explored_count += 1

	_visible_cells = next_visible
	visibility_changed.emit(observer_cell, newly_visible_count, newly_explored_count)
	return true


## Convenience adapter for game state stored as a floating-point grid position.
func update_from_grid_position(grid_position: Vector2, force: bool = false) -> bool:
	return update_visibility(Vector2i(roundi(grid_position.x), roundi(grid_position.y)), force)


func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid_size.x and cell.y < grid_size.y


func is_visible(cell: Vector2i) -> bool:
	return _visible_cells.has(cell)


func is_explored(cell: Vector2i) -> bool:
	return _explored_cells.has(cell)


func get_cell_state(cell: Vector2i) -> int:
	if is_visible(cell):
		return VISIBLE
	if is_explored(cell):
		return EXPLORED
	return UNSEEN


func get_visible_count() -> int:
	return _visible_cells.size()


func get_explored_count() -> int:
	return _explored_cells.size()


## Returned arrays are copies and can safely be sorted or modified by callers.
func get_visible_cells() -> Array[Vector2i]:
	return _dictionary_cells(_visible_cells)


func get_explored_cells() -> Array[Vector2i]:
	return _dictionary_cells(_explored_cells)


## Returns unexplored cells bordering explored territory. This is useful for
## exploration objectives, minimap hints, and choosing procedural discoveries.
func get_frontier_cells() -> Array[Vector2i]:
	var frontier: Dictionary = {}
	for explored_cell_value in _explored_cells:
		var explored_cell: Vector2i = explored_cell_value
		for direction in CARDINAL_DIRECTIONS:
			var candidate := explored_cell + direction
			if is_in_bounds(candidate) and not _explored_cells.has(candidate):
				frontier[candidate] = true
	return _dictionary_cells(frontier)


## Finds the closest threat that is currently observable. Threat entries may
## be Vector2i or floating-point grid positions. INVALID_CELL means no match.
func get_nearest_visible_threat(origin: Vector2i, threat_cells: Array) -> Vector2i:
	var nearest := INVALID_CELL
	var nearest_distance_squared := INF
	for threat_value in threat_cells:
		var threat_cell := _as_cell(threat_value)
		if threat_cell == INVALID_CELL or not is_visible(threat_cell):
			continue
		var distance_squared := origin.distance_squared_to(threat_cell)
		if distance_squared < nearest_distance_squared:
			nearest = threat_cell
			nearest_distance_squared = distance_squared
	return nearest


## Returns a normalized grid-space direction to the closest visible threat.
## Vector2.ZERO means no visible threat or a threat on the observer's cell.
func get_visible_threat_direction(origin: Vector2i, threat_cells: Array) -> Vector2:
	var threat_cell := get_nearest_visible_threat(origin, threat_cells)
	if threat_cell == INVALID_CELL:
		return Vector2.ZERO
	return Vector2(threat_cell - origin).normalized()


## Converts a grid-space direction to the screen-space direction used by a
## standard 2:1 isometric projection. Useful for compass and warning arrows.
func grid_direction_to_isometric(grid_direction: Vector2) -> Vector2:
	var screen_direction := Vector2(
		grid_direction.x - grid_direction.y,
		(grid_direction.x + grid_direction.y) * 0.5
	)
	return screen_direction.normalized()


func _rebuild_vision_offsets() -> void:
	_vision_offsets.clear()
	var radius_squared := vision_radius * vision_radius
	for y in range(-vision_radius, vision_radius + 1):
		for x in range(-vision_radius, vision_radius + 1):
			if x * x + y * y <= radius_squared:
				_vision_offsets.append(Vector2i(x, y))


func _dictionary_cells(source: Dictionary) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell_value in source:
		result.append(cell_value)
	return result


func _as_cell(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Vector2:
		return Vector2i(roundi(value.x), roundi(value.y))
	return INVALID_CELL
