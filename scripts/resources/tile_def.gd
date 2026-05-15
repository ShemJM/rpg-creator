class_name TileDef
extends Resource

@export var id: int = 0
@export var tile_name: String = ""
@export var color: Color = Color.WHITE
@export var passable: bool = true


static func get_stub_tileset() -> Array[TileDef]:
	var tiles: Array[TileDef] = []
	tiles.append(_make(0, "Grass", Color(0.3, 0.7, 0.3), true))
	tiles.append(_make(1, "Dirt", Color(0.6, 0.4, 0.2), true))
	tiles.append(_make(2, "Stone", Color(0.5, 0.5, 0.55), true))
	tiles.append(_make(3, "Water", Color(0.2, 0.4, 0.8), false))
	tiles.append(_make(4, "Wall", Color(0.25, 0.25, 0.3), false))
	return tiles


static func _make(p_id: int, p_name: String, p_color: Color, p_passable: bool) -> TileDef:
	var t := TileDef.new()
	t.id = p_id
	t.tile_name = p_name
	t.color = p_color
	t.passable = p_passable
	return t
