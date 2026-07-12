class_name BattleManager
extends Node
## Deterministic turn-based battle v1. Zero UI — BattleUI (and the scenario
## runner) observe through SignalBus; scripted and human commands funnel
## into the same submit path.
##
## Rules (also documented in CLAUDE.md — keep in sync):
## - Party members fight with their live GameState HP; battle damage persists.
## - Each round collects one command per living party member, in party order
##   (pending_actor_id is who must act next), then resolves synchronously:
##   combatants sorted by agi desc; ties -> party before enemies, then lower
##   index. Enemy AI: basic attack on the lowest-index living party member.
## - Damage: base = max(1, atk - def / 2) (integer division), then
##   damage = max(1, base * GameState.rng.randi_range(90, 110) / 100).
##   That rng call is the only randomness in a battle.
## - A dead attack target retargets to the first living enemy/member.
## - "flee" succeeds iff can_flee (processed before the round resolves).
## - Win: every enemy's gold_reward and item_rewards are granted.

var active: bool = false
var round_number: int = 0
var can_flee: bool = true
var last_result: String = ""
## Live enemy instances: { "index", "enemy_id", "name", "hp", "max_hp", "stats" }
var enemies: Array = []
var pending_actor_id: int = -1

var _pending_queue: Array = []   # actor_ids still to command this round
var _queued_actions: Array = []  # { "actor_id", "kind", "params" }


func _ready() -> void:
	SignalBus.battle_requested.connect(_on_battle_requested)
	SignalBus.scripted_battle_action.connect(_on_scripted_action)


func _on_battle_requested(enemy_ids: Array, p_can_flee: bool) -> void:
	active = true
	last_result = ""
	round_number = 0
	can_flee = p_can_flee
	enemies = []
	for i in range(enemy_ids.size()):
		var data := ProjectState.get_enemy_by_id(int(enemy_ids[i]))
		if data == null:
			continue
		var stats: Dictionary = data.stats.to_dict()
		enemies.append({
			"index": enemies.size(),
			"enemy_id": data.id,
			"name": data.enemy_name,
			"hp": int(stats.get("max_hp", 1)),
			"max_hp": int(stats.get("max_hp", 1)),
			"stats": stats,
		})
	SignalBus.trace_battle_started.emit(enemy_ids)
	if enemies.is_empty() or GameState.party.is_empty():
		_end("win" if GameState.party.size() > 0 else "lose")
		return
	_begin_round()


func _begin_round() -> void:
	round_number += 1
	SignalBus.trace_battle_round.emit(round_number)
	_queued_actions = []
	_pending_queue = []
	for m in GameState.party:
		if int(m["hp"]) > 0:
			_pending_queue.append(int(m["actor_id"]))
	_advance_pending()


func _advance_pending() -> void:
	if _pending_queue.is_empty():
		pending_actor_id = -1
		_resolve_round()
		return
	pending_actor_id = _pending_queue.pop_front()


func _on_scripted_action(kind: String, params: Dictionary) -> void:
	submit_action(kind, params)


## One command for the currently pending party member (UI buttons and the
## scripted signal both land here).
func submit_action(kind: String, params: Dictionary) -> void:
	if not active or pending_actor_id < 0:
		return
	_queued_actions.append({ "actor_id": pending_actor_id, "kind": kind, "params": params })
	_advance_pending()


func _resolve_round() -> void:
	# Flee first: deterministic — succeeds iff can_flee.
	for qa in _queued_actions:
		if qa["kind"] == "flee":
			if can_flee:
				SignalBus.trace_battle_action.emit("party:%d" % int(qa["actor_id"]), "flee", "", 0, 0)
				_end("flee")
				return
			SignalBus.trace_battle_action.emit("party:%d" % int(qa["actor_id"]), "flee_failed", "", 0, 0)

	# Turn order: agi desc; ties party before enemies, then lower index.
	var order: Array = []
	for i in range(GameState.party.size()):
		var m: Dictionary = GameState.party[i]
		var stats := GameState.get_member_stats(int(m["actor_id"]))
		order.append({ "side": "party", "idx": i, "agi": int(stats.get("agi", 0)) })
	for e in enemies:
		order.append({ "side": "enemy", "idx": int(e["index"]), "agi": int(e["stats"].get("agi", 0)) })
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["agi"] != b["agi"]:
			return a["agi"] > b["agi"]
		if a["side"] != b["side"]:
			return a["side"] == "party"
		return a["idx"] < b["idx"]
	)

	for turn in order:
		if turn["side"] == "party":
			var member: Dictionary = GameState.party[turn["idx"]]
			if int(member["hp"]) <= 0:
				continue
			_take_party_turn(member)
		else:
			var enemy: Dictionary = enemies[turn["idx"]]
			if int(enemy["hp"]) <= 0:
				continue
			_take_enemy_turn(enemy)
		if _all_enemies_dead():
			_end("win")
			return
		if GameState.is_party_defeated():
			_end("lose")
			return

	_begin_round()


