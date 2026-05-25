class_name RuntimePlayer
extends Node2D
## Play-test runtime. Builds a walkable map from ProjectState and spawns the player.
## Also exposes a scripted API for use by ScenarioRunner and agents.

const CELL_SIZE: int = 32

var _player: CharacterBody2D = null
var _event_runner: EventRunner = null
var _dialogue_box: DialogueBox = null
var _current_map: MapData = null
var _event_running: bool = false
var _last_player_grid: Vector2i = Vector2i(-1, -1)


func _ready() -> void:
	GameState.reset()
	_reset_all_event_self_switches()
	_current_map = ProjectState.get_current_map()
	if _current_map == null:
		SignalBus.playtest_stopped.emit()
		return

	_event_runner = EventRunner.new()
	add_child(_event_runner)
	_event_runner.finished.connect(_on_event_finished)

	_dialogue_box = DialogueBox.new()
	add_child(_dialogue_box)

	SignalBus.transfer_requested.connect(_on_transfer)

	_build_map(_current_map)
	_spawn_player(_current_map)
	_check_autorun_events()


func _build_map(map: MapData) -> void:
	# Draw tiles as colored rects and add collision for impassable ones.
	for coords: Vector2i in map.ground_layer:
		var tile_id: int = map.ground_layer[coords]
		_place_tile(coords, tile_id)

	for coords: Vector2i in map.surface_layer:
		var tile_id: int = map.surface_layer[coords]
		_place_tile(coords, tile_id)

	# Place event visuals.
	for ev: EventData in map.events:
		var page: EventPage = ev.get_active_page()
		if page == null:
			continue
		var ev_visual := ColorRect.new()
		ev_visual.color = page.graphic_color
		ev_visual.size = Vector2(CELL_SIZE - 8, CELL_SIZE - 8)
		ev_visual.position = Vector2(ev.x * CELL_SIZE + 4, ev.y * CELL_SIZE + 4)
		add_child(ev_visual)


func _place_tile(coords: Vector2i, tile_id: int) -> void:
	var tile_def := ProjectState.get_tile_def(tile_id)
	if tile_def == null:
		return

	var world_pos := Vector2(coords) * CELL_SIZE

	# Visual: ColorRect as a child of a Node2D at the position.
	var tile_visual := ColorRect.new()
	tile_visual.color = tile_def.color
	tile_visual.size = Vector2(CELL_SIZE, CELL_SIZE)
	tile_visual.position = world_pos
	add_child(tile_visual)

	# Collision for impassable tiles.
	if not tile_def.passable:
		var body := StaticBody2D.new()
		body.position = world_pos + Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)
		var shape := CollisionShape2D.new()
		var rect_shape := RectangleShape2D.new()
		rect_shape.size = Vector2(CELL_SIZE, CELL_SIZE)
		shape.shape = rect_shape
		body.add_child(shape)
		add_child(body)


func _spawn_player(map: MapData) -> void:
	_player = preload("res://scenes/runtime/PlayerCharacter.tscn").instantiate()
	# Spawn at center of map.
	var center := Vector2(map.width / 2.0, map.height / 2.0) * CELL_SIZE
	_player.position = center
	add_child(_player)

	# Camera follows player — skip in headless mode (no viewport).
	if DisplayServer.get_name() != "headless":
		var camera := Camera2D.new()
		camera.make_current()
		_player.add_child(camera)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		SignalBus.playtest_stopped.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") and not _event_running:
		_try_interact()
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if _event_running or _player == null or _current_map == null:
		return
	var player_grid := Vector2i(
		int(_player.position.x) / CELL_SIZE,
		int(_player.position.y) / CELL_SIZE
	)
	if player_grid == _last_player_grid:
		return
	print("[RT] Player moved to grid: ", player_grid)
	_last_player_grid = player_grid
	SignalBus.trace_player_moved.emit(player_grid, _current_map.id if _current_map else -1)
	_check_touch_events(player_grid)


# ---------------------------------------------------------------------------
# Scripted / Agent API
# ---------------------------------------------------------------------------

## Move the player one tile-step in the given direction.
## In scripted mode this teleports directly to the adjacent cell so callers
## don't have to wait multiple physics frames for the velocity to resolve.
## direction: "left" | "right" | "up" | "down"
func scripted_move(direction: String) -> void:
	if _player == null or _event_running or _current_map == null:
		return
	var current_grid := Vector2i(
		int(_player.position.x) / CELL_SIZE,
		int(_player.position.y) / CELL_SIZE
	)
	var dir_vec: Vector2i
	match direction:
		"left":  dir_vec = Vector2i(-1,  0)
		"right": dir_vec = Vector2i( 1,  0)
		"up":    dir_vec = Vector2i( 0, -1)
		"down":  dir_vec = Vector2i( 0,  1)
		_:       return
	var target := current_grid + dir_vec
	# Bounds check.
	if target.x < 0 or target.x >= _current_map.width or \
	   target.y < 0 or target.y >= _current_map.height:
		return
	# Update facing direction.
	(_player as PlayerCharacter).facing_direction = dir_vec
	# Teleport directly to target cell (top-left corner; grid calc uses int/CELL_SIZE).
	_player.position = Vector2(target) * CELL_SIZE + Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)
	# Emit trace immediately and sync _last_player_grid so _physics_process
	# doesn't double-report the same position on the next frame.
	_last_player_grid = target
	SignalBus.trace_player_moved.emit(target, _current_map.id)
	# Fire PLAYER_TOUCH events (same behaviour as walking manually).
	_check_touch_events(target)


