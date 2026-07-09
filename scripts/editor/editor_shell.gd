class_name EditorShell
extends MarginContainer
## Main editor navigation shell. Manages switching between editor panels.

var _map_editor: Control = null
var _database_panel: Control = null
var _runtime_player: Node = null

@onready var _nav_bar: VBoxContainer = $HSplit/NavPanel/VBox/NavBar
@onready var _maps_btn: Button = $HSplit/NavPanel/VBox/NavBar/Maps
@onready var _database_btn: Button = $HSplit/NavPanel/VBox/NavBar/Database
@onready var _content_area: Control = $HSplit/ContentArea
@onready var _playtest_btn: Button = $HSplit/NavPanel/VBox/PlayTestButton
@onready var _project_label: Label = $HSplit/NavPanel/VBox/ProjectLabel
@onready var _save_btn: Button = $HSplit/NavPanel/VBox/SaveBtn
@onready var _save_as_btn: Button = $HSplit/NavPanel/VBox/SaveAsBtn
@onready var _close_btn: Button = $HSplit/NavPanel/VBox/CloseBtn


func _ready() -> void:
	SignalBus.playtest_stopped.connect(_on_playtest_stopped)
	SignalBus.project_saved.connect(_on_project_saved)
	_playtest_btn.pressed.connect(_on_playtest_pressed)
	_save_btn.pressed.connect(_on_save_pressed)
	_save_as_btn.pressed.connect(_on_save_as_pressed)
	_close_btn.pressed.connect(_on_close_pressed)
	# Nav: exclusive toggle between the Maps and Database panels.
	var nav_group := ButtonGroup.new()
	_maps_btn.toggle_mode = true
	_maps_btn.button_group = nav_group
	_database_btn.toggle_mode = true
	_database_btn.button_group = nav_group
	_maps_btn.pressed.connect(func() -> void: _show_panel("maps"))
	_database_btn.pressed.connect(func() -> void: _show_panel("database"))
	_update_project_label()
	# Open map editor by default.
	_show_panel("maps")


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_S and event.ctrl_pressed:
			_on_save_pressed()
			accept_event()


func _update_project_label() -> void:
	var path := ProjectState.current_project_path
	if path.is_empty():
		_project_label.text = "Untitled"
	else:
		_project_label.text = path.get_file().get_basename()


func _show_panel(which: String) -> void:
	if _map_editor == null:
		_map_editor = (load("res://scenes/editor/MapEditor.tscn") as PackedScene).instantiate()
		_content_area.add_child(_map_editor)
	if _database_panel == null:
		_database_panel = (load("res://scenes/editor/DatabasePanel.tscn") as PackedScene).instantiate()
		_content_area.add_child(_database_panel)
		_database_panel.hide()
	var show_maps: bool = which == "maps"
	_map_editor.visible = show_maps
	_database_panel.visible = not show_maps
	_maps_btn.button_pressed = show_maps
	_database_btn.button_pressed = not show_maps


func _on_save_pressed() -> void:
	if ProjectState.current_project_path.is_empty():
		_on_save_as_pressed()
	else:
		ProjectState.save()


func _on_save_as_pressed() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.filters = PackedStringArray(["*.rpgc ; RPG Creator Project"])
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_selected.connect(func(path: String) -> void:
		if not path.ends_with(".rpgc"):
			path += ".rpgc"
		ProjectState.save(path)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


func _on_close_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/StartScreen.tscn")


func _on_project_saved(_path: String) -> void:
	_update_project_label()


func _on_playtest_pressed() -> void:
	# Auto-save before play-test if the project has a path.
	if not ProjectState.current_project_path.is_empty():
		ProjectState.save()
	SignalBus.playtest_requested.emit()
	hide()
	var scene := load("res://scenes/runtime/RuntimePlayer.tscn") as PackedScene
	_runtime_player = scene.instantiate()
	get_tree().root.add_child(_runtime_player)


func _on_playtest_stopped() -> void:
	if _runtime_player:
		_runtime_player.queue_free()
		_runtime_player = null
	show()
