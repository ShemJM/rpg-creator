class_name EventEditorPanel
extends VBoxContainer
## Editor panel for editing a selected event's pages and commands.

var _event: EventData = null
var _current_page_index: int = 0

@onready var _title_label: Label = $TitleBar/Title
@onready var _page_tabs: HBoxContainer = $TitleBar/PageTabs
@onready var _add_page_btn: Button = $TitleBar/AddPageBtn
@onready var _trigger_option: OptionButton = $PageSettings/TriggerOption
@onready var _condition_switch_spin: SpinBox = $PageSettings/CondSwitchSpin
@onready var _condition_self_switch_opt: OptionButton = $PageSettings/SelfSwitchOpt
@onready var _command_list: VBoxContainer = $CommandScroll/CommandList
@onready var _add_cmd_option: OptionButton = $AddCommandBar/AddCmdOption
@onready var _add_cmd_btn: Button = $AddCommandBar/AddCmdBtn


func _ready() -> void:
	SignalBus.event_selected.connect(_on_event_selected)
	_add_page_btn.pressed.connect(_on_add_page)
	_add_cmd_btn.pressed.connect(_on_add_command)
	_trigger_option.item_selected.connect(_on_trigger_changed)
	_condition_switch_spin.value_changed.connect(_on_condition_switch_changed)
	_condition_self_switch_opt.item_selected.connect(_on_self_switch_changed)
	_build_trigger_options()
	_build_add_cmd_options()
	_build_self_switch_options()


func _build_trigger_options() -> void:
	_trigger_option.clear()
	_trigger_option.add_item("Action Button", 0)
	_trigger_option.add_item("Player Touch", 1)
	_trigger_option.add_item("Autorun", 2)
	_trigger_option.add_item("Parallel", 3)


func _build_add_cmd_options() -> void:
	_add_cmd_option.clear()
	_add_cmd_option.add_item("Show Text", EventCommand.Type.SHOW_TEXT)
	_add_cmd_option.add_item("Show Choices", EventCommand.Type.SHOW_CHOICES)
	_add_cmd_option.add_item("Control Switches", EventCommand.Type.CONTROL_SWITCHES)
	_add_cmd_option.add_item("Control Variables", EventCommand.Type.CONTROL_VARIABLES)
	_add_cmd_option.add_item("Conditional Branch", EventCommand.Type.CONDITIONAL_BRANCH)
	_add_cmd_option.add_item("Transfer Player", EventCommand.Type.TRANSFER_PLAYER)
	_add_cmd_option.add_item("Set Self Switch", EventCommand.Type.SET_SELF_SWITCH)
	_add_cmd_option.add_item("Wait", EventCommand.Type.WAIT)


func _build_self_switch_options() -> void:
	_condition_self_switch_opt.clear()
	_condition_self_switch_opt.add_item("None", 0)
	_condition_self_switch_opt.add_item("A", 1)
	_condition_self_switch_opt.add_item("B", 2)
	_condition_self_switch_opt.add_item("C", 3)
	_condition_self_switch_opt.add_item("D", 4)


func _on_event_selected(event: EventData) -> void:
	_event = event
	_current_page_index = 0
	_refresh()


func _refresh() -> void:
	if _event == null:
		return
	_title_label.text = "Event: %s (id: %d)" % [_event.event_name, _event.id]
	_rebuild_page_tabs()
	_refresh_page()


func _rebuild_page_tabs() -> void:
	for child in _page_tabs.get_children():
		child.queue_free()
	for i in range(_event.pages.size()):
		var btn := Button.new()
		btn.text = "Page %d" % (i + 1)
		btn.toggle_mode = true
		btn.button_pressed = (i == _current_page_index)
		btn.pressed.connect(_on_page_tab_pressed.bind(i))
		_page_tabs.add_child(btn)


func _on_page_tab_pressed(index: int) -> void:
	_current_page_index = index
	_refresh_page()
	_rebuild_page_tabs()


func _refresh_page() -> void:
	if _event == null or _current_page_index >= _event.pages.size():
		return
	var page: EventPage = _event.pages[_current_page_index]
	_trigger_option.selected = page.trigger
	_condition_switch_spin.value = page.condition_switch_id
	# Self-switch.
	match page.condition_self_switch:
		"A": _condition_self_switch_opt.selected = 1
		"B": _condition_self_switch_opt.selected = 2
		"C": _condition_self_switch_opt.selected = 3
		"D": _condition_self_switch_opt.selected = 4
		_: _condition_self_switch_opt.selected = 0
	_rebuild_command_list(page)


func _rebuild_command_list(page: EventPage) -> void:
	for child in _command_list.get_children():
		child.queue_free()
	for i in range(page.commands.size()):
		var cmd: EventCommand = page.commands[i]
		var row := _make_command_row(cmd, i)
		_command_list.add_child(row)


