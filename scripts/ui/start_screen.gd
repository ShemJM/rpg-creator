class_name StartScreen
extends Control
## Launch screen. Choose to create a new project or open an existing one.

var _recent_list: VBoxContainer
var _no_recent_label: Label


func _ready() -> void:
	_build_ui()
	_refresh_recent()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = DesignTokens.COLOR_BG_DARK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", DesignTokens.SPACE_LG)
	margin.add_theme_constant_override("margin_right", DesignTokens.SPACE_LG)
	margin.add_theme_constant_override("margin_top", DesignTokens.SPACE_LG)
	margin.add_theme_constant_override("margin_bottom", DesignTokens.SPACE_LG)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", DesignTokens.SPACE_MD)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "RPG Creator"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", DesignTokens.FONT_SIZE_HERO)
	title.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_BRIGHT)
	vbox.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Godot 4 Edition"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_DIM)
	vbox.add_child(subtitle)

	vbox.add_child(HSeparator.new())

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", DesignTokens.SPACE_SM)
	vbox.add_child(btn_row)

	var new_btn := Button.new()
	new_btn.text = "New Project"
	new_btn.custom_minimum_size = Vector2(150, 44)
	new_btn.pressed.connect(_on_new_pressed)
	btn_row.add_child(new_btn)

	var open_btn := Button.new()
	open_btn.text = "Open Project…"
	open_btn.custom_minimum_size = Vector2(150, 44)
	open_btn.pressed.connect(_on_open_pressed)
	btn_row.add_child(open_btn)

	vbox.add_child(HSeparator.new())

	var recent_label := Label.new()
	recent_label.text = "Recent Projects"
	recent_label.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_DIM)
	vbox.add_child(recent_label)

	_no_recent_label = Label.new()
	_no_recent_label.text = "No recent projects."
	_no_recent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_no_recent_label.add_theme_color_override("font_color", DesignTokens.COLOR_TEXT_DIM)
	vbox.add_child(_no_recent_label)

	_recent_list = VBoxContainer.new()
	_recent_list.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	vbox.add_child(_recent_list)


func _refresh_recent() -> void:
	for child in _recent_list.get_children():
		child.queue_free()
	var recent := ProjectState.get_recent_projects()
	_no_recent_label.visible = recent.is_empty()
	for path: String in recent:
		var btn := Button.new()
		btn.text = "%s   —   %s" % [path.get_file().get_basename(), path]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.clip_text = true
		btn.custom_minimum_size = Vector2(0, 36)
		btn.pressed.connect(_open_recent.bind(path))
		_recent_list.add_child(btn)


func _on_new_pressed() -> void:
	ProjectState.create_new_project()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _on_open_pressed() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray([
		"*.rpgc ; RPG Creator Project",
		"*.rpgm ; Legacy RPG Creator Project",
	])
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_selected.connect(func(path: String) -> void:
		if ProjectState.load_from(path):
			get_tree().change_scene_to_file("res://scenes/Main.tscn")
		else:
			dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


func _open_recent(path: String) -> void:
	if not FileAccess.file_exists(path):
		ProjectState.remove_from_recent(path)
		_refresh_recent()
		return
	if ProjectState.load_from(path):
		get_tree().change_scene_to_file("res://scenes/Main.tscn")
