class_name MapCanvas
extends Node2D
## Draws the map grid from ProjectState and handles paint input.

const CELL_SIZE: int = 32

signal tile_paint_requested(coords: Vector2i)
signal tile_erase_requested(coords: Vector2i)
signal tile_fill_requested(coords: Vector2i)
signal event_place_requested(coords: Vector2i)
signal event_select_requested(event: EventData)

var active_tile_id: int = 0
var active_layer: int = 0
var active_tool: String = "pencil"
var event_mode: bool = false

var _is_painting: bool = false
var _camera_drag: bool = false
var _drag_start: Vector2 = Vector2.ZERO


func _ready() -> void:
	SignalBus.map_selected.connect(func(_i: int): queue_redraw())


func _draw() -> void:
	var map := ProjectState.get_current_map()
	if map == null:
		return

	# Draw ground layer.
	for coords: Vector2i in map.ground_layer:
		var tile_id: int = map.ground_layer[coords]
		var tile_def := ProjectState.get_tile_def(tile_id)
		if tile_def:
			_draw_tile(tile_def, Vector2(coords) * CELL_SIZE)

	# Draw surface layer on top.
	for coords: Vector2i in map.surface_layer:
		var tile_id: int = map.surface_layer[coords]
		var tile_def := ProjectState.get_tile_def(tile_id)
		if tile_def:
			_draw_tile(tile_def, Vector2(coords) * CELL_SIZE)

	# Draw grid lines.
	var grid_color := Color(0.0, 0.0, 0.0, 0.15)
	for x in range(map.width + 1):
		draw_line(Vector2(x * CELL_SIZE, 0), Vector2(x * CELL_SIZE, map.height * CELL_SIZE), grid_color)
	for y in range(map.height + 1):
		draw_line(Vector2(0, y * CELL_SIZE), Vector2(map.width * CELL_SIZE, y * CELL_SIZE), grid_color)

	# Draw events.
	for ev: EventData in map.events:
		var ev_rect := Rect2(Vector2(ev.x, ev.y) * CELL_SIZE + Vector2(4, 4), Vector2(CELL_SIZE - 8, CELL_SIZE - 8))
		var page: EventPage = ev.get_active_page()
		var ev_color := page.graphic_color if page else Color(0.8, 0.2, 0.2)
		draw_rect(ev_rect, ev_color)
		# Draw a small "E" label.
		draw_string(ThemeDB.fallback_font, Vector2(ev.x * CELL_SIZE + 8, ev.y * CELL_SIZE + 22), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

	# Draw hover highlight.
	var mouse_pos := get_local_mouse_position()
	var hover_coords := _world_to_grid(mouse_pos)
	if _is_in_bounds(hover_coords):
		var hover_rect := Rect2(Vector2(hover_coords) * CELL_SIZE, Vector2(CELL_SIZE, CELL_SIZE))
		draw_rect(hover_rect, Color(1, 1, 1, 0.3), false, 2.0)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_painting = true
				_handle_paint(mb.position)
			else:
				_is_painting = false
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_camera_drag = mb.pressed
			if mb.pressed:
				_drag_start = mb.position
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			scale *= 1.1
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scale *= 0.9
			scale = scale.clamp(Vector2(0.2, 0.2), Vector2(5.0, 5.0))

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _is_painting:
			_handle_paint(mm.position)
		elif _camera_drag:
			position += mm.relative
		queue_redraw()


func _handle_paint(screen_pos: Vector2) -> void:
	var local_pos := get_local_mouse_position()
	var coords := _world_to_grid(local_pos)
	if not _is_in_bounds(coords):
		return
	if event_mode:
		var map := ProjectState.get_current_map()
		if map:
			var existing := map.get_event_at(coords)
			if existing:
				event_select_requested.emit(existing)
			else:
				event_place_requested.emit(coords)
		_is_painting = false
		return
	match active_tool:
		"pencil":
			tile_paint_requested.emit(coords)
		"erase":
			tile_erase_requested.emit(coords)
		"fill":
			tile_fill_requested.emit(coords)
			_is_painting = false  # Only fill once per click.


func _world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x) / CELL_SIZE, int(world_pos.y) / CELL_SIZE)


func _is_in_bounds(coords: Vector2i) -> bool:
	var map := ProjectState.get_current_map()
	if map == null:
		return false
	return coords.x >= 0 and coords.x < map.width and coords.y >= 0 and coords.y < map.height


func _draw_tile(tile_def: TileDef, world_pos: Vector2) -> void:
	var dest := Rect2(world_pos, Vector2(CELL_SIZE, CELL_SIZE))
	var tex := ProjectState.get_tile_texture(tile_def)
	if tex:
		var src := Rect2(tile_def.region) if tile_def.region.size != Vector2i.ZERO else Rect2(Vector2.ZERO, Vector2(tex.get_width(), tex.get_height()))
		draw_texture_rect_region(tex, dest, src)
	else:
		draw_rect(dest, tile_def.color)