func _make_command_row(cmd: EventCommand, index: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = _command_summary(cmd)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var edit_btn := Button.new()
	edit_btn.text = "Edit"
	edit_btn.pressed.connect(_on_edit_command.bind(index))
	row.add_child(edit_btn)

	var del_btn := Button.new()
	del_btn.text = "X"
	del_btn.pressed.connect(_on_delete_command.bind(index))
	row.add_child(del_btn)

	return row


func _command_summary(cmd: EventCommand) -> String:
	match cmd.type:
		EventCommand.Type.SHOW_TEXT:
			var lines: Array = cmd.params.get("lines", [])
			var preview: String = lines[0] if lines.size() > 0 else "(empty)"
			if preview.length() > 40:
				preview = preview.substr(0, 37) + "..."
			return "Text: \"%s\"" % preview
		EventCommand.Type.SHOW_CHOICES:
			var choices: Array = cmd.params.get("choices", [])
			return "Choices: %s" % str(choices)
		EventCommand.Type.CONTROL_SWITCHES:
			return "Switch %s = %s" % [str(cmd.params.get("ids", [])), str(cmd.params.get("value", true))]
		EventCommand.Type.CONTROL_VARIABLES:
			return "Var %s %s %d" % [str(cmd.params.get("ids", [])), cmd.params.get("op", "set"), cmd.params.get("value", 0)]
		EventCommand.Type.CONDITIONAL_BRANCH:
			return "If %s[%d] == %s" % [cmd.params.get("condition_type", ""), cmd.params.get("id", 0), str(cmd.params.get("value", ""))]
		EventCommand.Type.TRANSFER_PLAYER:
			return "Transfer → Map %d (%d, %d)" % [cmd.params.get("map_id", 0), cmd.params.get("x", 0), cmd.params.get("y", 0)]
		EventCommand.Type.SET_SELF_SWITCH:
			return "Self Switch %s = %s" % [cmd.params.get("letter", "A"), str(cmd.params.get("value", true))]
		EventCommand.Type.WAIT:
			return "Wait %d frames" % cmd.params.get("frames", 60)
		_:
			return "Unknown"


func _on_add_page() -> void:
	if _event == null:
		return
	var page := EventPage.new()
	_event.pages.append(page)
	_current_page_index = _event.pages.size() - 1
	_refresh()


func _on_trigger_changed(idx: int) -> void:
	if _event == null or _current_page_index >= _event.pages.size():
		return
	_event.pages[_current_page_index].trigger = idx as EventPage.Trigger


func _on_condition_switch_changed(value: float) -> void:
	if _event == null or _current_page_index >= _event.pages.size():
		return
	_event.pages[_current_page_index].condition_switch_id = int(value)


func _on_self_switch_changed(idx: int) -> void:
	if _event == null or _current_page_index >= _event.pages.size():
		return
	var letters := ["", "A", "B", "C", "D"]
	_event.pages[_current_page_index].condition_self_switch = letters[idx]


func _on_add_command() -> void:
	if _event == null or _current_page_index >= _event.pages.size():
		return
	var page: EventPage = _event.pages[_current_page_index]
	var cmd_type: int = _add_cmd_option.get_item_id(_add_cmd_option.selected)
	var cmd := _create_default_command(cmd_type)
	page.commands.append(cmd)
	_rebuild_command_list(page)


func _create_default_command(cmd_type: int) -> EventCommand:
	match cmd_type:
		EventCommand.Type.SHOW_TEXT:
			return EventCommand.make_show_text(["Hello!"] as Array[String])
		EventCommand.Type.SHOW_CHOICES:
			return EventCommand.make_show_choices(["Yes", "No"] as Array[String])
		EventCommand.Type.CONTROL_SWITCHES:
			return EventCommand.make_control_switches([0] as Array[int], true)
		EventCommand.Type.CONTROL_VARIABLES:
			return EventCommand.make_control_variables([0] as Array[int], "add", 1)
		EventCommand.Type.CONDITIONAL_BRANCH:
			return EventCommand.make_conditional_branch("switch", 0, true)
		EventCommand.Type.TRANSFER_PLAYER:
			return EventCommand.make_transfer_player(0, 5, 5)
		EventCommand.Type.SET_SELF_SWITCH:
			return EventCommand.make_set_self_switch("A", true)
		EventCommand.Type.WAIT:
			return EventCommand.make_wait(60)
		_:
			return EventCommand.make_wait(60)


func _on_edit_command(index: int) -> void:
	if _event == null or _current_page_index >= _event.pages.size():
		return
	var page: EventPage = _event.pages[_current_page_index]
	if index >= page.commands.size():
		return
	var cmd: EventCommand = page.commands[index]
	# Open inline edit popup for this command type.
	_open_command_edit_popup(cmd, index)


func _on_delete_command(index: int) -> void:
	if _event == null or _current_page_index >= _event.pages.size():
		return
	var page: EventPage = _event.pages[_current_page_index]
	if index < page.commands.size():
		page.commands.remove_at(index)
		_rebuild_command_list(page)


func _open_command_edit_popup(cmd: EventCommand, index: int) -> void:
	# For MVP: inline editing via a simple popup window.
	var popup := Window.new()
	popup.title = "Edit Command"
	popup.size = Vector2i(400, 300)
	popup.transient = true
	popup.exclusive = true

	var vbox := VBoxContainer.new()
	vbox.anchors_preset = Control.PRESET_FULL_RECT
	vbox.offset_left = 10
	vbox.offset_right = -10
	vbox.offset_top = 10
	vbox.offset_bottom = -10
	popup.add_child(vbox)

	match cmd.type:
		EventCommand.Type.SHOW_TEXT:
			_build_text_edit_ui(vbox, cmd)
		EventCommand.Type.SHOW_CHOICES:
			_build_choices_edit_ui(vbox, cmd)
		EventCommand.Type.CONTROL_SWITCHES:
			_build_switch_edit_ui(vbox, cmd)
		EventCommand.Type.TRANSFER_PLAYER:
			_build_transfer_edit_ui(vbox, cmd)
		EventCommand.Type.WAIT:
			_build_wait_edit_ui(vbox, cmd)
		_:
			var lbl := Label.new()
			lbl.text = "Edit not yet implemented for this type."
			vbox.add_child(lbl)

	var close_btn := Button.new()
	close_btn.text = "Done"
	close_btn.pressed.connect(func():
		popup.queue_free()
		_refresh_page()
	)
	vbox.add_child(close_btn)

	add_child(popup)
	popup.popup_centered()


func _build_text_edit_ui(container: VBoxContainer, cmd: EventCommand) -> void:
	var lbl := Label.new()
	lbl.text = "Speaker Name:"
	container.add_child(lbl)
	var name_edit := LineEdit.new()
	name_edit.text = cmd.params.get("name", "")
	name_edit.text_changed.connect(func(t: String): cmd.params["name"] = t)
	container.add_child(name_edit)

	var lbl2 := Label.new()
	lbl2.text = "Text (one line per entry, use Shift+Enter for multi-line):"
	container.add_child(lbl2)
	var text_edit := TextEdit.new()
	text_edit.custom_minimum_size = Vector2(0, 120)
	var lines: Array = cmd.params.get("lines", [])
	text_edit.text = "\n".join(lines)
	text_edit.text_changed.connect(func():
		cmd.params["lines"] = text_edit.text.split("\n")
	)
	container.add_child(text_edit)


func _build_choices_edit_ui(container: VBoxContainer, cmd: EventCommand) -> void:
	var lbl := Label.new()
	lbl.text = "Choices (one per line):"
	container.add_child(lbl)
	var text_edit := TextEdit.new()
	text_edit.custom_minimum_size = Vector2(0, 120)
	var choices: Array = cmd.params.get("choices", [])
	text_edit.text = "\n".join(choices)
	text_edit.text_changed.connect(func():
		cmd.params["choices"] = text_edit.text.split("\n")
	)
	container.add_child(text_edit)


func _build_switch_edit_ui(container: VBoxContainer, cmd: EventCommand) -> void:
	var lbl := Label.new()
	lbl.text = "Switch ID:"
	container.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 99
	var ids: Array = cmd.params.get("ids", [0])
	spin.value = ids[0] if ids.size() > 0 else 0
	spin.value_changed.connect(func(v: float): cmd.params["ids"] = [int(v)])
	container.add_child(spin)

	var check := CheckBox.new()
	check.text = "ON"
	check.button_pressed = cmd.params.get("value", true)
	check.toggled.connect(func(v: bool): cmd.params["value"] = v)
	container.add_child(check)


func _build_transfer_edit_ui(container: VBoxContainer, cmd: EventCommand) -> void:
	var lbl := Label.new()
	lbl.text = "Map ID:"
	container.add_child(lbl)
	var map_spin := SpinBox.new()
	map_spin.min_value = 0
	map_spin.max_value = 99
	map_spin.value = cmd.params.get("map_id", 0)
	map_spin.value_changed.connect(func(v: float): cmd.params["map_id"] = int(v))
	container.add_child(map_spin)

	var xy_box := HBoxContainer.new()
	container.add_child(xy_box)
	var x_spin := SpinBox.new()
	x_spin.prefix = "X:"
	x_spin.min_value = 0
	x_spin.max_value = 99
	x_spin.value = cmd.params.get("x", 0)
	x_spin.value_changed.connect(func(v: float): cmd.params["x"] = int(v))
	xy_box.add_child(x_spin)

	var y_spin := SpinBox.new()
	y_spin.prefix = "Y:"
	y_spin.min_value = 0
	y_spin.max_value = 99
	y_spin.value = cmd.params.get("y", 0)
	y_spin.value_changed.connect(func(v: float): cmd.params["y"] = int(v))
	xy_box.add_child(y_spin)


func _build_wait_edit_ui(container: VBoxContainer, cmd: EventCommand) -> void:
	var lbl := Label.new()
	lbl.text = "Frames (60 = 1 second):"
	container.add_child(lbl)
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = 600
	spin.value = cmd.params.get("frames", 60)
	spin.value_changed.connect(func(v: float): cmd.params["frames"] = int(v))
	container.add_child(spin)
