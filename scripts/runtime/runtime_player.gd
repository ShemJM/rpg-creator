class_name RuntimePlayer
extends Node2D
## Play-test runtime. Builds a walkable map from ProjectState and spawns the player.
## Also exposes a scripted API for use by ScenarioRunner and agents.

const CELL_SIZE: int = 32
const MOVE_ROUTE_STEP_SECONDS: float = 0.15

var _player: CharacterBody2D = null
var _event_runner: EventRunner = null
var _dialogue_box: DialogueBox = null
var _current_map: MapData = null
var _event_running: bool = false
var _last_player_grid: Vector2i = Vector2i(-1, -1)

var _fade_layer: CanvasLayer = null
var _fade_rect: ColorRect = null
var _fade_tween: Tween = null

var _event_visuals: Dictionary = {}       # event_id -> ColorRect
var _parallel_runners: Dictionary = {}    # event_id -> EventRunner
var _last_active_pages: Dictionary = {}   # event_id -> active page index (-1 = none)
var _pending_autoruns: Array = []         # EventData queued while another event runs
var _refresh_queued: bool = false


func _ready() -> void:
	GameState.reset()
	_reset_all_event_runtime_state()
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
	SignalBus.fade_requested.connect(_on_fade_requested)
	SignalBus.move_route_requested.connect(_on_move_route_requested)
	SignalBus.game_over_requested.connect(_on_game_over)
	SignalBus.event_erased.connect(func(_event_id: int): _queue_refresh_events())
	SignalBus.trace_switch_changed.connect(func(_id: int, _v: bool): _queue_refresh_events())
	SignalBus.trace_variable_changed.connect(func(_id: int, _v: int): _queue_refresh_events())
	SignalBus.trace_self_switch_changed.connect(func(_id: int, _l: String, _v: bool): _queue_refresh_events())

	_build_fade_layer()
	_build_map(_current_map)
	_spawn_player(_current_map)
	_init_page_tracking()
	_check_autorun_events()
	_refresh_parallel_events()


func _build_map(map: MapData) -> void:
	# Draw tiles as colored rects and add collision for impassable ones.
	for coords: Vector2i in map.ground_layer:
		var tile_id: int = map.ground_layer[coords]
		_place_tile(coords, tile_id)

	for coords: Vector2i in map.surface_layer:
		var tile_id: int = map.surface_layer[coords]
		_place_tile(coords, tile_id)

	# Place event visuals. Every event gets a marker so page changes can
	# show/hide or recolour it later without rebuilding the map.
	for ev: EventData in map.events:
		var ev_visual := ColorRect.new()
		ev_visual.size = Vector2(CELL_SIZE - 8, CELL_SIZE - 8)
		ev_visual.position = Vector2(ev.x * CELL_SIZE + 4, ev.y * CELL_SIZE + 4)
		var page: EventPage = ev.get_active_page()
		ev_visual.visible = page != null
		if page:
			ev_visual.color = page.graphic_color
		add_child(ev_visual)
		_event_visuals[ev.id] = ev_visual


func _place_tile(coords: Vector2i, tile_id: int) -> void:
	var tile_def := ProjectState.get_tile_def(tile_id)
	if tile_def == null:
		return

	var world_pos := Vector2(coords) * CELL_SIZE

	var tex := ProjectState.get_tile_texture(tile_def)
	if tex:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		var src := Rect2(tile_def.region) if tile_def.region.size != Vector2i.ZERO \
				else Rect2(Vector2.ZERO, Vector2(tex.get_width(), tex.get_height()))
		sprite.region_enabled = true
		sprite.region_rect = src
		sprite.position = world_pos + Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)
		sprite.scale = Vector2(CELL_SIZE, CELL_SIZE) / src.size
		add_child(sprite)
	else:
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
	# Run any autorun whose page became active while another event was running.
	while not _pending_autoruns.is_empty():
		var ev: EventData = _pending_autoruns.pop_front()
		var page: EventPage = ev.get_active_page()
		if page and page.trigger == EventPage.Trigger.AUTORUN:
			_run_event(ev)
			return


