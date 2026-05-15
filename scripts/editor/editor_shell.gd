class_name EditorShell
extends MarginContainer
## Main editor navigation shell. Manages switching between editor panels.

var _map_editor: Control = null
var _runtime_player: Node = null

@onready var _nav_bar: VBoxContainer = $HSplit/NavPanel/VBox/NavBar
@onready var _content_area: Control = $HSplit/ContentArea
@onready var _playtest_btn: Button = $HSplit/NavPanel/VBox/PlayTestButton


func _ready() -> void:
	SignalBus.playtest_stopped.connect(_on_playtest_stopped)
	_playtest_btn.pressed.connect(_on_playtest_pressed)
	# Open map editor by default.
	_show_map_editor()


func _show_map_editor() -> void:
	if _map_editor == null:
		var scene := load("res://scenes/editor/MapEditor.tscn") as PackedScene
		_map_editor = scene.instantiate()
		_content_area.add_child(_map_editor)
	_map_editor.show()


func _on_playtest_pressed() -> void:
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
