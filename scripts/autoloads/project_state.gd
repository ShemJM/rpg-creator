extends Node
## Holds the active project's full data in memory. Single source of truth.

var maps: Array[MapData] = []
var current_map_index: int = -1
var tileset: Array[TileDef] = []


func _ready() -> void:
	tileset = TileDef.get_stub_tileset()
	create_new_project()


func create_new_project() -> void:
	maps.clear()
	current_map_index = -1
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
