extends Node
## Builds and applies a global Theme resource at startup. Attach as autoload.

var editor_theme: Theme


func _ready() -> void:
	editor_theme = _build_theme()
	# Apply to the scene tree root so all UI nodes inherit it.
	get_tree().root.theme = editor_theme


func _build_theme() -> Theme:
	var t := Theme.new()

	# --- Default font size ---
	t.set_default_font_size(DesignTokens.FONT_SIZE_BODY)

	# --- Label ---
	t.set_color("font_color", "Label", DesignTokens.COLOR_TEXT)
	t.set_font_size("font_size", "Label", DesignTokens.FONT_SIZE_LABEL)

	# --- Button ---
	t.set_stylebox("normal", "Button", _make_button_style(DesignTokens.COLOR_BG_ELEVATED))
	t.set_stylebox("hover", "Button", _make_button_style(DesignTokens.COLOR_PRIMARY.lerp(DesignTokens.COLOR_BG_ELEVATED, 0.7)))
	t.set_stylebox("pressed", "Button", _make_button_style(DesignTokens.COLOR_PRIMARY.darkened(0.2)))
	t.set_stylebox("disabled", "Button", _make_button_style(DesignTokens.COLOR_BG_PANEL.darkened(0.3)))
	t.set_stylebox("focus", "Button", _make_focus_style())
	t.set_color("font_color", "Button", DesignTokens.COLOR_TEXT)
	t.set_color("font_hover_color", "Button", DesignTokens.COLOR_TEXT_BRIGHT)
	t.set_color("font_pressed_color", "Button", DesignTokens.COLOR_TEXT_BRIGHT)
	t.set_color("font_disabled_color", "Button", DesignTokens.COLOR_TEXT_DIM)
	t.set_font_size("font_size", "Button", DesignTokens.FONT_SIZE_BODY)

	# --- PanelContainer ---
	t.set_stylebox("panel", "PanelContainer", _make_panel_style(DesignTokens.COLOR_BG_PANEL))

	# --- OptionButton ---
	t.set_stylebox("normal", "OptionButton", _make_button_style(DesignTokens.COLOR_BG_ELEVATED))
	t.set_stylebox("hover", "OptionButton", _make_button_style(DesignTokens.COLOR_BG_ELEVATED.lightened(0.1)))
	t.set_stylebox("pressed", "OptionButton", _make_button_style(DesignTokens.COLOR_PRIMARY.darkened(0.3)))
	t.set_stylebox("focus", "OptionButton", _make_focus_style())
	t.set_color("font_color", "OptionButton", DesignTokens.COLOR_TEXT)
	t.set_font_size("font_size", "OptionButton", DesignTokens.FONT_SIZE_BODY)

	# --- LineEdit ---
	t.set_stylebox("normal", "LineEdit", _make_input_style())
	t.set_stylebox("focus", "LineEdit", _make_input_focus_style())
	t.set_color("font_color", "LineEdit", DesignTokens.COLOR_TEXT)
	t.set_color("caret_color", "LineEdit", DesignTokens.COLOR_PRIMARY)
	t.set_font_size("font_size", "LineEdit", DesignTokens.FONT_SIZE_BODY)

	# --- TextEdit ---
	t.set_stylebox("normal", "TextEdit", _make_input_style())
	t.set_stylebox("focus", "TextEdit", _make_input_focus_style())
	t.set_color("font_color", "TextEdit", DesignTokens.COLOR_TEXT)
	t.set_color("caret_color", "TextEdit", DesignTokens.COLOR_PRIMARY)

	# --- SpinBox (inherits LineEdit styles) ---

	# --- ScrollContainer ---
	t.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

	# --- HSplitContainer / VSplitContainer ---
	var split_grabber := StyleBoxFlat.new()
	split_grabber.bg_color = DesignTokens.COLOR_BORDER
	split_grabber.content_margin_left = 2
	split_grabber.content_margin_right = 2
	t.set_stylebox("grabber", "HSplitContainer", split_grabber)
	t.set_stylebox("grabber", "VSplitContainer", split_grabber)
	t.set_constant("separation", "HSplitContainer", 6)
	t.set_constant("separation", "VSplitContainer", 6)

	# --- Containers spacing ---
	t.set_constant("separation", "VBoxContainer", DesignTokens.SPACE_SM)
	t.set_constant("separation", "HBoxContainer", DesignTokens.SPACE_SM)

	# --- TooltipPanel ---
	var tooltip_style := _make_panel_style(DesignTokens.COLOR_BG_ELEVATED)
	tooltip_style.border_color = DesignTokens.COLOR_BORDER
	tooltip_style.border_width_bottom = 1
	tooltip_style.border_width_top = 1
	tooltip_style.border_width_left = 1
	tooltip_style.border_width_right = 1
	t.set_stylebox("panel", "TooltipPanel", tooltip_style)
	t.set_color("font_color", "TooltipLabel", DesignTokens.COLOR_TEXT)

	# --- Window (for popups) ---
	var window_panel := _make_panel_style(DesignTokens.COLOR_BG_SURFACE)
	window_panel.shadow_color = Color(0, 0, 0, 0.5)
	window_panel.shadow_size = 12
	t.set_stylebox("embedded_border", "Window", window_panel)

	return t