func _check_autorun_events() -> void:
	if _current_map == null:
		return
	var first: EventData = null
	for ev: EventData in _current_map.events:
		var page: EventPage = ev.get_active_page()
		if page and page.trigger == EventPage.Trigger.AUTORUN:
			if first == null:
				first = ev
			else:
				_pending_autoruns.append(ev)  # Runs when the first one finishes.
	if first:
		_run_event(first)


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
	_stop_parallel_runners()
	_event_visuals.clear()
	_last_active_pages.clear()
	_pending_autoruns.clear()
	# Clear current map visuals.
	for child in get_children():
		if child != _event_runner and child != _dialogue_box and child != _fade_layer:
			child.queue_free()
	_current_map = target_map
	_build_map(_current_map)
	_spawn_player(_current_map)
	_player.position = Vector2(x, y) * CELL_SIZE + Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)
	# Sync so _physics_process doesn't re-fire _check_touch_events on the arrival tile.
	_last_player_grid = Vector2i(x, y)
	_init_page_tracking()
	_check_autorun_events()
	_refresh_parallel_events()


# ---------------------------------------------------------------------------
# Page re-evaluation & parallel events
# ---------------------------------------------------------------------------

## Record each event's current active page so later refreshes only react to
## *changes* (autorun is edge-triggered, not level-triggered).
func _init_page_tracking() -> void:
	_last_active_pages.clear()
	for ev: EventData in _current_map.events:
		_last_active_pages[ev.id] = _active_page_index(ev)


func _active_page_index(ev: EventData) -> int:
	var page: EventPage = ev.get_active_page()
	return ev.pages.find(page) if page else -1


## Batch refreshes to the next idle frame so a burst of switch/variable
## changes inside one command list re-evaluates pages only once.
func _queue_refresh_events() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_refresh_events.call_deferred()


func _refresh_events() -> void:
	_refresh_queued = false
	if _current_map == null:
		return
	for ev: EventData in _current_map.events:
		var page: EventPage = ev.get_active_page()
		var visual: ColorRect = _event_visuals.get(ev.id)
		if visual:
			visual.visible = page != null
			if page:
				visual.color = page.graphic_color
			visual.position = Vector2(ev.x * CELL_SIZE + 4, ev.y * CELL_SIZE + 4)
		var page_index: int = ev.pages.find(page) if page else -1
		if page_index != _last_active_pages.get(ev.id, -1):
			_last_active_pages[ev.id] = page_index
			if page and page.trigger == EventPage.Trigger.AUTORUN:
				if _event_running:
					_pending_autoruns.append(ev)
				else:
					_run_event(ev)
	_refresh_parallel_events()


func _refresh_parallel_events() -> void:
	if _current_map == null:
		return
	# Stop runners whose page is no longer an active parallel page.
	for event_id in _parallel_runners.keys():
		var ev := _find_event_by_id(event_id)
		var page: EventPage = ev.get_active_page() if ev else null
		if page == null or page.trigger != EventPage.Trigger.PARALLEL:
			var runner: EventRunner = _parallel_runners[event_id]
			runner.stop()
			runner.queue_free()
			_parallel_runners.erase(event_id)
	# Start runners for newly active parallel pages.
	for ev: EventData in _current_map.events:
		var page: EventPage = ev.get_active_page()
		if page and page.trigger == EventPage.Trigger.PARALLEL and not _parallel_runners.has(ev.id):
			var runner := EventRunner.new()
			add_child(runner)
			_parallel_runners[ev.id] = runner
			runner.finished.connect(_on_parallel_finished.bind(ev, runner))
			runner.run_event(ev)


func _on_parallel_finished(ev: EventData, runner: EventRunner) -> void:
	# Parallel pages loop while their conditions hold; restart next idle frame.
	_restart_parallel.call_deferred(ev, runner)


func _restart_parallel(ev: EventData, runner: EventRunner) -> void:
	if _parallel_runners.get(ev.id) != runner:
		return  # Runner was stopped/replaced in the meantime.
	var page: EventPage = ev.get_active_page()
	if page and page.trigger == EventPage.Trigger.PARALLEL:
		runner.run_event(ev)
	else:
		runner.stop()
		runner.queue_free()
		_parallel_runners.erase(ev.id)


