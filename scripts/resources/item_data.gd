class_name ItemData
extends Resource
## A usable/held item. Effect execution (heal, etc.) is wired up in the party phase;
## here `effect` is authored data only.

@export var id: int = 0
@export var item_name: String = "New Item"
@export var description: String = ""
@export var price: int = 0
@export var consumable: bool = true
## Free-form effect params, e.g. { "hp": 100, "mp": 0 }. Interpreted in a later phase.
@export var effect: Dictionary = {}


func _init() -> void:
	# Give each instance its own dict — an exported `{}` default can otherwise be
	# shared across instances in Godot.
	effect = {}


func to_dict() -> Dictionary:
	return {
		"id": id,
		"item_name": item_name,
		"description": description,
		"price": price,
		"consumable": consumable,
		"effect": effect.duplicate(true),
	}


static func from_dict(d: Dictionary) -> ItemData:
	var it := ItemData.new()
	it.id = int(d.get("id", 0))
	it.item_name = str(d.get("item_name", "New Item"))
	it.description = str(d.get("description", ""))
	it.price = int(d.get("price", 0))
	it.consumable = bool(d.get("consumable", true))
	var eff = d.get("effect", {})
	it.effect = (eff as Dictionary).duplicate(true) if eff is Dictionary else {}
	return it
