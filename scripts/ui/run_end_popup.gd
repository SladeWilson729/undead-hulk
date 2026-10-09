class_name RunEndPopup
extends Control
## The run summary: vector comic artwork and live text, fitted to the viewport without clipping.
## Shown by the HUD when the run ends. Death and victory share the layout; `won` swaps the
## headline, the starburst and the subtitle.
const INK := Color("20212b")
const PAPER := Color("f1e5bd")
const GREEN := Color("c4ef65")
const CORAL := Color("f47c66")
const DESIGN := Vector2(1080, 850)
## A full run: 14 standard waves, then wave 15 and the boss.
const FINAL_WAVE := 15
## Kill rows, top to bottom. Must match KillCause.LABELS names.
const CAUSE_ROWS := ["Smashed", "Stomped", "Eaten", "Crushed", "Buried", "Friendly Fire", "Fell"]
var sheet: Control
var headline: SystemFont
var body: SystemFont
var data: Dictionary

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	headline = SystemFont.new()
	headline.font_names = PackedStringArray(["Impact", "DejaVu Sans"])
	headline.font_weight = 900
	body = SystemFont.new()
	body.font_names = PackedStringArray(["Trebuchet MS", "DejaVu Sans"])
	body.font_weight = 700
	var shade := ColorRect.new()
	shade.color = Color(0.035, 0.045, 0.06, 0.83)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	sheet = Control.new()
	sheet.size = DESIGN
	sheet.draw.connect(_art)
	add_child(sheet)
	get_viewport().size_changed.connect(_fit)
	_fit()

func _fit() -> void:
	var viewport := get_viewport_rect().size
	var factor := minf((viewport.x - 40.0) / DESIGN.x, (viewport.y - 40.0) / DESIGN.y)
	sheet.scale = Vector2.ONE * factor
	sheet.position = (viewport - DESIGN * factor) * 0.5

func _poly(points: Array, color: Color) -> void:
	var vertices := PackedVector2Array(points)
	sheet.draw_colored_polygon(vertices, color)
	vertices.append(vertices[0])
	sheet.draw_polyline(vertices, INK, 5.0, true)

func _art() -> void:
	_poly([Vector2(32,49), Vector2(1055,28), Vector2(1072,821), Vector2(41,843)], Color("080d11"))
	_poly([Vector2(15,28), Vector2(1034,12), Vector2(1050,803), Vector2(28,825)], PAPER)
	# Sparse, deterministic flecks and halftone edges give the paper a printed finish.
	for i in range(330):
		var x := float((i * 193 + 21) % 1010 + 28)
		var y := float((i * 79 + 39) % 774 + 30)
		sheet.draw_line(Vector2(x,y), Vector2(x+3,y+1), Color(0.28,0.24,0.17,0.1), 1)
	for x in range(42, 1020, 13):
		for y in range(42, 156, 13):
			sheet.draw_circle(Vector2(x,y), 1.6, Color(0.2,0.2,0.17,0.13))
	_poly([Vector2(46,55),Vector2(691,43),Vector2(709,145),Vector2(59,156)], CORAL)
	_poly([Vector2(748,42),Vector2(783,58),Vector2(814,28),Vector2(839,50),Vector2(897,35),Vector2(910,58),Vector2(994,60),Vector2(976,96),Vector2(1018,122),Vector2(978,141),Vector2(981,164),Vector2(905,158),Vector2(866,179),Vector2(842,156),Vector2(775,170),Vector2(782,140),Vector2(741,113),Vector2(770,92)], GREEN)
	sheet.draw_style_box(_box(INK), Rect2(56,212,968,139))
	sheet.draw_line(Vector2(681,231),Vector2(681,332),Color("606459"),2)
	sheet.draw_line(Vector2(591,385),Vector2(591,666),Color("b8ae8e"),2)
	sheet.draw_line(Vector2(57,682),Vector2(1021,682),INK,3)

