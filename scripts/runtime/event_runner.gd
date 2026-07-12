class_name EventRunner
extends Node
## Interprets an event's command list at runtime. Pauses for dialogue, choices, waits.
## Emits structured trace signals for every command so agents can observe execution.

signal finished()

## Execution is a stack of frames so nested blocks compose correctly. Each
## frame is { "commands": Array, "index": int, "kind": String } where kind is
## "root" (the event page), "branch" (a conditional / battle-result block),
## "loop" (repeats its body until BREAK_LOOP), or "call" (a common event).
## The top frame is the one currently executing; when it runs off its end it
## either repeats (loop) or pops back to its parent (everything else).
const MAX_FRAME_DEPTH: int = 64  # Guards against runaway common-event recursion.

var _frames: Array = []
var _waiting: bool = false
var _event: EventData = null
var _stopped: bool = false


## Abort execution. Pending one-shot signal handlers become no-ops.
func stop() -> void:
	_stopped = true


func run_event(event: EventData) -> void:
	_event = event
	var page: EventPage = event.get_active_page()
	if page == null:
		finished.emit()
		return
	_frames = [_make_frame(page.commands, "root")]
	_waiting = false
	_stopped = false
	var map_id: int = -1
	for map in ProjectState.maps:
		if map.events.has(event):
			map_id = map.id
			break
	SignalBus.trace_event_started.emit(event.event_name, event.id, map_id)
	_execute_next()


## Run a raw command list (used for global common events — no owning event).
## context_event, if given, supplies self-switch context.
func run_commands(commands: Array, context_event: EventData = null) -> void:
	_event = context_event
	_frames = [_make_frame(commands, "root")]
	_waiting = false
	_stopped = false
	_execute_next()


func _make_frame(commands: Array, kind: String) -> Dictionary:
	return { "commands": commands, "index": 0, "kind": kind }


## Push a nested block (branch / loop body / common-event call) so it runs to
## completion before the parent frame resumes.
func _push_frame(commands: Array, kind: String) -> void:
	if _frames.size() >= MAX_FRAME_DEPTH:
		push_error("[ER] Max nesting depth reached (%d) — skipping %s block (recursion?)." % [MAX_FRAME_DEPTH, kind])
		return
	_frames.append(_make_frame(commands, kind))


func _execute_next() -> void:
	if _stopped:
		return
	while not _frames.is_empty():
		var frame: Dictionary = _frames[_frames.size() - 1]
		if frame["index"] >= frame["commands"].size():
			if frame["kind"] == "loop":
				# Repeat the body. Defer so a tight loop yields a frame instead
				# of recursing the call stack.
				frame["index"] = 0
				_execute_next.call_deferred()
				return
			_frames.pop_back()
			if _frames.is_empty():
				SignalBus.trace_event_finished.emit(_event.event_name if _event else "", _event.id if _event else -1)
				finished.emit()
				return
			continue  # Resume the parent frame (its index already advanced).
		var cmd: EventCommand = frame["commands"][frame["index"]]
		frame["index"] += 1
		_execute_command(cmd)
		return


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
			_cmd_fade(cmd.params, "out")
		EventCommand.Type.FADE_IN:
			_cmd_fade(cmd.params, "in")
		EventCommand.Type.ERASE_EVENT:
			_cmd_erase_event()
			_execute_next()
		EventCommand.Type.LABEL:
			_execute_next()  # Labels are jump targets only.
		EventCommand.Type.JUMP_TO_LABEL:
			_cmd_jump_to_label(cmd.params)
		EventCommand.Type.GAME_OVER:
			_cmd_game_over()
		EventCommand.Type.MOVE_ROUTE:
			_cmd_move_route(cmd.params)
		EventCommand.Type.CHANGE_GOLD:
			GameState.change_gold(str(cmd.params.get("op", "add")), int(cmd.params.get("value", 0)))
			_execute_next()
		EventCommand.Type.CHANGE_ITEMS:
			GameState.change_stock(
				str(cmd.params.get("kind", "item")),
				int(cmd.params.get("id", 0)),
				str(cmd.params.get("op", "add")),
				int(cmd.params.get("count", 1))
			)
			_execute_next()
		EventCommand.Type.CHANGE_HP:
			_cmd_change_hp(cmd.params)
		EventCommand.Type.CHANGE_EQUIPMENT:
			GameState.equip(
				int(cmd.params.get("actor_id", 0)),
				str(cmd.params.get("slot", "weapon")),
				int(cmd.params.get("equip_id", -1))
			)
			_execute_next()
		EventCommand.Type.USE_ITEM:
			GameState.use_item(int(cmd.params.get("item_id", 0)), int(cmd.params.get("actor_id", 0)))
			_execute_next()
		EventCommand.Type.SHOP_PROCESSING:
			_cmd_shop_processing(cmd.params)
		EventCommand.Type.BATTLE_PROCESSING:
			_cmd_battle_processing(cmd.params)
		EventCommand.Type.CALL_COMMON_EVENT:
			_cmd_call_common_event(cmd.params)
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


func _cmd_shop_processing(params: Dictionary) -> void:
	var entries: Array = params.get("entries", [])
	_waiting = true
	# ShopUI owns the session (buy/sell/close, scripted or clicked) and emits
	# shop_finished when it closes — the dialogue wait/resume pattern.
	SignalBus.shop_finished.connect(_on_shop_finished, CONNECT_ONE_SHOT)
	SignalBus.shop_requested.emit(entries)


