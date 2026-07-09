class_name StatBlock
extends Resource
## The eight core RPG stats. Shared by actors, classes (base stats) and equipment
## (as bonuses). Flat values for now — per-level growth curves come with the combat phase.

@export var max_hp: int = 100
@export var max_mp: int = 20
@export var atk: int = 10   ## physical attack
@export var def: int = 10   ## physical defence
@export var mat: int = 10   ## magic attack
@export var mdf: int = 10   ## magic defence
@export var agi: int = 10   ## agility / turn order
@export var luk: int = 10   ## luck


func to_dict() -> Dictionary:
	return {
		"max_hp": max_hp,
		"max_mp": max_mp,
		"atk": atk,
		"def": def,
		"mat": mat,
		"mdf": mdf,
		"agi": agi,
		"luk": luk,
	}


static func from_dict(d: Dictionary) -> StatBlock:
	var s := StatBlock.new()
	s.max_hp = int(d.get("max_hp", 100))
	s.max_mp = int(d.get("max_mp", 20))
	s.atk = int(d.get("atk", 10))
	s.def = int(d.get("def", 10))
	s.mat = int(d.get("mat", 10))
	s.mdf = int(d.get("mdf", 10))
	s.agi = int(d.get("agi", 10))
	s.luk = int(d.get("luk", 10))
	return s


## Field metadata for building editor UIs and iterating stats generically.
## Each entry: { "key": String, "label": String }.
const FIELDS: Array = [
	{ "key": "max_hp", "label": "Max HP" },
	{ "key": "max_mp", "label": "Max MP" },
	{ "key": "atk", "label": "Attack" },
	{ "key": "def", "label": "Defence" },
	{ "key": "mat", "label": "M.Attack" },
	{ "key": "mdf", "label": "M.Defence" },
	{ "key": "agi", "label": "Agility" },
	{ "key": "luk", "label": "Luck" },
]
