extends Node2D
## Screen-space print artwork anchored to a world impact; no imported art needed.
var anchor := Vector3.ZERO
var word := "POW!"
var style: int = 0
var screen_offset := Vector2.ZERO
var age: float = 0.0
const LIFETIME := 0.85
var _font: SystemFont

func _ready() -> void:
	add_to_group("comic_wall_impacts")
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Impact","Arial Black","DejaVu Sans"])
	_font.font_weight = 900
	rotation = deg_to_rad(-12.0 if style % 2 == 0 else 10.0)
	queue_redraw()

func _process(delta: float) -> void:
	age += delta
	if age >= LIFETIME:
		queue_free()
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null or camera.is_position_behind(anchor):
		visible = false
		return
	visible = true
	var viewport_size := get_viewport_rect().size
	var screen_scale := clampf(viewport_size.y/1080.0,0.55,1.5)
	position = camera.unproject_position(anchor) + (screen_offset+Vector2(0,-38.0-age*48.0))*screen_scale
	var pop := lerpf(0.25,1.18,sin(clampf(age/0.11,0.0,1.0)*PI*0.5))
	if age > 0.11:
		pop = lerpf(1.18,1.0,clampf((age-0.11)/0.13,0.0,1.0))
	scale = Vector2.ONE*screen_scale*pop
	modulate.a = 1.0-smoothstep(0.57,LIFETIME,age)

func _star(size_factor: float, offset: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in range(24):
		var angle := float(index)*TAU/24.0
		var radius := 1.0 if index % 2 == 0 else 0.62
		radius *= 1.0+sin(float(index)*7.3)*0.09
		points.append(Vector2(cos(angle)*132.0,sin(angle)*78.0)*radius*size_factor+offset)
	return points

func _draw() -> void:
	var ink := Color("171526")
	var paper := Color("ffe76a")
	var accent := Color("ed5141") if style != 1 else Color("42b8d1")
	var back := _star(1.11,Vector2(7,8))
	draw_colored_polygon(back,ink)
	var outer := _star(1.03,Vector2.ZERO)
	draw_colored_polygon(outer,accent)
	outer.append(outer[0])
	draw_polyline(outer,ink,4.0,true)
	var inner := _star(0.86,Vector2(-3,-2))
	draw_colored_polygon(inner,paper)
	# Halftone ink stays inside the inner paper burst.
	for x in range(-105,106,9):
		for y in range(-60,61,9):
			var dot := Vector2(x,y)
			if Geometry2D.is_point_in_polygon(dot,inner):
				draw_circle(dot,1.35,Color(0.65,0.26,0.12,0.22))
	var font_size := 56
	var text_size := _font.get_string_size(word,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	var baseline := Vector2(-text_size.x*0.5,(_font.get_ascent(font_size)-_font.get_descent(font_size))*0.5)
	draw_string_outline(_font,baseline+Vector2(3,4),word,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,10,ink)
	draw_string_outline(_font,baseline,word,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,7,ink)
	draw_string(_font,baseline,word,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("fff8da"))
