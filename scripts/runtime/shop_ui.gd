class_name ShopUI
extends CanvasLayer
## Runtime shop session. Opened by SHOP_PROCESSING via SignalBus.shop_requested;
## emits SignalBus.shop_finished when closed so the event runner resumes.
##
## Both the on-screen buttons and the scripted signals (scripted_shop_buy /
## scripted_shop_sell / scripted_shop_close) funnel into the same handlers,
## which mutate GameState (the single trace-emission point) — so headless
## scenario runs and human play are byte-identical in observable behavior.

## Resolved entries for the open session:
## { "kind": String, "id": int, "name": String, "price": int }
var entries: Array = []
var is_open: bool = false

var _root: Control
var _panel: PanelContainer
var _list: VBoxContainer
var _gold_label: Label


func _ready() -> void:
	layer = 11
	_build_ui()
	_panel.hide()
	SignalBus.shop_requested.connect(_on_shop_requested)
	SignalBus.scripted_shop_buy.connect(_on_buy)
	SignalBus.scripted_shop_sell.connect(_on_sell)
	SignalBus.scripted_shop_close.connect(_on_close)


func _on_shop_requested(raw_entries: Array) -> void:
	entries = []
	for e in raw_entries:
		if not e is Dictionary:
			continue
		var kind: String = str((e as Dictionary).get("kind", "item"))
		var id: int = int((e as Dictionary).get("id", 0))
		var name := ""
		var db_price := 0
		if kind == "equip":
			var eq := ProjectState.get_equip_by_id(id)
			if eq == null:
				continue
			name = eq.equip_name
			db_price = eq.price
		else:
			var item := ProjectState.get_item_by_id(id)
			if item == null:
				continue
			name = item.item_name
			db_price = item.price
		var price: int = int((e as Dictionary).get("price", db_price))
		entries.append({ "kind": kind, "id": id, "name": name, "price": price })
	is_open = true
	SignalBus.trace_shop_opened.emit(entries)
	_refresh()
	_panel.show()


## Buy `count` of entry `index`. Rejected (no state change) when gold is short.
func _on_buy(index: int, count: int) -> void:
	if not is_open or index < 0 or index >= entries.size() or count < 1:
		return
	var entry: Dictionary = entries[index]
	var cost: int = int(entry["price"]) * count
	var ok: bool = GameState.gold >= cost
	if ok:
		GameState.change_gold("sub", cost)
		GameState.change_stock(entry["kind"], entry["id"], "add", count)
	SignalBus.trace_shop_transaction.emit("buy", entry["kind"], entry["id"], count, -cost if ok else 0, ok)
	_refresh()


## Sell `count` of a stocked item/equip at half its database price.
func _on_sell(kind: String, id: int, count: int) -> void:
	if not is_open or count < 1:
		return
	var ok: bool = GameState.get_stock(kind, id) >= count
	var gain := 0
	if ok:
		var db_price := 0
		if kind == "equip":
			var eq := ProjectState.get_equip_by_id(id)
			db_price = eq.price if eq else 0
		else:
			var item := ProjectState.get_item_by_id(id)
			db_price = item.price if item else 0
		gain = (db_price / 2) * count
		GameState.change_stock(kind, id, "sub", count)
		GameState.change_gold("add", gain)
	SignalBus.trace_shop_transaction.emit("sell", kind, id, count, gain, ok)
	_refresh()


func _on_close() -> void:
	if not is_open:
		return
	is_open = false
	entries = []
	_panel.hide()
	SignalBus.trace_shop_closed.emit()
	SignalBus.shop_finished.emit()


# ---------------------------------------------------------------------------
# Minimal UI (headless runs never need it painted)
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(360, 0)
	_root.add_child(_panel)

	var vbox := VBoxContainer.new()
	_panel.add_child(vbox)

	var title := Label.new()
	title.text = "Shop"
	vbox.add_child(title)

	_gold_label = Label.new()
	vbox.add_child(_gold_label)

	_list = VBoxContainer.new()
	vbox.add_child(_list)

	var close_btn := Button.new()
	close_btn.text = "Leave"
	close_btn.pressed.connect(_on_close)
	vbox.add_child(close_btn)


func _refresh() -> void:
	if _gold_label:
		_gold_label.text = "Gold: %d" % GameState.gold
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var btn := Button.new()
		btn.text = "%s — %d g" % [entry["name"], entry["price"]]
		btn.pressed.connect(_on_buy.bind(i, 1))
		_list.add_child(btn)
