class_name EventCommand
extends Resource
## A single command in an event's command list. Type + params dictionary.

enum Type {
	SHOW_TEXT,
	SHOW_CHOICES,
	CONTROL_SWITCHES,
	CONTROL_VARIABLES,
	CONDITIONAL_BRANCH,
	TRANSFER_PLAYER,
	SET_SELF_SWITCH,
	WAIT,
	PLAY_SE,
	FADE_OUT,
	FADE_IN,
	ERASE_EVENT,
	LABEL,
	JUMP_TO_LABEL,
	GAME_OVER,
	MOVE_ROUTE,
	# Append-only past this point: legacy project files store integer
	# ordinals, so reordering the entries above would corrupt them on load.
	CHANGE_GOLD,
	CHANGE_ITEMS,
	CHANGE_HP,
	CHANGE_EQUIPMENT,
	USE_ITEM,
	SHOP_PROCESSING,
}

@export var type: Type = Type.SHOW_TEXT
## Params vary by type. See docs below.
## SHOW_TEXT: { "lines": ["..."], "face": "", "name": "" }
## SHOW_CHOICES: { "choices": ["A", "B"], "cancel_index": -1 }
## CONTROL_SWITCHES: { "ids": [0], "value": true }
## CONTROL_VARIABLES: { "ids": [0], "op": "set", "value": 0 }
## CONDITIONAL_BRANCH: { "condition_type": "switch", "id": 0, "value": true,
##                       "commands_if": [EventCommand...], "commands_else": [EventCommand...] }
## TRANSFER_PLAYER: { "map_id": 0, "x": 0, "y": 0 }
## SET_SELF_SWITCH: { "letter": "A", "value": true }
## WAIT: { "frames": 60 }
## PLAY_SE: { "track": "", "volume": 100 }
## FADE_OUT: { "duration": 0.5 }  (seconds)
## FADE_IN: { "duration": 0.5 }   (seconds)
## ERASE_EVENT: {}  — hides this event for the rest of the play-test
## LABEL: { "name": "start" }
## JUMP_TO_LABEL: { "name": "start" }
## GAME_OVER: {}
## MOVE_ROUTE: { "target": "player" | "this",
##               "steps": ["up","down","left","right","wait",
##                         "face_up","face_down","face_left","face_right","turn_toward_player"],
##               "wait_for_completion": true }
##   Movement steps walk one tile; face_* / turn_toward_player only change facing.
## CHANGE_GOLD: { "op": "add"|"sub"|"set", "value": 100 }
## CHANGE_ITEMS: { "kind": "item"|"equip", "id": 0, "op": "add"|"sub"|"set", "count": 1 }
## CHANGE_HP: { "actor_id": -1 (whole party) | actor id, "op": "add"|"sub"|"set",
##              "value": 20, "allow_ko": false } — without allow_ko HP floors at 1;
##   with allow_ko a full party wipe triggers game over.
## CHANGE_EQUIPMENT: { "actor_id": 0, "slot": "weapon"|"head"|"body"|"accessory",
##                     "equip_id": 3 } — -1 unequips; equipping consumes from stock.
## USE_ITEM: { "item_id": 0, "actor_id": 0 } — applies effect {"hp","mp"}; consumables decrement.
## SHOP_PROCESSING: { "entries": [ { "kind": "item"|"equip", "id": 0, "price": 30 } ] }
##   price optional (defaults to the database price); sell price = floor(price / 2).
##   Blocks the event until the shop closes.
@export var params: Dictionary = {}


static func make_show_text(lines: Array[String], speaker_name: String = "") -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = Type.SHOW_TEXT
	cmd.params = { "lines": lines, "name": speaker_name }
	return cmd


static func make_show_choices(choices: Array[String], cancel_index: int = -1) -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = Type.SHOW_CHOICES
	cmd.params = { "choices": choices, "cancel_index": cancel_index }
	return cmd


static func make_control_switches(ids: Array[int], value: bool) -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = Type.CONTROL_SWITCHES
	cmd.params = { "ids": ids, "value": value }
	return cmd


static func make_control_variables(ids: Array[int], op: String, value: int) -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = Type.CONTROL_VARIABLES
	cmd.params = { "ids": ids, "op": op, "value": value }
	return cmd


static func make_conditional_branch(condition_type: String, id: int, value: Variant) -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = Type.CONDITIONAL_BRANCH
	cmd.params = {
		"condition_type": condition_type,
		"id": id,
		"value": value,
		"commands_if": [],
		"commands_else": [],
	}
	return cmd


static func make_transfer_player(map_id: int, x: int, y: int) -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = Type.TRANSFER_PLAYER
	cmd.params = { "map_id": map_id, "x": x, "y": y }
	return cmd


static func make_set_self_switch(letter: String, value: bool) -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = Type.SET_SELF_SWITCH
	cmd.params = { "letter": letter, "value": value }
	return cmd


static func make_wait(frames: int) -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = Type.WAIT
	cmd.params = { "frames": frames }
	return cmd


static func make_fade_out(duration: float = 0.5) -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = Type.FADE_OUT
	cmd.params = { "duration": duration }
	return cmd


static func make_fade_in(duration: float = 0.5) -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = Type.FADE_IN
	cmd.params = { "duration": duration }
	return cmd


static func make_erase_event() -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = Type.ERASE_EVENT
	cmd.params = {}
	return cmd


static func make_label(label_name: String) -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = Type.LABEL
	cmd.params = { "name": label_name }
	return cmd


static func make_jump_to_label(label_name: String) -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = Type.JUMP_TO_LABEL
	cmd.params = { "name": label_name }
	return cmd


static func make_game_over() -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = Type.GAME_OVER
	cmd.params = {}
	return cmd


static func make_move_route(target: String, steps: Array, wait_for_completion: bool = true) -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = Type.MOVE_ROUTE
	cmd.params = { "target": target, "steps": steps, "wait_for_completion": wait_for_completion }
	return cmd


static func make_change_gold(op: String, value: int) -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = Type.CHANGE_GOLD
	cmd.params = { "op": op, "value": value }
	return cmd


static func make_change_items(kind: String, id: int, op: String, count: int) -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = Type.CHANGE_ITEMS
	cmd.params = { "kind": kind, "id": id, "op": op, "count": count }
	return cmd


static func make_change_hp(actor_id: int, op: String, value: int, allow_ko: bool = false) -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = Type.CHANGE_HP
	cmd.params = { "actor_id": actor_id, "op": op, "value": value, "allow_ko": allow_ko }
	return cmd


static func make_change_equipment(actor_id: int, slot: String, equip_id: int) -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = Type.CHANGE_EQUIPMENT
	cmd.params = { "actor_id": actor_id, "slot": slot, "equip_id": equip_id }
	return cmd


static func make_use_item(item_id: int, actor_id: int) -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = Type.USE_ITEM
	cmd.params = { "item_id": item_id, "actor_id": actor_id }
	return cmd


static func make_shop_processing(entries: Array) -> EventCommand:
	var cmd := EventCommand.new()
	cmd.type = Type.SHOP_PROCESSING
	cmd.params = { "entries": entries }
	return cmd
