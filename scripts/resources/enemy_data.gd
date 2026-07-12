class_name EnemyData
extends Resource
## A battle enemy. Rewards are deterministic (no drop chances in v1).

@export var id: int = 0
@export var enemy_name: String = "New Enemy"
@export var stats: StatBlock = null
@export var gold_reward: int = 0
## Deterministic drops: [ { "kind": "item"|"equip", "id": 0, "count": 1 } ]
@export var item_rewards: Array = []
@export var note: String = ""


func _init() -> void:
	stats = StatBlock.new()
	item_rewards = []


func to_dict() -> Dictionary:
	return {
		"id": id,
		"enemy_name": enemy_name,
		"stats": stats.to_dict(),
		"gold_reward": gold_reward,
		"item_rewards": item_rewards.duplicate(true),
		"note": note,
	}


static func from_dict(d: Dictionary) -> EnemyData:
	var e := EnemyData.new()
	e.id = int(d.get("id", 0))
	e.enemy_name = str(d.get("enemy_name", "New Enemy"))
	e.stats = StatBlock.from_dict(d.get("stats", {}))
	e.gold_reward = int(d.get("gold_reward", 0))
	var rewards = d.get("item_rewards", [])
	e.item_rewards = (rewards as Array).duplicate(true) if rewards is Array else []
	e.note = str(d.get("note", ""))
	return e
