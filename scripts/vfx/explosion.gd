class_name Explosion
extends Node3D
## Cartoon explosion, all built in code (no art files). Spawn with Explosion.spawn().
##   - fireball: three nested spheres (yellow core, orange, dark red) that pop out fast and
##     then shrink and fade, so it reads as one rolling ball of fire
##   - flash light, ground shockwave ring, sparks, rising smoke, a scorch mark on the floor
##   - "KA-BOOM!" in the same comic style as the wall impacts
## Visual only: damage is the caller's job (see Rocket). Frees itself when done.

const COMIC := preload("res://scripts/vfx/comic_wall_impact.gd")
const WORDS := ["KA-BOOM!", "BLAM!", "KRAKOOM!"]

static var _scorch_texture: GradientTexture2D
static var _word_index: int = 0


## radius = size of the fireball at its biggest (m). Matches the damage radius by default.
static func spawn(parent: Node, at: Vector3, radius: float = 3.0) -> Explosion:
	var e := Explosion.new()
	parent.add_child(e)
	e.global_position = at
	e._build(radius)
	return e


func _build(radius: float) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Fireball: inner layers grow fastest and die first.
	var layers := [
		[Color(1.0, 0.95, 0.55), 0.55, 0.12, 0.30],  # color, size (x radius), grow time, fade time
		[Color(1.0, 0.55, 0.12), 0.8, 0.16, 0.42],
		[Color(0.75, 0.16, 0.05), 1.0, 0.2, 0.55],
	]
	for l in layers:
		var ball := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 20
		sphere.rings = 10
		ball.mesh = sphere
		var mat := VfxMat.glow(l[0], 1.0)
		ball.material_override = mat
		ball.scale = Vector3.ONE * radius * 0.15
		add_child(ball)
		var full: float = radius * l[1]
		var t := create_tween()
		t.tween_property(ball, "scale", Vector3.ONE * full, l[2]).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		t.parallel().tween_property(ball, "position:y", full * 0.35, l[2] + l[3])
		t.tween_property(mat, "albedo_color:a", 0.0, l[3])
		t.parallel().tween_property(ball, "scale", Vector3.ONE * full * 0.6, l[3])

	# Flash.
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.65, 0.3)
	light.light_energy = 8.0
	light.omni_range = radius * 4.0
	light.position.y = 1.0
	add_child(light)
	create_tween().tween_property(light, "light_energy", 0.0, 0.4).set_ease(Tween.EASE_OUT)

	# Shockwave ring along the ground.
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	ring.mesh = torus
	var ring_mat := VfxMat.glow(Color(1.0, 0.9, 0.7), 0.8)
	ring.material_override = ring_mat
	ring.scale = Vector3(0.3, 0.15, 0.3)
	add_child(ring)
	ring.global_position = Vector3(global_position.x, 0.1, global_position.z)
	var rt := create_tween()
	rt.tween_property(ring, "scale", Vector3(radius * 1.4, 0.15, radius * 1.4), 0.3).set_ease(Tween.EASE_OUT)
	rt.parallel().tween_property(ring_mat, "albedo_color:a", 0.0, 0.3)

	for p in [_sparks(radius), _smoke(radius)]:
		add_child(p)
		p.emitting = true
	_scorch(radius)
	_comic()
	get_tree().create_timer(2.2).timeout.connect(queue_free)


func _sparks(radius: float) -> CPUParticles3D:
	var p := VfxMat.burst(36, 0.8)
	p.direction = Vector3.UP
	p.spread = 90.0
	p.initial_velocity_min = radius * 2.5
	p.initial_velocity_max = radius * 4.5
	p.gravity = Vector3(0, -14, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.08, 0.08)
	box.material = VfxMat.glow(Color(1.0, 0.75, 0.25), 1.0)
	p.mesh = box
	return p


func _smoke(radius: float) -> CPUParticles3D:
	var p := VfxMat.burst(22, 1.8)
	p.explosiveness = 0.85
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * 0.4
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, 1.2, 0)  # Hot smoke rises.
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.scale_amount_min = radius * 0.35
	p.scale_amount_max = radius * 0.6
	p.scale_amount_curve = VfxMat.grow_curve()
	p.color_ramp = VfxMat.fade_ramp(Color(0.32, 0.29, 0.27), Color(0.15, 0.14, 0.14))
	p.mesh = VfxMat.puff_mesh()
	return p


## Dark scorch decal on the floor, fades out after a few seconds. Lives in the parent so it
## outlasts this node.
func _scorch(radius: float) -> void:
	if _scorch_texture == null:
		var g := Gradient.new()
		g.set_color(0, Color(0, 0, 0, 0.85))
		g.set_color(1, Color(0, 0, 0, 0))
		_scorch_texture = GradientTexture2D.new()
		_scorch_texture.gradient = g
		_scorch_texture.fill = GradientTexture2D.FILL_RADIAL
		_scorch_texture.fill_from = Vector2(0.5, 0.5)
		_scorch_texture.fill_to = Vector2(1.0, 0.5)
		_scorch_texture.width = 128
		_scorch_texture.height = 128
	var d := Decal.new()
	d.texture_albedo = _scorch_texture
	d.modulate = Color(0.12, 0.09, 0.08)
	d.size = Vector3(radius * 1.6, 0.8, radius * 1.6)
	d.upper_fade = 0.1
	d.lower_fade = 0.1
	get_parent().add_child(d)
	d.global_position = Vector3(global_position.x, 0.0, global_position.z)
	d.rotation.y = randf() * TAU
	var t := d.create_tween()
	t.tween_interval(5.0)
	t.tween_property(d, "modulate:a", 0.0, 2.0)
	t.tween_callback(d.queue_free)


func _comic() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var comic := COMIC.new()
	comic.word = WORDS[_word_index % WORDS.size()]
	comic.style = 0
	comic.anchor = global_position + Vector3.UP * 1.5
	_word_index += 1
	layer.add_child(comic)
