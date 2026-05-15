class_name MapData
extends Resource

@export var id: int = 0
@export var map_name: String = "Untitled"
@export var width: int = 20
@export var height: int = 15

## Layer data: Dictionary mapping Vector2i coords to tile_id (int).
var ground_layer: Dictionary = {}
var surface_layer: Dictionary = {}

## Events placed on this map.
var events: Array[EventData] = []


func set_tile(layer: int, coords: Vector2i, tile_id: int) -> void:
	if coords.x < 0 or coords.x >= width or coords.y < 0 or coords.y >= height:
		return
	match layer:
		0: ground_layer[coords] = tile_id
		1: surface_layer[coords] = tile_id


func get_tile(layer: int, coords: Vector2i) -> int:
	match layer:
		0: return ground_layer.get(coords, 0)
		1: return surface_layer.get(coords, -1)
	return -1


func erase_tile(layer: int, coords: Vector2i) -> void:
	match layer:
		0: ground_layer.erase(coords)
		1: surface_layer.erase(coords)


func fill_ground_default() -> void:
	for x in range(width):
		for y in range(height):
			ground_layer[Vector2i(x, y)] = 0


func add_event(x: int, y: int, name: String = "Event") -> EventData:
	var ev := EventData.new()
	ev.id = events.size()
	ev.event_name = name
	ev.x = x
	ev.y = y
	# Add a default page with action_button trigger.
	var page := EventPage.new()
	page.trigger = EventPage.Trigger.ACTION_BUTTON
	ev.pages.append(page)
	events.append(ev)
	return ev


func get_event_at(coords: Vector2i) -> EventData:
	for ev in events:
		if ev.x == coords.x and ev.y == coords.y:
			return ev
	return null


func remove_event(ev: EventData) -> void:
	events.erase(ev)
