class_name DialogueBox
extends CanvasLayer
## Runtime dialogue box. Displays text and choices, emits signals when done.

var _root: Control
var _text_label: RichTextLabel
var _name_label: Label
var _panel: PanelContainer
var _choices_container: VBoxContainer
var _is_showing: bool = false
var _choice_cancel_index: int = -1


func _ready() -> void:
	layer = 10
	_build_ui()
	_sync_layout()
	_panel.hide()
	SignalBus.dialogue_requested.connect(_on_dialogue_requested)
	SignalBus.choices_requested.connect(_on_choices_requested)
	get_viewport().size_changed.connect(_sync_layout)


func _build_ui() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = DesignTokens.COLOR_BG_SURFACE
	style.border_color = DesignTokens.COLOR_BORDER
	style.border_width_bottom = 1
	style.border_width_top = 1
	style.border_width_left = 1
	style.border_width_right = 1
	style.corner_radius_top_left = int(DesignTokens.RADIUS_MD)
	style.corner_radius_top_right = int(DesignTokens.RADIUS_MD)
	style.corner_radius_bottom_left = int(DesignTokens.RADIUS_MD)
	style.corner_radius_bottom_right = int(DesignTokens.RADIUS_MD)
	_panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", DesignTokens.SPACE_LG)
	margin.add_theme_constant_override("margin_right", DesignTokens.SPACE_LG)
	margin.add_theme_constant_override("margin_top", DesignTokens.SPACE_MD)
	margin.add_theme_constant_override("margin_bottom", DesignTokens.SPACE_MD)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	margin.add_child(vbox)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", DesignTokens.FONT_SIZE_LABEL)
	_name_label.add_theme_color_override("font_color", DesignTokens.COLOR_ACCENT)
	vbox.add_child(_name_label)

	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.scroll_active = false
	_text_label.fit_content = true
	_text_label.custom_minimum_size = Vector2(0, 60)
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_text_label)

	_choices_container = VBoxContainer.new()
	vbox.add_child(_choices_container)

	_root.add_child(_panel)


func _sync_layout() -> void:
	if _root == null or _panel == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	_root.position = Vector2.ZERO
	_root.size = viewport_size
	var panel_margin := 40.0
	var panel_height := 160.0
	_panel.position = Vector2(panel_margin, viewport_size.y - panel_height - panel_margin)
	_panel.size = Vector2(maxf(320.0, viewport_size.x - panel_margin * 2.0), panel_height)


func _on_dialogue_requested(text: String, speaker: String) -> void:
	print("[DB] dialogue_requested received: '", text, "'")
	_clear_choices()
	_name_label.text = speaker
	_name_label.visible = speaker != ""
	_text_label.text = text
	_panel.show()
	_is_showing = true
	print("[DB] panel visible=", _panel.visible, " is_showing=", _is_showing)


func _on_choices_requested(choices: Array, cancel_index: int) -> void:
	print("[DB] choices_requested received: ", choices)
	_clear_choices()
	_choice_cancel_index = cancel_index
	_name_label.text = ""
	_name_label.visible = false
	_text_label.text = ""
	_panel.show()
	_is_showing = true

	for i in range(choices.size()):
		var btn := Button.new()
		btn.text = str(choices[i])
		btn.pressed.connect(_on_choice_pressed.bind(i))
		_choices_container.add_child(btn)


func _on_choice_pressed(index: int) -> void:
	_close_dialogue()
	SignalBus.choice_made.emit(index)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_showing:
		return
	if _choices_container.get_child_count() > 0:
		if event.is_action_pressed("ui_cancel") and _choice_cancel_index >= 0:
			_close_dialogue()
			SignalBus.choice_made.emit(_choice_cancel_index)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_accept"):
		_close_dialogue()
		SignalBus.dialogue_finished.emit()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_close_dialogue()
		SignalBus.dialogue_finished.emit()
		get_viewport().set_input_as_handled()


func _close_dialogue() -> void:
	_clear_choices()
	_choice_cancel_index = -1
	_panel.hide()
	_is_showing = false


func _clear_choices() -> void:
	for child in _choices_container.get_children():
		child.queue_free()