func _box(color: Color, border: Color = INK, width: int = 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	return style

func _text(value: String, rect: Rect2, font_size: int, color: Color = INK, display: bool = false, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = value
	label.position = rect.position
	label.size = rect.size
	label.add_theme_font_override("font", headline if display else body)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(label)
	return label

func number(value: int) -> String:
	var raw := str(value)
	var out := ""
	for i in raw.length():
		if i > 0 and (raw.length() - i) % 3 == 0:
			out += ","
		out += raw[i]
	return out

## Largest font size (up to `start`) at which `value` fits in `width` pixels.
func _fit_size(value: String, font: Font, start: int, width: float) -> int:
	var size := start
	while size > 12 and font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		size -= 2
	return size


func present(summary: Dictionary) -> void:
	data = summary
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var won: bool = data.get("won", false)
	# Headline sized to sit inside the coral banner (its inner width is ~600 px).
	var title := "SMASHED IT!" if won else "DEAD. AGAIN."
	_text(title, Rect2(78,49,610,108), _fit_size(title, headline, 82, 600.0), INK, true)
	var subtitle := "UNDEAD HULK  /  ALL %d WAVES + BOSS" % FINAL_WAVE if won else "UNDEAD HULK  /  FELL ON WAVE %d OF %d" % [data.get("wave", 1), FINAL_WAVE]
	_text(subtitle,Rect2(63,167,620,32),18)
	_text("FULL...\nFOR NOW" if won else "STILL\nHUNGRY!",Rect2(784,64,195,87),31,INK,true,HORIZONTAL_ALIGNMENT_CENTER)
	_text("TOTAL MAYHEM",Rect2(79,229,470,27),18,GREEN)
	_text(number(int(data.get("score",0))),Rect2(78,250,580,90),65,PAPER,true)
	var best_label := "NEW PERSONAL BEST!" if data.get("new_best",false) else "PERSONAL BEST"
	_text(best_label,Rect2(712,233,290,30),19,GREEN)
	_text(number(int(data.get("best",0))),Rect2(712,265,289,49),36,PAPER,true)
	_text("Saved on this device" if data.get("save_ok",true) else "Couldn't save this score",Rect2(712,313,290,25),14,PAPER)
	_text("THE DAMAGE REPORT",Rect2(61,365,510,40),28,INK,true)
	_text("WAVE %02d   /   %d KILLS" % [data.get("wave",1),data.get("kills",0)],Rect2(621,367,398,38),25,INK,true)
	var counts: Dictionary = {}
	for entry in data.get("kills_by_cause",[]):
		counts[entry[0]] = entry[1]
	var names: Array = CAUSE_ROWS
	for i in names.size():
		var y := 413 + i * 32
		if i % 2 == 0:
			var strip := ColorRect.new()
			strip.position = Vector2(59,y)
			strip.size = Vector2(506,31)
			strip.color = Color(0.23,0.24,0.18,0.07)
			strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sheet.add_child(strip)
		_text("%02d" % (i+1),Rect2(70,y+1,40,30),15,Color("797662"))
		_text(names[i],Rect2(115,y-1,337,32),21)
		_text(str(counts.get(names[i],0)),Rect2(454,y-2,94,32),23,INK,true,HORIZONTAL_ALIGNMENT_RIGHT)
	var extras := int(counts.get("Other",0))
	_text("Other mishaps: %d" % extras if extras > 0 else "Every body tells a story. A short one.",Rect2(70,645,490,28),15,Color("66624f"))
	var items := [["Kill points",data.get("kill_points",0)],["Special bounties",data.get("bounty_points",0)],["Style bonuses",data.get("style_points",0)],["Wave clears (%d)" % data.get("waves_cleared",0),data.get("wave_points",0)]]
	for i in items.size():
		_text(items[i][0],Rect2(622,414+i*34,273,32),19)
		_text("+"+number(int(items[i][1])),Rect2(883,414+i*34,121,32),20,INK,false,HORIZONTAL_ALIGNMENT_RIGHT)
	_text("JUGGLED  %d    /    WALL SPLATS  %d" % [data.get("juggles",0),data.get("splats",0)],Rect2(623,552,395,30),19,INK,true)
	var specials: Dictionary = data.get("specials",{})
	var special_count := 0
	for count in specials.values():
		special_count += int(count)
	_text("%d specials sent back to training." % special_count,Rect2(623,582,395,26),15,Color("66624f"))
	# Augments claimed this run, by name. Wraps to two lines, then trims.
	var augments: Array = data.get("augments",[])
	_text("AUGMENTS CLAIMED  %d" % augments.size(),Rect2(623,612,395,28),19,INK,true)
	var aug_line := "None yet. Survive a wave to choose one." if augments.is_empty() else ", ".join(PackedStringArray(augments))
	var aug_label := _text(aug_line,Rect2(623,640,395,40),14,Color("4a4838"))
	aug_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	aug_label.max_lines_visible = 2
	aug_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# The label grew to fit the text on one line before wrapping was on; pin it back.
	aug_label.clip_text = true
	aug_label.size = Vector2(395, 40)
	_text("Kill + bounty points x wave. Style pays extra.",Rect2(61,692,940,28),17,INK,false,HORIZONTAL_ALIGNMENT_CENTER)
	var retry := Button.new()
	retry.name = "NewRun"
	retry.text = "NEW RUN   [R]"
	retry.position = Vector2(300,734)
	retry.size = Vector2(480,64)
	retry.add_theme_font_override("font",headline)
	retry.add_theme_font_size_override("font_size",31)
	retry.add_theme_color_override("font_color",INK)
	retry.add_theme_color_override("font_focus_color",INK)
	retry.add_theme_color_override("font_hover_color",INK)
	retry.add_theme_color_override("font_pressed_color",INK)
	retry.add_theme_stylebox_override("normal",_box(GREEN,INK,4))
	retry.add_theme_stylebox_override("hover",_box(Color("dcff98"),INK,4))
	retry.add_theme_stylebox_override("pressed",_box(Color("9bc24d"),INK,4))
	retry.add_theme_stylebox_override("focus",_box(Color(0,0,0,0),Color("f47c66"),3))
	retry.pressed.connect(func() -> void: get_tree().reload_current_scene())
	sheet.add_child(retry)
	retry.grab_focus()
	modulate.a = 0.0
	create_tween().tween_property(self,"modulate:a",1.0,0.2)

