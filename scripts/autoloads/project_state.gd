extends Node
## Holds the active project's full data in memory. Single source of truth.

const RECENT_PROJECTS_PATH := "user://recent_projects.json"
const MAX_RECENT := 8

var maps: Array[MapData] = []
var current_map_index: int = -1
var tileset: Array[TileDef] = []
var current_project_path: String = ""


func _ready() -> void:
	tileset = TileDef.get_stub_tileset()


func create_new_project() -> void:
	maps.clear()
	current_map_index = -1
	current_project_path = ""
	add_map("Map 001")


func add_map(map_name: String = "New Map") -> MapData:
	var map := MapData.new()
	map.id = maps.size()
	map.map_name = map_name
	map.fill_ground_default()
	maps.append(map)
	current_map_index = maps.size() - 1
	return map


func get_current_map() -> MapData:
	if current_map_index < 0 or current_map_index >= maps.size():
		return null
	return maps[current_map_index]


func select_map(index: int) -> void:
	if index >= 0 and index < maps.size():
		current_map_index = index
		SignalBus.map_selected.emit(index)


func get_tile_def(tile_id: int) -> TileDef:
	if tile_id >= 0 and tile_id < tileset.size():
		return tileset[tile_id]
	return null


# ---------------------------------------------------------------------------
# Save / Load
# ---------------------------------------------------------------------------

func save(path: String = "") -> void:
	if path.is_empty():
		path = current_project_path
	if path.is_empty():
		push_error("ProjectState.save: no path provided")
		return
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("ProjectState.save: could not open file: %s" % path)
		return
	file.store_string(JSON.stringify(serialize(), "\t"))
	file.close()
	current_project_path = path
	_add_to_recent(path)
	SignalBus.project_saved.emit(path)


