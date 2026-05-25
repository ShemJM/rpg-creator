class_name EventRunner
extends Node
## Interprets an event's command list at runtime. Pauses for dialogue, choices, waits.
## Emits structured trace signals for every command so agents can observe execution.

signal finished()

var _commands: Array = []
var _index: int = 0
var _waiting: bool = false
var _event: EventData = null


func run_event(event: EventData) -> void:
	_event = event
	var page: EventPage = event.get_active_page()
	if page == null:
		finished.emit()
		return
	_commands = page.commands
	_index = 0
	_waiting = false
	var map_id: int = -1
	for map in ProjectState.maps:
		if map.events.has(event):
			map_id = map.id
			break
	SignalBus.trace_event_started.emit(event.event_name, event.id, map_id)
	_execute_next()


func _execute_next() -> void:
	if _index >= _commands.size():
		SignalBus.trace_event_finished.emit(_event.event_name if _event else "", _event.id if _event else -1)
		finished.emit()
		return
	var cmd: EventCommand = _commands[_index]
	_index += 1
	_execute_command(cmd)


func _execute_command(cmd: EventCommand) -> void:
	var type_name: String = EventCommand.Type.keys()[cmd.type]
	SignalBus.trace_command_executed.emit(_event.id if _event else -1, type_name, cmd.params)
	match cmd.type:
		EventCommand.Type.SHOW_TEXT:
			_cmd_show_text(cmd.params)
		EventCommand.Type.SHOW_CHOICES:
			_cmd_show_choices(cmd.params)
		EventCommand.Type.CONTROL_SWITCHES:
			_cmd_control_switches(cmd.params)
			_execute_next()
		EventCommand.Type.CONTROL_VARIABLES:
			_cmd_control_variables(cmd.params)
			_execute_next()
		EventCommand.Type.CONDITIONAL_BRANCH:
			_cmd_conditional_branch(cmd.params)
		EventCommand.Type.TRANSFER_PLAYER:
			_cmd_transfer_player(cmd.params)
		EventCommand.Type.SET_SELF_SWITCH:
			_cmd_set_self_switch(cmd.params)
			_execute_next()
		EventCommand.Type.WAIT:
			_cmd_wait(cmd.params)
		EventCommand.Type.FADE_OUT:
			_execute_next()  # Stub — no visual yet.
		EventCommand.Type.FADE_IN:
			_execute_next()
		_:
			_execute_next()


# --- Command implementations ---

func _cmd_show_text(params: Dictionary) -> void:
	var lines: Array = params.get("lines", [])
	var speaker: String = params.get("name", "")
	var full_text: String = "\n".join(lines)
	print("[ER] show_text: '", full_text, "' speaker='", speaker, "'")
	SignalBus.trace_dialogue.emit(speaker, full_text)
	_waiting = true
	SignalBus.dialogue_requested.emit(full_text, speaker)
	# Wait for dialogue to finish — from UI or from scripted advance.
	SignalBus.dialogue_finished.connect(_on_dialogue_done, CONNECT_ONE_SHOT)
	SignalBus.scripted_dialogue_advance.connect(_on_scripted_dialogue_advance, CONNECT_ONE_SHOT)


func _cmd_show_choices(params: Dictionary) -> void:
	var choices: Array = params.get("choices", [])
	var cancel_index: int = int(params.get("cancel_index", -1))
	print("[ER] show_choices: ", choices)
	_waiting = true
	SignalBus.choices_requested.emit(choices, cancel_index)
	SignalBus.choice_made.connect(_on_choice_made, CONNECT_ONE_SHOT)
	SignalBus.scripted_choice_made.connect(_on_scripted_choice, CONNECT_ONE_SHOT)


func _on_dialogue_done() -> void:
	_waiting = false
	# Disconnect scripted advance if it wasn't consumed.
	if SignalBus.scripted_dialogue_advance.is_connected(_on_scripted_dialogue_advance):
		SignalBus.scripted_dialogue_advance.disconnect(_on_scripted_dialogue_advance)
	_execute_next()


func _on_scripted_dialogue_advance() -> void:
	# Disconnect UI handler since we're advancing programmatically.
	if SignalBus.dialogue_finished.is_connected(_on_dialogue_done):
		SignalBus.dialogue_finished.disconnect(_on_dialogue_done)
	_waiting = false
	# Dismiss the visible dialogue box too.
	SignalBus.dialogue_finished.emit()
	_execute_next()


func _on_choice_made(_index: int) -> void:
	_waiting = false
	# Disconnect scripted choice handler if not consumed.
	if SignalBus.scripted_choice_made.is_connected(_on_scripted_choice):
		SignalBus.scripted_choice_made.disconnect(_on_scripted_choice)
	# Choice result stored in variable 0 for conditional access.
	GameState.set_variable(0, _index)
	_execute_next()


func _on_scripted_choice(index: int) -> void:
	# Disconnect UI handler since we're choosing programmatically.
	if SignalBus.choice_made.is_connected(_on_choice_made):
		SignalBus.choice_made.disconnect(_on_choice_made)
	_waiting = false
	GameState.set_variable(0, index)
	SignalBus.choice_made.emit(index)  # Let dialogue box close itself.
	_execute_next()


func _cmd_control_switches(params: Dictionary) -> void:
	var ids: Array = params.get("ids", [])
	var value: bool = params.get("value", true)
	for id: int in ids:
		GameState.set_switch(id, value)
		SignalBus.trace_switch_changed.emit(id, value)


func _cmd_control_variables(params: Dictionary) -> void:
	var ids: Array = params.get("ids", [])
	var op: String = params.get("op", "set")
	var value: int = params.get("value", 0)
	for id: int in ids:
		GameState.modify_variable(id, op, value)
		SignalBus.trace_variable_changed.emit(id, GameState.get_variable(id))


func _cmd_conditional_branch(params: Dictionary) -> void:
	var condition_met := false
	var ctype: String = params.get("condition_type", "switch")
	var id: int = params.get("id", 0)
	var value: Variant = params.get("value", true)

	match ctype:
		"switch":
			condition_met = GameState.get_switch(id) == value
		"variable_gte":
			condition_met = GameState.get_variable(id) >= int(value)
		"self_switch":
			var letter: String = str(value)
			condition_met = _event.self_switches.get(letter, false)

	var branch_cmds: Array
	if condition_met:
		branch_cmds = params.get("commands_if", [])
	else:
		branch_cmds = params.get("commands_else", [])

	# Execute the branch inline, then continue with the rest.
	if branch_cmds.size() > 0:
		var remaining := _commands.slice(_index)
		_commands = branch_cmds + remaining
		_index = 0
	_execute_next()


func _cmd_transfer_player(params: Dictionary) -> void:
	var map_id: int = params.get("map_id", 0)
	var x: int = params.get("x", 0)
	var y: int = params.get("y", 0)
	var from_id: int = -1
	if _event:
		for map in ProjectState.maps:
			if map.events.has(_event):
				from_id = map.id
				break
	SignalBus.trace_transfer.emit(from_id, map_id, x, y)
	SignalBus.transfer_requested.emit(map_id, x, y)
	_execute_next()


func _cmd_set_self_switch(params: Dictionary) -> void:
	var letter: String = params.get("letter", "A")
	var value: bool = params.get("value", true)
	if _event:
		_event.self_switches[letter] = value


func _cmd_wait(params: Dictionary) -> void:
	var frames: int = params.get("frames", 60)
	var seconds: float = frames / 60.0
	_waiting = true
	get_tree().create_timer(seconds).timeout.connect(func():
		_waiting = false
		_execute_next()
	)