func _take_party_turn(member: Dictionary) -> void:
	var actor_id: int = int(member["actor_id"])
	var action: Dictionary = {}
	for qa in _queued_actions:
		if int(qa["actor_id"]) == actor_id:
			action = qa
			break
	var kind: String = str(action.get("kind", "attack"))
	var params: Dictionary = action.get("params", {})

	if kind == "flee":
		return  # Failed flee (can_flee false) wastes the member's turn.

	if kind == "item":
		var item_id: int = int(params.get("item_id", 0))
		var target_actor: int = int(params.get("target_actor_id", actor_id))
		var item := ProjectState.get_item_by_id(item_id)
		var amount: int = int(item.effect.get("hp", 0)) if item else 0
		var ok := GameState.use_item(item_id, target_actor)
		var target_member := GameState.get_member(target_actor)
		SignalBus.trace_battle_action.emit(
			"party:%d" % actor_id, "item" if ok else "item_failed",
			"party:%d" % target_actor, amount if ok else 0,
			int(target_member.get("hp", 0))
		)
		return

	# Default: attack.
	var target_index: int = int(params.get("target", 0))
	var enemy := _living_enemy(target_index)
	if enemy.is_empty():
		return
	var stats := GameState.get_member_stats(actor_id)
	var damage := _damage(int(stats.get("atk", 1)), int(enemy["stats"].get("def", 0)))
	enemy["hp"] = maxi(0, int(enemy["hp"]) - damage)
	SignalBus.trace_battle_action.emit(
		"party:%d" % actor_id, "attack", "enemy:%d" % int(enemy["index"]), damage, int(enemy["hp"])
	)


func _take_enemy_turn(enemy: Dictionary) -> void:
	# AI: basic attack on the lowest-index living party member.
	var target: Dictionary = {}
	for m in GameState.party:
		if int(m["hp"]) > 0:
			target = m
			break
	if target.is_empty():
		return
	var target_id: int = int(target["actor_id"])
	var target_stats := GameState.get_member_stats(target_id)
	var damage := _damage(int(enemy["stats"].get("atk", 1)), int(target_stats.get("def", 0)))
	GameState.change_hp(target_id, "sub", damage, true)
	SignalBus.trace_battle_action.emit(
		"enemy:%d" % int(enemy["index"]), "attack", "party:%d" % target_id,
		damage, int(GameState.get_member(target_id).get("hp", 0))
	)


func _damage(atk: int, def: int) -> int:
	var base: int = maxi(1, atk - def / 2)
	return maxi(1, base * GameState.rng.randi_range(90, 110) / 100)


## The requested enemy if alive, else the first living one ({} if none).
func _living_enemy(preferred_index: int) -> Dictionary:
	if preferred_index >= 0 and preferred_index < enemies.size() and int(enemies[preferred_index]["hp"]) > 0:
		return enemies[preferred_index]
	for e in enemies:
		if int(e["hp"]) > 0:
			return e
	return {}


func _all_enemies_dead() -> bool:
	for e in enemies:
		if int(e["hp"]) > 0:
			return false
	return true


func _end(result: String) -> void:
	var gold_total := 0
	var rewards: Array = []
	if result == "win":
		for e in enemies:
			var data := ProjectState.get_enemy_by_id(int(e["enemy_id"]))
			if data == null:
				continue
			gold_total += data.gold_reward
			for r in data.item_rewards:
				if r is Dictionary:
					rewards.append(r)
					GameState.change_stock(
						str((r as Dictionary).get("kind", "item")),
						int((r as Dictionary).get("id", 0)),
						"add",
						int((r as Dictionary).get("count", 1))
					)
		if gold_total > 0:
			GameState.change_gold("add", gold_total)
	active = false
	pending_actor_id = -1
	last_result = result
	SignalBus.trace_battle_ended.emit(result, gold_total, rewards)
	SignalBus.battle_finished.emit(result)
