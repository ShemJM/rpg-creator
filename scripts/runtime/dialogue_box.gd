class_name DialogueBox
extends CanvasLayer
## Runtime dialogue box. Displays text and choices, emits signals when done.

var _text_label: RichTextLabel
var _name_label: Label
var _panel: PanelContainer
var _choices_container: VBoxContainer
var _is_showing: bool = false


func _ready() -> void:
	layer = 10
	_build_ui()
	_panel.hide()
	SignalBus.dialogue_requested.connect(_on_dialogue_requested)
	SignalBus.choices_requested.connect(_on_choices_requested)


func _build_ui() -> void:
	# Full-screen Control anchor so children can position relative to viewport.
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Panel at bottom of screen.
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_top = -160.0
	_panel.offset_bottom = 0.0
	_panel.offset_left = 40.0
	_panel.offset_right = -40.0

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
	_text_label.fit_content = true
	_text_label.custom_minimum_size = Vector2(0, 60)
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_text_label)

	_choices_container = VBoxContainer.new()
	vbox.add_child(_choices_container)

	root.add_child(_panel)


func _on_dialogue_requested(text: String, speaker: String) -> void:
	print("[DB] dialogue_requested received: '", text, "'")
	_clear_choices()
	_name_label.text = speaker
	_name_label.visible = speaker != ""
	_text_label.text = text
	_panel.show()
	_is_showing = true
	print("[DB] panel visible=", _panel.visible, " is_showing=", _is_showing)


func _on_choices_requested(choices: Array) -> void:
	print("[DB] choices_requested received: ", choices)
	_clear_choices()
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
	_clear_choices()
	_panel.hide()
	_is_showing = false
	SignalBus.choice_made.emit(index)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_showing:
		return
	if _choices_container.get_child_count() > 0:
		return  # Waiting for choice selection, not key press.
	if event.is_action_pressed("ui_accept"):
		_panel.hide()
		_is_showing = false
		SignalBus.dialogue_finished.emit()
		get_viewport().set_input_as_handled()


func _clear_choices() -> void:
	for child in _choices_container.get_children():
		child.queue_free()
