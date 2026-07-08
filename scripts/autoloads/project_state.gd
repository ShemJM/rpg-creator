extends Node
## Holds the active project's full data in memory. Single source of truth.

const RECENT_PROJECTS_PATH := "user://recent_projects.json"
const MAX_RECENT := 8

var maps: Array[MapData] = []
var current_map_index: int = -1
var tileset: Array[TileDef] = []
var current_project_path: String = ""
## Default spritesheet for the play-test player. Null = colour-block fallback.
var player_graphic: CharacterGraphic = null

var _texture_cache: Dictionary = {}


func _ready() -> void:
	tileset = TileDef.get_stub_tileset()


## Load and cache a texture from an absolute path. Returns null if missing/invalid.
## Shared by tiles and character graphics.
func load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _texture_cache.has(path):
		return _texture_cache[path]
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null:
		return null
	var tex := ImageTexture.create_from_image(img)
	_texture_cache[path] = tex
	return tex


func get_tile_texture(tile_def: TileDef) -> Texture2D:
	return load_texture(tile_def.source_path)


## Import a Tiled tileset JSON (.tsj / .json).
## Replaces the current tileset with the imported tiles.
## Returns an error string on failure, empty string on success.
func import_tiled_tileset(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "Could not open file: %s" % path
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return "Invalid JSON in: %s" % path
	var data: Dictionary = parsed
	var img_rel: String = data.get("image", "")
	if img_rel.is_empty():
		return "Tileset has no 'image' field"
	# Resolve image path relative to the .tsj file.
	var base_dir := path.get_base_dir()
	var img_path := (base_dir + "/" + img_rel).simplify_path()
	var tw: int = data.get("tilewidth", 32)
	var th: int = data.get("tileheight", 32)
	var columns: int = data.get("columns", 1)
	var tile_count: int = data.get("tilecount", 0)
	if tw <= 0 or th <= 0 or columns <= 0 or tile_count <= 0:
		return "Tileset has invalid tile dimensions or count"
	# Build per-tile property map from the optional 'tiles' array.
	var tile_props: Dictionary = {}
	for tile_entry in data.get("tiles", []):
		var tid: int = tile_entry.get("id", -1)
		if tid < 0:
			continue
		var props: Dictionary = {}
		for prop in tile_entry.get("properties", []):
			props[prop.get("name", "")] = prop.get("value")
		tile_props[tid] = props
	tileset.clear()
	_texture_cache.erase(img_path)
	for i in range(tile_count):
		var t := TileDef.new()
		t.id = i
		var col := i % columns
		var row := i / columns
		t.source_path = img_path
		t.region = Rect2i(col * tw, row * th, tw, th)
		t.tile_name = "Tile %d" % i
		t.passable = true
		if tile_props.has(i):
			var p: Dictionary = tile_props[i]
			if p.has("passable"):
				t.passable = bool(p["passable"])
			if p.has("name"):
				t.tile_name = str(p["name"])
		tileset.append(t)
	return ""


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
# Authoring service API — for use by agents, MCP tools, and scenario scripts
# ---------------------------------------------------------------------------

## Find a map by its integer id.
func get_map_by_id(map_id: int) -> MapData:
	for map in maps:
		if map.id == map_id:
			return map
	return null


## Add a new map with explicit dimensions.
func add_map_sized(map_name: String, width: int, height: int) -> MapData:
	var map := MapData.new()
	map.id = maps.size()
	map.map_name = map_name
	map.width = width
	map.height = height
	map.fill_ground_default()
	maps.append(map)
	current_map_index = maps.size() - 1
	return map


## Paint a single tile on a layer.  layer 0 = ground, 1 = surface.
func paint_tile(map_id: int, layer: int, x: int, y: int, tile_id: int) -> bool:
	var map := get_map_by_id(map_id)
	if map == null:
		return false
	map.set_tile(layer, Vector2i(x, y), tile_id)
	return true


## Fill a rectangle on a layer with one tile id.
func fill_rect(map_id: int, layer: int, x: int, y: int, w: int, h: int, tile_id: int) -> bool:
	var map := get_map_by_id(map_id)
	if map == null:
		return false
	for ty in range(y, y + h):
		for tx in range(x, x + w):
			map.set_tile(layer, Vector2i(tx, ty), tile_id)
	return true


## Place an event and return it.  Returns null if map not found.
func place_event(map_id: int, x: int, y: int, event_name: String = "Event") -> EventData:
	var map := get_map_by_id(map_id)
	if map == null:
		return null
	return map.add_event(x, y, event_name)


## Append a command to a specific event page.
## Returns false if the event or page index is invalid.
func append_command(map_id: int, event_id: int, page_index: int, cmd: EventCommand) -> bool:
	var map := get_map_by_id(map_id)
	if map == null:
		return false
	for ev in map.events:
		if ev.id == event_id:
			if page_index < 0 or page_index >= ev.pages.size():
				return false
			ev.pages[page_index].commands.append(cmd)
			return true
	return false


## Return a lightweight summary of all maps for agent inspection.
func list_maps() -> Array:
	var result: Array = []
	for map in maps:
		result.append({
			"id": map.id,
			"name": map.map_name,
			"width": map.width,
			"height": map.height,
			"event_count": map.events.size(),
		})
	return result


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
	var tileset_data: Array = []
	for t in tileset:
		tileset_data.append({
			"id": t.id,
			"tile_name": t.tile_name,
			"color": [t.color.r, t.color.g, t.color.b, t.color.a],
			"passable": t.passable,
			"source_path": t.source_path,
			"region": [t.region.position.x, t.region.position.y, t.region.size.x, t.region.size.y],
		})
	return {
		"version": 2,
		"maps": maps_data,
		"tileset": tileset_data,
		"player_graphic": player_graphic.to_dict() if player_graphic else null,
	}


func deserialize(data: Dictionary) -> void:
	maps.clear()
	current_map_index = -1
	_texture_cache.clear()
	var raw_tileset: Array = data.get("tileset", [])
	if raw_tileset.is_empty():
		tileset = TileDef.get_stub_tileset()
	else:
		tileset.clear()
		for td in raw_tileset:
			var t := TileDef.new()
			t.id = td.get("id", 0)
			t.tile_name = td.get("tile_name", "Tile")
			var c: Array = td.get("color", [1, 1, 1, 1])
			t.color = Color(c[0], c[1], c[2], c[3])
			t.passable = td.get("passable", true)
			t.source_path = td.get("source_path", "")
			var r: Array = td.get("region", [0, 0, 0, 0])
			t.region = Rect2i(r[0], r[1], r[2], r[3])
			tileset.append(t)
	# Player graphic (added in version 2; absent in v1 projects → null fallback).
	var pg = data.get("player_graphic", null)
	player_graphic = CharacterGraphic.from_dict(pg) if pg is Dictionary else null
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
		"graphic": page.graphic.to_dict() if page.graphic else null,
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
	var pg = data.get("graphic", null)
	page.graphic = CharacterGraphic.from_dict(pg) if pg is Dictionary else null
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
