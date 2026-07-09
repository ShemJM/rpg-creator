class_name DatabasePanel
extends VBoxContainer
## Database editor — authors actors, classes, items, weapons and armor.
## Category tab strip → entry list (add/delete) → per-entry field editor.

const CATEGORIES: Array = [
	{ "key": "actors", "label": "Actors" },
	{ "key": "classes", "label": "Classes" },
	{ "key": "items", "label": "Items" },
	{ "key": "weapons", "label": "Weapons" },
	{ "key": "armor", "label": "Armor" },
]

var _category: String = "actors"
var _selected_index: int = -1

@onready var _category_tabs: HBoxContainer = $CategoryTabs
@onready var _entry_list: VBoxContainer = $Body/LeftPanel/EntryScroll/EntryList
@onready var _add_btn: Button = $Body/LeftPanel/EntryButtons/AddBtn
@onready var _delete_btn: Button = $Body/LeftPanel/EntryButtons/DeleteBtn
@onready var _editor_form: VBoxContainer = $Body/EditorScroll/EditorForm


func _ready() -> void:
	_build_category_tabs()
	_add_btn.pressed.connect(_on_add_entry)
	_delete_btn.pressed.connect(_on_delete_entry)
	_select_category(_category)


func _build_category_tabs() -> void:
	for child in _category_tabs.get_children():
		child.queue_free()
	for cat in CATEGORIES:
		var btn := Button.new()
		btn.text = cat["label"]
		btn.toggle_mode = true
		btn.button_pressed = (cat["key"] == _category)
		btn.pressed.connect(_select_category.bind(cat["key"]))
		_category_tabs.add_child(btn)


func _select_category(key: String) -> void:
	_category = key
	_selected_index = -1
	for i in range(_category_tabs.get_child_count()):
		var btn := _category_tabs.get_child(i) as Button
		btn.button_pressed = (CATEGORIES[i]["key"] == key)
	_rebuild_entry_list()
	_rebuild_editor()


# ---------------------------------------------------------------------------
# Entry list
# ---------------------------------------------------------------------------

## The resources shown for the current category (equipment is filtered by kind).
func _current_entries() -> Array:
	match _category:
		"actors": return ProjectState.actors
		"classes": return ProjectState.classes
		"items": return ProjectState.items
		"weapons": return ProjectState.equipment.filter(func(e): return e.kind == EquipData.KIND_WEAPON)
		"armor": return ProjectState.equipment.filter(func(e): return e.kind == EquipData.KIND_ARMOR)
	return []


func _entry_name(entry) -> String:
	match _category:
		"actors": return entry.actor_name
		"classes": return entry.class_name_
		"items": return entry.item_name
		"weapons", "armor": return entry.equip_name
	return "?"


func _rebuild_entry_list() -> void:
	for child in _entry_list.get_children():
		child.queue_free()
	var entries := _current_entries()
	for i in range(entries.size()):
		var entry = entries[i]
		var btn := Button.new()
		btn.text = "%03d: %s" % [entry.id, _entry_name(entry)]
		btn.toggle_mode = true
		btn.button_pressed = (i == _selected_index)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_entry_selected.bind(i))
		_entry_list.add_child(btn)


func _on_entry_selected(index: int) -> void:
	_selected_index = index
	_rebuild_entry_list()
	_rebuild_editor()


func _on_add_entry() -> void:
	var new_entry
	match _category:
		"actors": new_entry = ProjectState.add_actor()
		"classes": new_entry = ProjectState.add_class()
		"items": new_entry = ProjectState.add_item()
		"weapons": new_entry = ProjectState.add_equip("New Weapon", EquipData.KIND_WEAPON)
		"armor": new_entry = ProjectState.add_equip("New Armor", EquipData.KIND_ARMOR)
	var entries := _current_entries()
	_selected_index = entries.find(new_entry)
	_rebuild_entry_list()
	_rebuild_editor()


func _on_delete_entry() -> void:
	var entries := _current_entries()
	if _selected_index < 0 or _selected_index >= entries.size():
		return
	var entry = entries[_selected_index]
	match _category:
		"actors": ProjectState.actors.erase(entry)
		"classes": ProjectState.classes.erase(entry)
		"items": ProjectState.items.erase(entry)
		"weapons", "armor": ProjectState.equipment.erase(entry)
	_selected_index = -1
	_rebuild_entry_list()
	_rebuild_editor()


# ---------------------------------------------------------------------------
# Field editor
# ---------------------------------------------------------------------------

func _rebuild_editor() -> void:
	for child in _editor_form.get_children():
		child.queue_free()
	var entries := _current_entries()
	if _selected_index < 0 or _selected_index >= entries.size():
		var hint := Label.new()
		hint.text = "Select or add an entry."
		_editor_form.add_child(hint)
		return
	var entry = entries[_selected_index]
	match _category:
		"actors": _build_actor_editor(entry)
		"classes": _build_class_editor(entry)
		"items": _build_item_editor(entry)
		"weapons", "armor": _build_equip_editor(entry)


func _build_actor_editor(actor: ActorData) -> void:
	_add_line_edit("Name:", actor.actor_name, func(t: String) -> void:
		actor.actor_name = t
		_refresh_selected_label()
	)
	_add_class_option("Class:", actor.class_id, func(id: int) -> void: actor.class_id = id)
	_add_spin_row("Initial Level:", 1, 99, actor.initial_level,
		func(v: float) -> void: actor.initial_level = int(v))
	_add_graphic_row("Charset:",
		func() -> CharacterGraphic: return actor.graphic,
		func(result: CharacterGraphic) -> void: actor.graphic = result)
	_add_section("Base Stats")
	_build_stat_block_ui(actor.stats)
	_add_section("Note")
	_add_text_edit(actor.note, func(t: String) -> void: actor.note = t)


