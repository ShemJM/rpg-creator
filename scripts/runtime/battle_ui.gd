class_name BattleUI
extends CanvasLayer
## Minimal battle display. Purely reactive — logic lives in BattleManager;
## headless scenario runs never need this painted. Buttons let a human play:
## they submit through the same BattleManager.submit_action path as
## scripted actions.

var manager: BattleManager = null

var _panel: PanelContainer
var _status: Label
var _log: Label
var _buttons: HBoxContainer


func _ready() -> void:
	layer = 12
	_build_ui()
	_panel.hide()
	SignalBus.battle_requested.connect(func(_ids: Array, _flee: bool) -> void:
		_panel.show()
		_refresh())
	SignalBus.trace_battle_action.connect(func(actor: String, action: String, target: String, amount: int, hp_left: int) -> void:
		if _log:
			_log.text = "%s %s %s for %d (%d HP left)" % [actor, action, target, amount, hp_left]
		_refresh())
	SignalBus.trace_battle_ended.connect(func(_result: String, _gold: int, _rewards: Array) -> void:
		_panel.hide())


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.custom_minimum_size = Vector2(420, 0)
	add_child(_panel)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	_status = Label.new()
	vbox.add_child(_status)

	_log = Label.new()
	vbox.add_child(_log)

	_buttons = HBoxContainer.new()
	vbox.add_child(_buttons)

	var attack_btn := Button.new()
	attack_btn.text = "Attack"
	attack_btn.pressed.connect(func() -> void:
		if manager:
			manager.submit_action("attack", { "target": 0 }))
	_buttons.add_child(attack_btn)

	var flee_btn := Button.new()
	flee_btn.text = "Flee"
	flee_btn.pressed.connect(func() -> void:
		if manager:
			manager.submit_action("flee", {}))
	_buttons.add_child(flee_btn)


func _refresh() -> void:
	if _status == null or manager == null:
		return
	var parts: Array[String] = []
	for m in GameState.party:
		parts.append("%s %d HP" % [m["name"], int(m["hp"])])
	for e in manager.enemies:
		parts.append("[E] %s %d/%d" % [e["name"], int(e["hp"]), int(e["max_hp"])])
	_status.text = " | ".join(parts)
