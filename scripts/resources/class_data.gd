class_name ClassData
extends Resource
## A character class (job). Holds base stats; skills/learnings arrive with the combat phase.

@export var id: int = 0
@export var class_name_: String = "New Class"  ## `class_name` is a reserved keyword
@export var stats: StatBlock = null
@export var note: String = ""


func _init() -> void:
	if stats == null:
		stats = StatBlock.new()


func to_dict() -> Dictionary:
	return {
		"id": id,
		"class_name": class_name_,
		"stats": stats.to_dict(),
		"note": note,
	}


static func from_dict(d: Dictionary) -> ClassData:
	var c := ClassData.new()
	c.id = int(d.get("id", 0))
	c.class_name_ = str(d.get("class_name", "New Class"))
	c.stats = StatBlock.from_dict(d.get("stats", {}))
	c.note = str(d.get("note", ""))
	return c
