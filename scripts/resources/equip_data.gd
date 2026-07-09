class_name EquipData
extends Resource
## A piece of equipment. One class covers both weapons and armor, distinguished by `kind`;
## the database editor shows them under separate Weapons/Armor tabs filtered by `kind`.

const KIND_WEAPON := "weapon"
const KIND_ARMOR := "armor"

@export var id: int = 0
@export var equip_name: String = "New Equipment"
@export var kind: String = KIND_WEAPON  ## "weapon" | "armor"
@export var slot: String = ""           ## e.g. "weapon", "head", "body", "accessory"
@export var description: String = ""
@export var price: int = 0
@export var stat_mods: StatBlock = null  ## additive stat bonuses when equipped
@export var note: String = ""


func _init() -> void:
	if stat_mods == null:
		# Equipment bonuses default to zero, not the StatBlock base defaults.
		stat_mods = StatBlock.from_dict({
			"max_hp": 0, "max_mp": 0, "atk": 0, "def": 0,
			"mat": 0, "mdf": 0, "agi": 0, "luk": 0,
		})


func to_dict() -> Dictionary:
	return {
		"id": id,
		"equip_name": equip_name,
		"kind": kind,
		"slot": slot,
		"description": description,
		"price": price,
		"stat_mods": stat_mods.to_dict(),
		"note": note,
	}


static func from_dict(d: Dictionary) -> EquipData:
	var e := EquipData.new()
	e.id = int(d.get("id", 0))
	e.equip_name = str(d.get("equip_name", "New Equipment"))
	e.kind = str(d.get("kind", KIND_WEAPON))
	e.slot = str(d.get("slot", ""))
	e.description = str(d.get("description", ""))
	e.price = int(d.get("price", 0))
	e.stat_mods = StatBlock.from_dict(d.get("stat_mods", {}))
	e.note = str(d.get("note", ""))
	return e