# --- Style Helpers ---

func _make_button_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = int(DesignTokens.RADIUS_SM)
	s.corner_radius_top_right = int(DesignTokens.RADIUS_SM)
	s.corner_radius_bottom_left = int(DesignTokens.RADIUS_SM)
	s.corner_radius_bottom_right = int(DesignTokens.RADIUS_SM)
	s.content_margin_left = DesignTokens.SPACE_MD
	s.content_margin_right = DesignTokens.SPACE_MD
	s.content_margin_top = DesignTokens.SPACE_SM
	s.content_margin_bottom = DesignTokens.SPACE_SM
	return s


func _make_panel_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = int(DesignTokens.RADIUS_MD)
	s.corner_radius_top_right = int(DesignTokens.RADIUS_MD)
	s.corner_radius_bottom_left = int(DesignTokens.RADIUS_MD)
	s.corner_radius_bottom_right = int(DesignTokens.RADIUS_MD)
	s.content_margin_left = DesignTokens.SPACE_MD
	s.content_margin_right = DesignTokens.SPACE_MD
	s.content_margin_top = DesignTokens.SPACE_MD
	s.content_margin_bottom = DesignTokens.SPACE_MD
	return s


func _make_input_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = DesignTokens.COLOR_BG_DARK
	s.border_color = DesignTokens.COLOR_BORDER
	s.border_width_bottom = 1
	s.border_width_top = 1
	s.border_width_left = 1
	s.border_width_right = 1
	s.corner_radius_top_left = int(DesignTokens.RADIUS_SM)
	s.corner_radius_top_right = int(DesignTokens.RADIUS_SM)
	s.corner_radius_bottom_left = int(DesignTokens.RADIUS_SM)
	s.corner_radius_bottom_right = int(DesignTokens.RADIUS_SM)
	s.content_margin_left = DesignTokens.SPACE_SM
	s.content_margin_right = DesignTokens.SPACE_SM
	s.content_margin_top = DesignTokens.SPACE_SM
	s.content_margin_bottom = DesignTokens.SPACE_SM
	return s


func _make_input_focus_style() -> StyleBoxFlat:
	var s := _make_input_style()
	s.border_color = DesignTokens.COLOR_PRIMARY
	s.border_width_bottom = 2
	s.border_width_top = 2
	s.border_width_left = 2
	s.border_width_right = 2
	return s


func _make_focus_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color.TRANSPARENT
	s.border_color = DesignTokens.COLOR_PRIMARY
	s.border_width_bottom = 2
	s.border_width_top = 2
	s.border_width_left = 2
	s.border_width_right = 2
	s.corner_radius_top_left = int(DesignTokens.RADIUS_SM)
	s.corner_radius_top_right = int(DesignTokens.RADIUS_SM)
	s.corner_radius_bottom_left = int(DesignTokens.RADIUS_SM)
	s.corner_radius_bottom_right = int(DesignTokens.RADIUS_SM)
	return s
