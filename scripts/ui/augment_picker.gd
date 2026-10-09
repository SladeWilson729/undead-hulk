class_name AugmentPicker
extends Control
## The between-waves pick screen: three comic-paper cards, pick one with the mouse or 1/2/3.
## Same ink-and-paper look as the run summary. Runs while the game is paused.
## AugmentSystem.open_picker() creates it; `chosen` fires once and the screen fades out.

signal chosen(augment: Augment)

const INK := Color("20212b")
const PAPER := Color("f1e5bd")
const RARITY_COLORS := [Color("9fb39a"), Color("6fb4f0"), Color("f2c14e")]  # Common, Rare, Legendary
const CARD := Vector2(300, 400)
const DESIGN := Vector2(1080, 620)

var offers: Array[Augment] = []
var system: AugmentSystem
var sheet: Control
var headline: SystemFont
var body: SystemFont
var _cards: Array[Control] = []
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
	shade.color = Color(0.035, 0.045, 0.06, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	sheet = Control.new()
	sheet.size = DESIGN
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sheet)
	get_viewport().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	var viewport := get_viewport_rect().size
	var factor := minf((viewport.x - 40.0) / DESIGN.x, (viewport.y - 40.0) / DESIGN.y)
	sheet.scale = Vector2.ONE * factor
	sheet.position = (viewport - DESIGN * factor) * 0.5


func present(augment_offers: Array[Augment], augment_system: AugmentSystem) -> void:
	offers = augment_offers
	system = augment_system
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var title := _label("PICK YOUR POISON", Rect2(0, 18, DESIGN.x, 80), 64, PAPER, true, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_color_override("font_outline_color", INK)
	title.add_theme_constant_override("outline_size", 14)
	_label("Wave cleared. Choose one.  [1] [2] [3] or click", Rect2(0, 98, DESIGN.x, 30), 18, Color("c4ef65"), false, HORIZONTAL_ALIGNMENT_CENTER)
	var gap := 40.0
	var total := offers.size() * CARD.x + (offers.size() - 1) * gap
	for i in offers.size():
		var pos := Vector2((DESIGN.x - total) * 0.5 + i * (CARD.x + gap), 160)
		_cards.append(_card(offers[i], i, pos))
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)


func _card(a: Augment, index: int, pos: Vector2) -> Control:
	var card := Panel.new()
	card.position = pos
	card.size = CARD
	card.pivot_offset = CARD * 0.5
	card.rotation_degrees = [-2.0, 1.0, 2.5][index % 3]
	card.add_theme_stylebox_override("panel", _box(PAPER, INK, 5))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	sheet.add_child(card)
	# Rarity band across the top.
	var band := Panel.new()
	band.position = Vector2(0, 0)
	band.size = Vector2(CARD.x, 46)
	band.add_theme_stylebox_override("panel", _box(RARITY_COLORS[a.rarity], INK, 5))
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(band)
	_label_in(band, a.rarity_name(), Rect2(14, 6, 200, 34), 22, INK, true)
	_label_in(band, "[%d]" % (index + 1), Rect2(CARD.x - 70, 6, 56, 34), 22, INK, true, HORIZONTAL_ALIGNMENT_RIGHT)
	# Name, sized to fit.
	var name_size := 34
	while name_size > 18 and headline.get_multiline_string_size(a.display_name, HORIZONTAL_ALIGNMENT_LEFT, CARD.x - 36, name_size).y > 88:
		name_size -= 2
	_label_in(card, a.display_name, Rect2(18, 62, CARD.x - 36, 92), name_size, INK, true, HORIZONTAL_ALIGNMENT_LEFT, true)
	_label_in(card, a.category.to_upper(), Rect2(18, 156, CARD.x - 36, 24), 15, Color("8a5a3b"), false)
	var rule := ColorRect.new()
	rule.position = Vector2(18, 184)
	rule.size = Vector2(CARD.x - 36, 3)
	rule.color = INK
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(rule)
	# Description shrinks to fit above the footer.
	var desc_size := 18
	while desc_size > 12 and body.get_multiline_string_size(a.description, HORIZONTAL_ALIGNMENT_LEFT, CARD.x - 36, desc_size).y > 146:
		desc_size -= 1
	_label_in(card, a.description, Rect2(18, 196, CARD.x - 36, 150), desc_size, INK, false, HORIZONTAL_ALIGNMENT_LEFT, true)
	var owned := system.count(a.id) if system else 0
	var footer := "NEW" if owned == 0 else ("OWNED %d / %d" % [owned, a.max_stacks] if a.max_stacks > 0 else "OWNED %d" % owned)
	_label_in(card, footer, Rect2(18, CARD.y - 44, CARD.x - 36, 30), 18, Color("d4553f") if owned == 0 else INK, true)
	card.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			choose(index))
	card.mouse_entered.connect(func() -> void: _hover(card, true))
	card.mouse_exited.connect(func() -> void: _hover(card, false))
	return card


func _hover(card: Control, on: bool) -> void:
	if _done:
		return
	var t := card.create_tween()
	t.tween_property(card, "scale", Vector2.ONE * (1.06 if on else 1.0), 0.08)


func _input(event: InputEvent) -> void:
	if _done or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	var i := -1
	match key:
		KEY_1, KEY_KP_1: i = 0
		KEY_2, KEY_KP_2: i = 1
		KEY_3, KEY_KP_3: i = 2
	if i >= 0 and i < offers.size():
		get_viewport().set_input_as_handled()
		choose(i)


## Takes card `index`. Public so tests can pick without input.
func choose(index: int) -> void:
	if _done or index < 0 or index >= offers.size():
		return
	_done = true
	var card := _cards[index]
	var t := create_tween()
	t.tween_property(card, "scale", Vector2.ONE * 1.15, 0.1)
	t.tween_property(self, "modulate:a", 0.0, 0.15)
	t.tween_callback(queue_free)
	chosen.emit(offers[index])


func _box(color: Color, border: Color, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	return style


func _label(value: String, rect: Rect2, font_size: int, color: Color, display: bool, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return _label_in(sheet, value, rect, font_size, color, display, align)


func _label_in(parent: Control, value: String, rect: Rect2, font_size: int, color: Color, display: bool, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, wrap: bool = false) -> Label:
	var label := Label.new()
	# Wrapping has to be on before the text goes in, or the label sizes itself to one long line.
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = value
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_override("font", headline if display else body)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
