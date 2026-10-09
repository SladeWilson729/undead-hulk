class_name PauseMenu
extends Control
## Esc (or P) mid-run: pauses the game and shows the settings card. Same ink-and-paper look as
## the pick screen and the run summary. Sound toggles save at once (GameSettings).
## The HUD opens it; Esc, P or RESUME closes it.

signal closed

const INK := Color("20212b")
const PAPER := Color("f1e5bd")
const ON_COLOR := Color("c4ef65")
const OFF_COLOR := Color("f47c66")
const DESIGN := Vector2(560, 470)
## Rows: setting key, label.
const ROWS := [["music", "MUSIC"], ["sfx", "SOUND EFFECTS"], ["voice", "HULK & BOSS VOICES"]]

var sheet: Control
var headline: SystemFont
var body: SystemFont
## Setting key -> its ON/OFF button (tests press these).
var toggles: Dictionary = {}
var _was_paused: bool = false
var _mouse_mode: Input.MouseMode
var _done: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	headline = SystemFont.new()
	headline.font_names = PackedStringArray(["Impact", "DejaVu Sans"])
	headline.font_weight = 900
	body = SystemFont.new()
	body.font_names = PackedStringArray(["Trebuchet MS", "DejaVu Sans"])
	body.font_weight = 700
	var shade := ColorRect.new()
	shade.color = Color(0.035, 0.045, 0.06, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	sheet = Panel.new()
	sheet.size = DESIGN
	sheet.pivot_offset = DESIGN * 0.5
	sheet.rotation_degrees = -1.5
	sheet.add_theme_stylebox_override("panel", _box(PAPER, INK, 6))
	add_child(sheet)
	_build()
	get_viewport().size_changed.connect(_fit)
	_fit()
	# Pause.
	_was_paused = get_tree().paused
	get_tree().paused = true
	_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.12)


func _fit() -> void:
	var viewport := get_viewport_rect().size
	var factor := minf(minf((viewport.x - 40.0) / DESIGN.x, (viewport.y - 40.0) / DESIGN.y), 1.2)
	sheet.scale = Vector2.ONE * factor
	sheet.position = (viewport - DESIGN) * 0.5


func _build() -> void:
	var band := Panel.new()
	band.position = Vector2(0, 0)
	band.size = Vector2(DESIGN.x, 96)
	band.add_theme_stylebox_override("panel", _box(OFF_COLOR, INK, 6))
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(band)
	_label(band, "PAUSED", Rect2(0, 6, DESIGN.x, 84), 64, INK, true, HORIZONTAL_ALIGNMENT_CENTER)
	_label(sheet, "SOUND", Rect2(40, 118, 300, 34), 26, INK, true)
	for i in ROWS.size():
		var key: String = ROWS[i][0]
		var y := 166 + i * 72
		if i % 2 == 0:
			var strip := ColorRect.new()
			strip.position = Vector2(30, y - 8)
			strip.size = Vector2(DESIGN.x - 60, 64)
			strip.color = Color(0.23, 0.24, 0.18, 0.07)
			strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sheet.add_child(strip)
		_label(sheet, ROWS[i][1], Rect2(44, y + 6, 300, 36), 22, INK, false)
		var b := _button(Rect2(DESIGN.x - 190, y, 150, 48), 24)
		b.toggle_mode = true
		b.button_pressed = GameSettings.is_enabled(key)
		b.toggled.connect(func(on: bool) -> void:
			GameSettings.set_enabled(key, on)
			_style_toggle(b, on))
		_style_toggle(b, b.button_pressed)
		toggles[key] = b
	var resume := _button(Rect2(110, DESIGN.y - 92, DESIGN.x - 220, 60), 30)
	resume.name = "Resume"
	resume.text = "RESUME   [ESC]"
	resume.add_theme_stylebox_override("normal", _box(ON_COLOR, INK, 5))
	resume.add_theme_stylebox_override("hover", _box(ON_COLOR.lightened(0.15), INK, 5))
	resume.add_theme_stylebox_override("pressed", _box(ON_COLOR.darkened(0.1), INK, 5))
	resume.pressed.connect(close)


func _style_toggle(b: Button, on: bool) -> void:
	b.text = "ON" if on else "OFF"
	var color := ON_COLOR if on else OFF_COLOR
	b.add_theme_stylebox_override("normal", _box(color, INK, 5))
	b.add_theme_stylebox_override("hover", _box(color.lightened(0.15), INK, 5))
	b.add_theme_stylebox_override("pressed", _box(color.darkened(0.1), INK, 5))
	b.add_theme_stylebox_override("hover_pressed", _box(color.lightened(0.15), INK, 5))


func _unhandled_input(event: InputEvent) -> void:
	if not _done and event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()


## Unpauses (unless something else had the game paused first) and goes away.
func close() -> void:
	if _done:
		return
	_done = true
	get_tree().paused = _was_paused
	Input.mouse_mode = _mouse_mode
	closed.emit()
	var t := create_tween()
	t.tween_property(self, "modulate:a", 0.0, 0.1)
	t.tween_callback(queue_free)


func _button(rect: Rect2, font_size: int) -> Button:
	var b := Button.new()
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", headline)
	b.add_theme_font_size_override("font_size", font_size)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, INK)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sheet.add_child(b)
	return b


func _box(color: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	return style


func _label(parent: Control, value: String, rect: Rect2, font_size: int, color: Color, display: bool, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = value
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_override("font", headline if display else body)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
