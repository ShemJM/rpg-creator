class_name ActorData
extends Resource
## A playable character. Reuses CharacterGraphic (Phase A) for the map charset.

@export var id: int = 0
@export var actor_name: String = "New Actor"
@export var class_id: int = -1  ## -1 = none
@export var initial_level: int = 1
@export var stats: StatBlock = null
@export var graphic: CharacterGraphic = null  ## map charset; null = colour fallback
@export var note: String = ""


func _init() -> void:
	if stats == null:
		stats = StatBlock.new()


func to_dict() -> Dictionary:
	return {
		"id": id,
		"actor_name": actor_name,
		"class_id": class_id,
		"initial_level": initial_level,
		"stats": stats.to_dict(),
		"graphic": graphic.to_dict() if graphic else null,
		"note": note,
	}


static func from_dict(d: Dictionary) -> ActorData:
	var a := ActorData.new()
	a.id = int(d.get("id", 0))
	a.actor_name = str(d.get("actor_name", "New Actor"))
	a.class_id = int(d.get("class_id", -1))
	a.initial_level = int(d.get("initial_level", 1))
	a.stats = StatBlock.from_dict(d.get("stats", {}))
	var g = d.get("graphic", null)
	a.graphic = CharacterGraphic.from_dict(g) if g is Dictionary else null
	a.note = str(d.get("note", ""))
	return a