func load_from(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ProjectState.load_from: could not open file: %s" % path)
		return false
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_error("ProjectState.load_from: invalid JSON in %s" % path)
		return false
	deserialize(parsed)
	current_project_path = path
	_add_to_recent(path)
	SignalBus.project_loaded.emit(path)
	return true


# ---------------------------------------------------------------------------
# Serialization
# ---------------------------------------------------------------------------

func serialize() -> Dictionary:
	var maps_data: Array = []
	for map in maps:
		maps_data.append(_serialize_map(map))
	return { "version": 1, "maps": maps_data }


func deserialize(data: Dictionary) -> void:
	maps.clear()
	current_map_index = -1
	for map_data in data.get("maps", []):
		maps.append(_deserialize_map(map_data))
	if maps.size() > 0:
		current_map_index = 0


func _serialize_map(map: MapData) -> Dictionary:
	var events_data: Array = []
	for ev in map.events:
		events_data.append(_serialize_event(ev))
	return {
		"id": map.id,
		"map_name": map.map_name,
		"width": map.width,
		"height": map.height,
		"ground_layer": _serialize_layer(map.ground_layer),
		"surface_layer": _serialize_layer(map.surface_layer),
		"events": events_data,
	}


func _serialize_layer(layer: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in layer:
		result["%d,%d" % [key.x, key.y]] = layer[key]
	return result


func _serialize_event(ev: EventData) -> Dictionary:
	var pages_data: Array = []
	for page in ev.pages:
		pages_data.append(_serialize_page(page))
	return {
		"id": ev.id,
		"event_name": ev.event_name,
		"x": ev.x,
		"y": ev.y,
		"pages": pages_data,
	}


func _serialize_page(page: EventPage) -> Dictionary:
	var cmds: Array = []
	for cmd in page.commands:
		cmds.append(_serialize_command(cmd))
	return {
		"trigger": page.trigger,
		"graphic_color": [page.graphic_color.r, page.graphic_color.g, page.graphic_color.b, page.graphic_color.a],
		"condition_switch_id": page.condition_switch_id,
		"condition_switch_value": page.condition_switch_value,
		"condition_self_switch": page.condition_self_switch,
		"condition_variable_id": page.condition_variable_id,
		"condition_variable_gte": page.condition_variable_gte,
		"commands": cmds,
	}


func _serialize_command(cmd: EventCommand) -> Dictionary:
	var params: Dictionary = cmd.params.duplicate(true)
	if params.has("commands_if"):
		params["commands_if"] = _serialize_command_array(params["commands_if"])
	if params.has("commands_else"):
		params["commands_else"] = _serialize_command_array(params["commands_else"])
	return { "type": cmd.type, "params": params }


func _serialize_command_array(cmds: Array) -> Array:
	var result: Array = []
	for cmd in cmds:
		result.append(_serialize_command(cmd))
	return result


func _deserialize_map(data: Dictionary) -> MapData:
	var map := MapData.new()
	map.id = data.get("id", 0)
	map.map_name = data.get("map_name", "Untitled")
	map.width = data.get("width", 20)
	map.height = data.get("height", 15)
	map.ground_layer = _deserialize_layer(data.get("ground_layer", {}))
	map.surface_layer = _deserialize_layer(data.get("surface_layer", {}))
	for ev_data in data.get("events", []):
		map.events.append(_deserialize_event(ev_data))
	return map


func _deserialize_layer(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key_str: String in data:
		var parts := key_str.split(",")
		result[Vector2i(int(parts[0]), int(parts[1]))] = int(data[key_str])
	return result


func _deserialize_event(data: Dictionary) -> EventData:
	var ev := EventData.new()
	ev.id = data.get("id", 0)
	ev.event_name = data.get("event_name", "Event")
	ev.x = data.get("x", 0)
	ev.y = data.get("y", 0)
	for page_data in data.get("pages", []):
		ev.pages.append(_deserialize_page(page_data))
	return ev


func _deserialize_page(data: Dictionary) -> EventPage:
	var page := EventPage.new()
	page.trigger = data.get("trigger", 0) as EventPage.Trigger
	var gc: Array = data.get("graphic_color", [0.8, 0.2, 0.2, 1.0])
	page.graphic_color = Color(gc[0], gc[1], gc[2], gc[3])
	page.condition_switch_id = data.get("condition_switch_id", -1)
	page.condition_switch_value = data.get("condition_switch_value", true)
	page.condition_self_switch = data.get("condition_self_switch", "")
	page.condition_variable_id = data.get("condition_variable_id", -1)
	page.condition_variable_gte = data.get("condition_variable_gte", 0)
	var cmds: Array[EventCommand] = []
	for cmd_data in data.get("commands", []):
		cmds.append(_deserialize_command(cmd_data))
	page.commands = cmds
	return page


func _deserialize_command(data: Dictionary) -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = data.get("type", 0) as EventCommand.Type
	var params: Dictionary = data.get("params", {}).duplicate(true)
	if params.has("commands_if"):
		params["commands_if"] = _deserialize_command_array(params["commands_if"])
	if params.has("commands_else"):
		params["commands_else"] = _deserialize_command_array(params["commands_else"])
	cmd.params = params
	return cmd


func _deserialize_command_array(arr: Array) -> Array[EventCommand]:
	var result: Array[EventCommand] = []
	for d in arr:
		result.append(_deserialize_command(d))
	return result


# ---------------------------------------------------------------------------
# Recent projects
# ---------------------------------------------------------------------------

func get_recent_projects() -> Array[String]:
	if not FileAccess.file_exists(RECENT_PROJECTS_PATH):
		return []
	var file := FileAccess.open(RECENT_PROJECTS_PATH, FileAccess.READ)
	if file == null:
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Array:
		return []
	var result: Array[String] = []
	for item in parsed:
		result.append(str(item))
	return result


func remove_from_recent(path: String) -> void:
	var recent := get_recent_projects()
	recent.erase(path)
	var file := FileAccess.open(RECENT_PROJECTS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(recent))
		file.close()


func _add_to_recent(path: String) -> void:
	var recent := get_recent_projects()
	recent.erase(path)
	recent.insert(0, path)
	while recent.size() > MAX_RECENT:
		recent.pop_back()
	var file := FileAccess.open(RECENT_PROJECTS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(recent))
		file.close()