## Trigger the interact action programmatically (same as pressing ui_accept).
func scripted_interact() -> void:
	if not _event_running:
		_try_interact()


## Advance a waiting dialogue programmatically.
func scripted_advance_dialogue() -> void:
	SignalBus.scripted_dialogue_advance.emit()


## Make a choice programmatically (0-based index).
func scripted_make_choice(index: int) -> void:
	SignalBus.scripted_choice_made.emit(index)


## Return a snapshot of the current runtime state as a Dictionary.
## This is the structured output agents and tests should read.
func get_snapshot() -> Dictionary:
	var player_grid := Vector2i(-1, -1)
	if _player:
		player_grid = Vector2i(
			int(_player.position.x) / CELL_SIZE,
			int(_player.position.y) / CELL_SIZE
		)
	var switches: Array = []
	for i in range(GameState.switches.size()):
		if GameState.switches[i]:
			switches.append(i)
	var variables: Dictionary = {}
	for i in range(GameState.variables.size()):
		if GameState.variables[i] != 0:
			variables[str(i)] = GameState.variables[i]
	return {
		"map_id": _current_map.id if _current_map else -1,
		"map_name": _current_map.map_name if _current_map else "",
		"player_grid": { "x": player_grid.x, "y": player_grid.y },
		"event_running": _event_running,
		"switches_on": switches,
		"variables": variables,
	}


func _try_interact() -> void:
	if _current_map == null or _player == null:
		return
	# Check for event at the tile the player is facing.
	var player_grid := Vector2i(
		int(_player.position.x) / CELL_SIZE,
		int(_player.position.y) / CELL_SIZE
	)
	# Check the tile the player is standing on and adjacent tiles.
	var facing: Vector2i = _player.facing_direction
	var target: Vector2i = player_grid + facing
	var ev := _current_map.get_event_at(target)
	if ev == null:
		ev = _current_map.get_event_at(player_grid)
	if ev == null:
		return
	var page: EventPage = ev.get_active_page()
	if page == null:
		return
	if page.trigger == EventPage.Trigger.ACTION_BUTTON:
		_run_event(ev)


func _run_event(ev: EventData) -> void:
	print("[RT] _run_event: ", ev.event_name, " commands=", ev.get_active_page().commands.size())
	_event_running = true
	_event_runner.run_event(ev)


func _on_event_finished() -> void:
	_event_running = false


func _check_autorun_events() -> void:
	if _current_map == null:
		return
	for ev: EventData in _current_map.events:
		var page: EventPage = ev.get_active_page()
		if page and page.trigger == EventPage.Trigger.AUTORUN:
			_run_event(ev)
			return  # Only one autorun at a time.


func _check_touch_events(player_grid: Vector2i) -> void:
	var ev := _current_map.get_event_at(player_grid)
	if ev == null:
		print("[RT] No event at ", player_grid)
		return
	var page: EventPage = ev.get_active_page()
	if page == null:
		print("[RT] Event '%s' has no active page" % ev.event_name)
		return
	print("[RT] Event '%s' trigger=%d (PLAYER_TOUCH=%d)" % [ev.event_name, page.trigger, EventPage.Trigger.PLAYER_TOUCH])
	if page.trigger == EventPage.Trigger.PLAYER_TOUCH:
		print("[RT] Running touch event: ", ev.event_name)
		_run_event(ev)


func _on_transfer(map_id: int, x: int, y: int) -> void:
	var target_map := _find_map_by_id(map_id)
	if target_map == null:
		return
	# Clear current map visuals.
	for child in get_children():
		if child != _event_runner and child != _dialogue_box:
			child.queue_free()
	_current_map = target_map
	_build_map(_current_map)
	_spawn_player(_current_map)
	_player.position = Vector2(x, y) * CELL_SIZE + Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)
	# Sync so _physics_process doesn't re-fire _check_touch_events on the arrival tile.
	_last_player_grid = Vector2i(x, y)
	_check_autorun_events()


func _reset_all_event_self_switches() -> void:
	for map: MapData in ProjectState.maps:
		for ev: EventData in map.events:
			ev.self_switches = { "A": false, "B": false, "C": false, "D": false }


func _find_map_by_id(map_id: int) -> MapData:
	for map: MapData in ProjectState.maps:
		if map.id == map_id:
			return map
	return null