func _on_shop_finished() -> void:
	_waiting = false
	_execute_next()


func _cmd_battle_processing(params: Dictionary) -> void:
	var enemy_ids: Array = params.get("enemies", [])
	var can_flee: bool = bool(params.get("can_flee", true))
	_waiting = true
	SignalBus.battle_finished.connect(_on_battle_finished.bind(params), CONNECT_ONE_SHOT)
	SignalBus.battle_requested.emit(enemy_ids, can_flee)


func _on_battle_finished(result: String, params: Dictionary) -> void:
	_waiting = false
	var branch: Array = []
	match result:
		"win":
			branch = params.get("commands_win", [])
		"lose":
			branch = params.get("commands_lose", [])
			if branch.is_empty():
				# RPG Maker convention: a lost battle without a lose branch
				# ends the game.
				_cmd_game_over()
				return
	# "flee" (or an empty win branch) just continues past the command.
	if branch.size() > 0:
		_push_frame(branch, "branch")
	_execute_next()


func _cmd_call_common_event(params: Dictionary) -> void:
	var id: int = int(params.get("id", -1))
	var ce := ProjectState.get_common_event_by_id(id)
	if ce == null:
		push_warning("[ER] CALL_COMMON_EVENT: no common event with id %d" % id)
		_execute_next()
		return
	SignalBus.trace_common_event_called.emit(id)
	# Run inline as a nested frame (the depth guard in _push_frame stops
	# runaway recursion). If the guard rejects it, execution simply continues.
	_push_frame(ce.commands, "call")
	_execute_next()


func _cmd_change_hp(params: Dictionary) -> void:
	var allow_ko: bool = bool(params.get("allow_ko", false))
	GameState.change_hp(
		int(params.get("actor_id", -1)),
		str(params.get("op", "sub")),
		int(params.get("value", 0)),
		allow_ko
	)
	if allow_ko and GameState.is_party_defeated():
		_cmd_game_over()
		return
	_execute_next()


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
		"gold_gte":
			condition_met = GameState.gold >= int(value)
		"has_item":
			var kind: String = str(params.get("kind", "item"))
			var min_count: int = int(value) if (value is int or value is float) else 1
			condition_met = GameState.get_stock(kind, id) >= min_count

	var branch_cmds: Array
	if condition_met:
		branch_cmds = params.get("commands_if", [])
	else:
		branch_cmds = params.get("commands_else", [])

	# Run the chosen branch as a nested frame, then resume the parent.
	if branch_cmds.size() > 0:
		_push_frame(branch_cmds, "branch")
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
		SignalBus.trace_self_switch_changed.emit(_event.id, letter, value)


func _cmd_wait(params: Dictionary) -> void:
	var frames: int = params.get("frames", 60)
	var seconds: float = frames / 60.0
	_waiting = true
	get_tree().create_timer(seconds).timeout.connect(func():
		_waiting = false
		_execute_next()
	)


func _cmd_fade(params: Dictionary, direction: String) -> void:
	var duration: float = params.get("duration", 0.5)
	_waiting = true
	SignalBus.fade_finished.connect(func():
		_waiting = false
		_execute_next()
	, CONNECT_ONE_SHOT)
	SignalBus.fade_requested.emit(direction, duration)


func _cmd_erase_event() -> void:
	if _event:
		_event.erased = true
		SignalBus.event_erased.emit(_event.id)


func _cmd_jump_to_label(params: Dictionary) -> void:
	var target: String = params.get("name", "")
	# Search from the current frame outward so a jump inside a branch/loop can
	# target a label in an enclosing block (e.g. a page-level loop label). The
	# frames above the match are abandoned.
	for i in range(_frames.size() - 1, -1, -1):
		var idx := _find_label(_frames[i]["commands"], target)
		if idx >= 0:
			while _frames.size() > i + 1:
				_frames.pop_back()
			_frames[i]["index"] = idx + 1
			# Defer so a backwards jump can't recurse the stack into oblivion;
			# tight loops advance at most once per idle frame.
			_execute_next.call_deferred()
			return
	# No matching label — continue past the jump.
	push_warning("[ER] JUMP_TO_LABEL: no label named '%s'" % target)
	_execute_next()


func _find_label(commands: Array, label_name: String) -> int:
	for i in range(commands.size()):
		var c: EventCommand = commands[i]
		if c.type == EventCommand.Type.LABEL and str(c.params.get("name", "")) == label_name:
			return i
	return -1


func _cmd_game_over() -> void:
	SignalBus.trace_game_over.emit()
	SignalBus.trace_event_finished.emit(_event.event_name if _event else "", _event.id if _event else -1)
	finished.emit()
	SignalBus.game_over_requested.emit()


func _cmd_move_route(params: Dictionary) -> void:
	var target: String = params.get("target", "player")
	var steps: Array = params.get("steps", [])
	var wait_for_completion: bool = params.get("wait_for_completion", true)
	var event_id: int = _event.id if _event else -1
	if wait_for_completion:
		_waiting = true
		SignalBus.move_route_finished.connect(func():
			_waiting = false
			_execute_next()
		, CONNECT_ONE_SHOT)
		SignalBus.move_route_requested.emit(event_id, target, steps)
	else:
		SignalBus.move_route_requested.emit(event_id, target, steps)
		_execute_next()
