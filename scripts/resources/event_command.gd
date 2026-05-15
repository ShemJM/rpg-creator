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
## FADE_OUT: { "speed": 1.0 }
## FADE_IN: { "speed": 1.0 }
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
