extends Node
## Cross-system signal bus for the RPG Creator editor.

# --- Editor ---
signal map_selected(map_index: int)
signal tile_painted(layer: int, coords: Vector2i, tile_id: int)
signal tool_changed(tool_name: String)
signal layer_changed(layer: int)

# --- Play-test ---
signal playtest_requested()
signal playtest_stopped()

# --- Events (editor) ---
signal event_selected(event: EventData)
signal event_placed(event: EventData)
signal event_mode_toggled(active: bool)

# --- Project ---
signal project_loaded(path: String)
signal project_saved(path: String)

# --- Events (runtime) ---
signal dialogue_requested(text: String, speaker: String)
signal choices_requested(choices: Array, cancel_index: int)
signal choice_made(index: int)
signal dialogue_finished()
signal transfer_requested(map_id: int, x: int, y: int)
## direction: "out" fades to black, "in" fades back to the scene.
signal fade_requested(direction: String, duration: float)
signal fade_finished()
## target: "player" or "event" (event_id identifies the event to move).
signal move_route_requested(event_id: int, target: String, steps: Array)
signal move_route_finished()
signal game_over_requested()
signal event_erased(event_id: int)

# --- Party / resources (runtime) ---
signal shop_requested(entries: Array)
signal shop_finished()
signal battle_requested(enemy_ids: Array, can_flee: bool)
signal battle_finished(result: String)

# --- Agent / scripted control ---
## Emit to advance a waiting dialogue without keyboard input.
signal scripted_dialogue_advance()
## Emit to make a choice without keyboard input.
signal scripted_choice_made(index: int)
## Shop session controls (handled by ShopUI while a shop is open).
signal scripted_shop_buy(index: int, count: int)
signal scripted_shop_sell(kind: String, id: int, count: int)
signal scripted_shop_close()
## Battle command for the pending party member (handled by BattleManager).
## kind: "attack" | "item" | "flee"; params vary by kind.
signal scripted_battle_action(kind: String, params: Dictionary)

# --- Runtime trace (structured output for agents / tests) ---
signal trace_event_started(event_name: String, event_id: int, map_id: int)
signal trace_event_finished(event_name: String, event_id: int)
signal trace_command_executed(event_id: int, command_type: String, params: Dictionary)
signal trace_switch_changed(id: int, value: bool)
signal trace_variable_changed(id: int, value: int)
signal trace_self_switch_changed(event_id: int, letter: String, value: bool)
signal trace_game_over()
signal trace_transfer(from_map_id: int, to_map_id: int, x: int, y: int)
signal trace_dialogue(speaker: String, text: String)
signal trace_choice_made(index: int, label: String)
signal trace_player_moved(grid_pos: Vector2i, map_id: int)
signal trace_assertion_failed(message: String)
signal trace_gold_changed(gold: int, delta: int)
## kind: "item" | "equip"; count is the new stock count.
signal trace_item_changed(kind: String, id: int, count: int)
signal trace_hp_changed(actor_id: int, hp: int, max_hp: int)
signal trace_mp_changed(actor_id: int, mp: int, max_mp: int)
## equip_id -1 = slot emptied.
signal trace_equip_changed(actor_id: int, slot: String, equip_id: int)
signal trace_item_used(item_id: int, actor_id: int, ok: bool)
signal trace_shop_opened(entries: Array)
## action: "buy" | "sell"; ok false = rejected (insufficient gold/stock).
signal trace_shop_transaction(action: String, kind: String, id: int, count: int, gold_delta: int, ok: bool)
signal trace_shop_closed()
signal trace_battle_started(enemy_ids: Array)
signal trace_battle_round(round_number: int)
## actor/target encoded "party:<actor_id>" / "enemy:<index>"; amount is damage or heal.
signal trace_battle_action(actor: String, action: String, target: String, amount: int, target_hp_left: int)
signal trace_battle_ended(result: String, gold_reward: int, item_rewards: Array)
signal trace_common_event_called(id: int)