func _stop_parallel_runners() -> void:
	for event_id in _parallel_runners:
		var runner: EventRunner = _parallel_runners[event_id]
		runner.stop()
		runner.queue_free()
	_parallel_runners.clear()


# ---------------------------------------------------------------------------
# Screen fade
# ---------------------------------------------------------------------------

func _build_fade_layer() -> void:
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 100
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_layer.add_child(_fade_rect)
	add_child(_fade_layer)


func _on_fade_requested(direction: String, duration: float) -> void:
	var target_alpha: float = 1.0 if direction == "out" else 0.0
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_rect, "color:a", target_alpha, maxf(duration, 0.01))
	_fade_tween.finished.connect(func(): SignalBus.fade_finished.emit())


# ---------------------------------------------------------------------------
# Move routes
# ---------------------------------------------------------------------------

func _on_move_route_requested(event_id: int, target: String, steps: Array) -> void:
	_execute_move_route(event_id, target, steps)


func _execute_move_route(event_id: int, target: String, steps: Array) -> void:
	for step in steps:
		var step_name := str(step)
		if step_name != "wait":
			var dir := _direction_vector(step_name)
			if dir == Vector2i.ZERO:
				continue
			if target == "player":
				_step_player(dir)
			else:
				_step_event(event_id, dir)
		await get_tree().create_timer(MOVE_ROUTE_STEP_SECONDS).timeout
		if not is_inside_tree():
			return  # Play-test ended mid-route.
	SignalBus.move_route_finished.emit()


func _direction_vector(direction: String) -> Vector2i:
	match direction:
		"left":  return Vector2i(-1, 0)
		"right": return Vector2i(1, 0)
		"up":    return Vector2i(0, -1)
		"down":  return Vector2i(0, 1)
	return Vector2i.ZERO


func _step_player(dir: Vector2i) -> void:
	if _player == null or _current_map == null:
		return
	(_player as PlayerCharacter).facing_direction = dir
	var current := Vector2i(
		int(_player.position.x) / CELL_SIZE,
		int(_player.position.y) / CELL_SIZE
	)
	var target_cell := current + dir
	if not _is_cell_passable(target_cell):
		return  # Blocked: keep facing, skip the step.
	_player.position = Vector2(target_cell) * CELL_SIZE + Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)
	_last_player_grid = target_cell
	SignalBus.trace_player_moved.emit(target_cell, _current_map.id)


func _step_event(event_id: int, dir: Vector2i) -> void:
	var ev := _find_event_by_id(event_id)
	if ev == null:
		return
	var target_cell := Vector2i(ev.x, ev.y) + dir
	if not _is_cell_passable(target_cell):
		return
	ev.x = target_cell.x
	ev.y = target_cell.y
	var visual: ColorRect = _event_visuals.get(event_id)
	if visual:
		visual.position = Vector2(ev.x * CELL_SIZE + 4, ev.y * CELL_SIZE + 4)


func _is_cell_passable(cell: Vector2i) -> bool:
	if _current_map == null:
		return false
	if cell.x < 0 or cell.x >= _current_map.width or cell.y < 0 or cell.y >= _current_map.height:
		return false
	for tile_id in [_current_map.get_tile(0, cell), _current_map.get_tile(1, cell)]:
		var tile_def := ProjectState.get_tile_def(tile_id)
		if tile_def and not tile_def.passable:
			return false
	return true


# ---------------------------------------------------------------------------
# Game over
# ---------------------------------------------------------------------------

func _on_game_over() -> void:
	SignalBus.playtest_stopped.emit()


func _reset_all_event_runtime_state() -> void:
	for map: MapData in ProjectState.maps:
		for ev: EventData in map.events:
			ev.self_switches = { "A": false, "B": false, "C": false, "D": false }
			ev.erased = false


func _find_map_by_id(map_id: int) -> MapData:
	for map: MapData in ProjectState.maps:
		if map.id == map_id:
			return map
	return null


func _find_event_by_id(event_id: int) -> EventData:
	if _current_map == null:
		return null
	for ev: EventData in _current_map.events:
		if ev.id == event_id:
			return ev
	return null
