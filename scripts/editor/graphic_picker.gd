class_name GraphicPicker
extends RefCounted
## Shared editor popup for authoring a CharacterGraphic (charset). Used by the event
## editor (page graphic) and the database editor (actor graphic).
##
## Usage:
##   GraphicPicker.open(self, current_graphic, func(result):
##       target.graphic = result   # result is a CharacterGraphic, or null if cleared
##       refresh_ui())
##
## `host` is any Node in the tree — the popup and file dialog are parented to it.


static func open(host: Node, graphic: CharacterGraphic, on_done: Callable) -> void:
	# Edit a working copy in place; start fresh if none was assigned.
	var g: CharacterGraphic = graphic if graphic != null else CharacterGraphic.new()

	var popup := Window.new()
	popup.title = "Character Graphic"
	popup.size = Vector2i(480, 480)
	popup.transient = true
	popup.exclusive = true

	var vbox := VBoxContainer.new()
	vbox.anchors_preset = Control.PRESET_FULL_RECT
	vbox.offset_left = 10
	vbox.offset_right = -10
	vbox.offset_top = 10
	vbox.offset_bottom = -10
	popup.add_child(vbox)

	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(96, 96)
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	var refresh_preview := func() -> void:
		var tex := ProjectState.load_texture(g.source_path)
		if tex and g.is_valid():
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(g.region_for(Vector2i(0, 1), 0))
			preview.texture = atlas
		else:
			preview.texture = null

	# Spritesheet path row.
	var path_label := Label.new()
	path_label.text = "Spritesheet:"
	vbox.add_child(path_label)
	var path_row := HBoxContainer.new()
	var path_edit := LineEdit.new()
	path_edit.text = g.source_path
	path_edit.editable = false
	path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_row.add_child(path_edit)
	var browse_btn := Button.new()
	browse_btn.text = "Browse..."
	browse_btn.pressed.connect(func() -> void:
		var fd := FileDialog.new()
		fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		fd.access = FileDialog.ACCESS_FILESYSTEM
		fd.filters = PackedStringArray(["*.png ; PNG Image", "*.jpg, *.jpeg ; JPEG Image"])
		fd.file_selected.connect(func(p: String) -> void:
			g.source_path = p
			path_edit.text = p
			refresh_preview.call()
			fd.queue_free()
		)
		fd.canceled.connect(fd.queue_free)
		host.add_child(fd)
		fd.popup_centered_ratio(0.6)
	)
	path_row.add_child(browse_btn)
	vbox.add_child(path_row)

	# Numeric slicing fields.
	_add_spin(vbox, "Frame width (px):", 1, 1024, g.frame_width,
		func(v: float) -> void:
			g.frame_width = int(v)
			refresh_preview.call()
	)
	_add_spin(vbox, "Frame height (px):", 1, 1024, g.frame_height,
		func(v: float) -> void:
			g.frame_height = int(v)
			refresh_preview.call()
	)
	_add_spin(vbox, "Columns (frames/dir):", 1, 32, g.columns,
		func(v: float) -> void: g.columns = int(v))
	_add_spin(vbox, "Rows (directions):", 1, 32, g.rows,
		func(v: float) -> void: g.rows = int(v))
	_add_spin(vbox, "Walk frames per dir:", 1, 32, g.frames_per_direction,
		func(v: float) -> void: g.frames_per_direction = int(v))
	_add_spin(vbox, "Anim FPS:", 1, 60, int(g.anim_fps),
		func(v: float) -> void: g.anim_fps = float(v))

	vbox.add_child(HSeparator.new())
	var preview_label := Label.new()
	preview_label.text = "Preview (facing down):"
	vbox.add_child(preview_label)
	vbox.add_child(preview)
	refresh_preview.call()

	# Resolve to the graphic (or null when empty) and notify the caller.
	var finish := func(result: CharacterGraphic) -> void:
		popup.queue_free()
		if on_done.is_valid():
			on_done.call(result)

	var btn_row := HBoxContainer.new()
	var clear_btn := Button.new()
	clear_btn.text = "Clear Graphic"
	clear_btn.pressed.connect(func() -> void: finish.call(null))
	btn_row.add_child(clear_btn)
	var done_btn := Button.new()
	done_btn.text = "Done"
	done_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	done_btn.pressed.connect(func() -> void: finish.call(g if g.is_valid() else null))
	btn_row.add_child(done_btn)
	vbox.add_child(btn_row)

	host.add_child(popup)
	popup.close_requested.connect(func() -> void: finish.call(g if g.is_valid() else null))
	popup.popup_centered()


static func _add_spin(container: VBoxContainer, text: String, min_v: int, max_v: int, value: int, cb: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(160, 0)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.value = value
	spin.value_changed.connect(cb)
	row.add_child(spin)
	container.add_child(row)
