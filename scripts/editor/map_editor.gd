class_name MapEditor
extends VBoxContainer
## Map editor panel — map list, tile palette, layer/tool selection, and canvas viewport.

var _selected_tile_id: int = 0
var _selected_layer: int = 0
var _selected_tool: String = "pencil"

@onready var _map_list: VBoxContainer = $VSplit/Top/LeftPanel/MapScroll/MapList
@onready var _canvas: MapCanvas = $VSplit/Top/CanvasContainer/SubViewport/MapCanvas
@onready var _palette: HBoxContainer = $VSplit/Bottom/HBox/Palette
@onready var _layer_option: OptionButton = $VSplit/Bottom/HBox/LayerOption
@onready var _tool_option: OptionButton = $VSplit/Bottom/HBox/ToolOption
@onready var _right_panel: PanelContainer = $VSplit/Top/RightPanel
@onready var _import_btn: Button = $VSplit/Bottom/HBox/ImportTilesetBtn


func _ready() -> void:
	_build_palette()
	_build_layer_options()
	_build_tool_options()
	_rebuild_map_list()
	_import_btn.pressed.connect(_on_import_tileset_pressed)
	SignalBus.map_selected.connect(_on_map_selected)
	_canvas.tile_paint_requested.connect(_on_tile_paint)
	_canvas.tile_erase_requested.connect(_on_tile_erase)
	_canvas.tile_fill_requested.connect(_on_tile_fill)
	_canvas.event_place_requested.connect(_on_event_place)
	_canvas.event_select_requested.connect(_on_event_select)


func _build_palette() -> void:
	for child in _palette.get_children():
		child.queue_free()
	for tile_def in ProjectState.tileset:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(44, 44)
		btn.tooltip_text = tile_def.tile_name
		var tex := ProjectState.get_tile_texture(tile_def)
		if tex:
			var tr := TextureRect.new()
			tr.texture = tex
			if tile_def.region.size != Vector2i.ZERO:
				var atlas := AtlasTexture.new()
				atlas.atlas = tex
				atlas.region = Rect2(tile_def.region)
				tr.texture = atlas
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.custom_minimum_size = Vector2(36, 36)
			tr.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
			btn.add_child(tr)
		else:
			var style := StyleBoxFlat.new()
			style.bg_color = tile_def.color
			style.corner_radius_top_left = int(DesignTokens.RADIUS_SM)
			style.corner_radius_top_right = int(DesignTokens.RADIUS_SM)
			style.corner_radius_bottom_left = int(DesignTokens.RADIUS_SM)
			style.corner_radius_bottom_right = int(DesignTokens.RADIUS_SM)
			style.content_margin_left = 4
			style.content_margin_right = 4
			style.content_margin_top = 4
			style.content_margin_bottom = 4
			btn.add_theme_stylebox_override("normal", style)
			var hover_style := style.duplicate()
			hover_style.border_color = DesignTokens.COLOR_TEXT_BRIGHT
			hover_style.border_width_bottom = 2
			hover_style.border_width_top = 2
			hover_style.border_width_left = 2
			hover_style.border_width_right = 2
			btn.add_theme_stylebox_override("hover", hover_style)
		btn.pressed.connect(_on_palette_select.bind(tile_def.id))
		_palette.add_child(btn)


func _build_layer_options() -> void:
	_layer_option.add_item("Ground", 0)
	_layer_option.add_item("Surface", 1)
	_layer_option.item_selected.connect(func(idx: int): _selected_layer = idx; _canvas.active_layer = idx)


func _build_tool_options() -> void:
	_tool_option.add_item("Pencil", 0)
	_tool_option.add_item("Fill", 1)
	_tool_option.add_item("Erase", 2)
	_tool_option.add_item("Event", 3)
	_tool_option.item_selected.connect(_on_tool_selected)


func _on_tool_selected(idx: int) -> void:
	match idx:
		0: _selected_tool = "pencil"
		1: _selected_tool = "fill"
		2: _selected_tool = "erase"
		3: _selected_tool = "event"
	_canvas.active_tool = _selected_tool
	_canvas.event_mode = (_selected_tool == "event")


func _on_palette_select(tile_id: int) -> void:
	_selected_tile_id = tile_id
	_canvas.active_tile_id = tile_id


func _rebuild_map_list() -> void:
	for child in _map_list.get_children():
		child.queue_free()
	for i in range(ProjectState.maps.size()):
		var btn := Button.new()
		btn.text = ProjectState.maps[i].map_name
		btn.pressed.connect(func(): ProjectState.select_map(i))
		_map_list.add_child(btn)
	# Add "New Map" button.
	var new_btn := Button.new()
	new_btn.text = "+ New Map"
	new_btn.pressed.connect(_on_new_map)
	_map_list.add_child(new_btn)


func _on_new_map() -> void:
	var idx := ProjectState.maps.size() + 1
	ProjectState.add_map("Map %03d" % idx)
	_rebuild_map_list()
	_canvas.queue_redraw()


func _on_map_selected(_index: int) -> void:
	_canvas.queue_redraw()


func _on_tile_paint(coords: Vector2i) -> void:
	var map := ProjectState.get_current_map()
	if map:
		map.set_tile(_selected_layer, coords, _selected_tile_id)
		_canvas.queue_redraw()


func _on_tile_erase(coords: Vector2i) -> void:
	var map := ProjectState.get_current_map()
	if map:
		map.erase_tile(_selected_layer, coords)
		_canvas.queue_redraw()


func _on_tile_fill(coords: Vector2i) -> void:
	var map := ProjectState.get_current_map()
	if map == null:
		return
	var target_id := map.get_tile(_selected_layer, coords)
	if target_id == _selected_tile_id:
		return
	_flood_fill(map, _selected_layer, coords, target_id, _selected_tile_id)
	_canvas.queue_redraw()


func _flood_fill(map: MapData, layer: int, start: Vector2i, target_id: int, replace_id: int) -> void:
	var queue: Array[Vector2i] = [start]
	var visited: Dictionary = {}
	while queue.size() > 0:
		var pos: Vector2i = queue.pop_front()
		if visited.has(pos):
			continue
		if pos.x < 0 or pos.x >= map.width or pos.y < 0 or pos.y >= map.height:
			continue
		if map.get_tile(layer, pos) != target_id:
			continue
		visited[pos] = true
		map.set_tile(layer, pos, replace_id)
		queue.append(Vector2i(pos.x + 1, pos.y))
		queue.append(Vector2i(pos.x - 1, pos.y))
		queue.append(Vector2i(pos.x, pos.y + 1))
		queue.append(Vector2i(pos.x, pos.y - 1))


func _on_event_place(coords: Vector2i) -> void:
	var map := ProjectState.get_current_map()
	if map == null:
		return
	var ev := map.add_event(coords.x, coords.y, "Event %03d" % (map.events.size()))
	_canvas.queue_redraw()
	_show_event_panel()
	SignalBus.event_selected.emit(ev)


func _on_event_select(event: EventData) -> void:
	_show_event_panel()
	SignalBus.event_selected.emit(event)


func _show_event_panel() -> void:
	_right_panel.visible = true


func _on_import_tileset_pressed() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.tsj,*.json ; Tiled Tileset"])
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_selected.connect(func(path: String) -> void:
		var err := ProjectState.import_tiled_tileset(path)
		if not err.is_empty():
			push_error("Import tileset failed: %s" % err)
		else:
			_build_palette()
			_canvas.queue_redraw()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)