func _build_class_editor(cls: ClassData) -> void:
	_add_line_edit("Name:", cls.class_name_, func(t: String) -> void:
		cls.class_name_ = t
		_refresh_selected_label()
	)
	_add_section("Base Stats")
	_build_stat_block_ui(cls.stats)
	_add_section("Note")
	_add_text_edit(cls.note, func(t: String) -> void: cls.note = t)


func _build_item_editor(item: ItemData) -> void:
	_add_line_edit("Name:", item.item_name, func(t: String) -> void:
		item.item_name = t
		_refresh_selected_label()
	)
	_add_spin_row("Price:", 0, 999999, item.price, func(v: float) -> void: item.price = int(v))
	_add_check_row("Consumable", item.consumable, func(on: bool) -> void: item.consumable = on)
	_add_section("Effect")
	_add_spin_row("Restore HP:", 0, 99999, int(item.effect.get("hp", 0)),
		func(v: float) -> void: item.effect["hp"] = int(v))
	_add_spin_row("Restore MP:", 0, 99999, int(item.effect.get("mp", 0)),
		func(v: float) -> void: item.effect["mp"] = int(v))
	_add_section("Description")
	_add_text_edit(item.description, func(t: String) -> void: item.description = t)


func _build_equip_editor(equip: EquipData) -> void:
	_add_line_edit("Name:", equip.equip_name, func(t: String) -> void:
		equip.equip_name = t
		_refresh_selected_label()
	)
	_add_line_edit("Slot:", equip.slot, func(t: String) -> void: equip.slot = t)
	_add_spin_row("Price:", 0, 999999, equip.price, func(v: float) -> void: equip.price = int(v))
	_add_section("Stat Bonuses")
	_build_stat_block_ui(equip.stat_mods)
	_add_section("Description")
	_add_text_edit(equip.description, func(t: String) -> void: equip.description = t)


## Refresh only the selected entry-list button label (name changed).
func _refresh_selected_label() -> void:
	if _selected_index < 0 or _selected_index >= _entry_list.get_child_count():
		return
	var entries := _current_entries()
	if _selected_index < entries.size():
		var btn := _entry_list.get_child(_selected_index) as Button
		var entry = entries[_selected_index]
		btn.text = "%03d: %s" % [entry.id, _entry_name(entry)]


# ---------------------------------------------------------------------------
# Reusable field widgets
# ---------------------------------------------------------------------------

func _build_stat_block_ui(stats: StatBlock) -> void:
	for field in StatBlock.FIELDS:
		var key: String = field["key"]
		_add_spin_row(field["label"] + ":", -9999, 99999, int(stats.get(key)),
			func(v: float) -> void: stats.set(key, int(v)))


func _add_section(title: String) -> void:
	_editor_form.add_child(HSeparator.new())
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 16)
	_editor_form.add_child(lbl)


func _labeled_row(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(120, 0)
	row.add_child(label)
	_editor_form.add_child(row)
	return row


func _add_line_edit(label: String, value: String, cb: Callable) -> void:
	var row := _labeled_row(label)
	var edit := LineEdit.new()
	edit.text = value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(cb)
	row.add_child(edit)


func _add_spin_row(label: String, min_v: int, max_v: int, value: int, cb: Callable) -> void:
	var row := _labeled_row(label)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.value = value
	spin.value_changed.connect(cb)
	row.add_child(spin)


func _add_check_row(label: String, value: bool, cb: Callable) -> void:
	var row := _labeled_row("")
	var check := CheckBox.new()
	check.text = label
	check.button_pressed = value
	check.toggled.connect(cb)
	row.add_child(check)


func _add_text_edit(value: String, cb: Callable) -> void:
	var edit := TextEdit.new()
	edit.custom_minimum_size = Vector2(0, 80)
	edit.text = value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(func() -> void: cb.call(edit.text))
	_editor_form.add_child(edit)


func _add_class_option(label: String, current_id: int, cb: Callable) -> void:
	var row := _labeled_row(label)
	var opt := OptionButton.new()
	opt.add_item("(none)", -1)
	var selected_idx := 0
	for i in range(ProjectState.classes.size()):
		var cls: ClassData = ProjectState.classes[i]
		opt.add_item("%s" % cls.class_name_, cls.id)
		if cls.id == current_id:
			selected_idx = i + 1
	opt.selected = selected_idx
	opt.item_selected.connect(func(idx: int) -> void: cb.call(opt.get_item_id(idx)))
	row.add_child(opt)


func _add_graphic_row(label: String, get_current: Callable, on_set: Callable) -> void:
	var row := _labeled_row(label)
	var btn := Button.new()
	var current: CharacterGraphic = get_current.call()
	btn.text = current.source_path.get_file() if (current and current.is_valid()) else "(none)"
	btn.pressed.connect(func() -> void:
		GraphicPicker.open(self, get_current.call(), func(result: CharacterGraphic) -> void:
			on_set.call(result)
			btn.text = result.source_path.get_file() if (result and result.is_valid()) else "(none)"
		)
	)
	row.add_child(btn)
