class_name MuzzleFlash
extends Node3D
## Launcher barrel fire, built in code. Two parts, spawned together by MuzzleFlash.fire():
##   - front: a flame cone and a white-hot flash ball at the muzzle, plus a light pop
##   - back:  the backblast: a fire cone and a burst of smoke out of the rear of the tube
##            (an AT4-style launcher vents backward; it sells the shot from any angle)
## Both are free-standing in the world (they don't follow the launcher), and free themselves.

## muzzle / breech: the launcher's marker nodes. Flames point along the tube.
static func fire(parent: Node, muzzle: Node3D, breech: Node3D) -> void:
	var forward := (muzzle.global_position - breech.global_position).normalized()
	_flame(parent, muzzle.global_position, forward, 1.1, 0.1, true)
	_flame(parent, breech.global_position, -forward, 0.9, 0.16, false)
	_backblast_smoke(parent, breech.global_position, -forward)


static func _flame(parent: Node, at: Vector3, dir: Vector3, length: float, life: float, with_light: bool) -> void:
	var root := MuzzleFlash.new()
	root.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(root)
	root.global_position = at
	# Point the node's -Z along dir.
	root.look_at(at + dir, Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT)

	var cone := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = 0.22
	c.height = 1.0
	c.radial_segments = 10
	cone.mesh = c
	cone.material_override = VfxMat.glow(Color(1.0, 0.7, 0.2), 0.9)
	cone.rotation.x = -PI / 2  # Cylinder axis (Y) along -Z.
	cone.position.z = -length * 0.5
	cone.scale = Vector3(1.0, length, 1.0)
	root.add_child(cone)

	var core := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.22
	s.height = 0.44
	core.mesh = s
	core.material_override = VfxMat.glow(Color(1.0, 1.0, 0.85), 1.0)
	root.add_child(core)

	if with_light:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.7, 0.35)
		light.light_energy = 5.0
		light.omni_range = 6.0
		root.add_child(light)
		root.create_tween().tween_property(light, "light_energy", 0.0, life * 2.0)

	# Pop out, then pinch away.
	root.scale = Vector3.ONE * 0.4
	var t := root.create_tween()
	t.tween_property(root, "scale", Vector3.ONE * 1.15, life * 0.4).set_ease(Tween.EASE_OUT)
	t.tween_property(root, "scale", Vector3(0.2, 0.2, 1.3), life * 0.6)
	t.tween_callback(root.queue_free)


static func _backblast_smoke(parent: Node, at: Vector3, dir: Vector3) -> void:
	var p := VfxMat.burst(16, 1.1)
	p.direction = dir
	p.spread = 20.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.damping_min = 5.0
	p.damping_max = 7.0
	p.gravity = Vector3(0, 0.8, 0)
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.7
	p.scale_amount_curve = VfxMat.grow_curve()
	p.color_ramp = VfxMat.fade_ramp(Color(0.85, 0.82, 0.78), Color(0.5, 0.48, 0.46))
	p.mesh = VfxMat.puff_mesh()
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	parent.get_tree().create_timer(1.6).timeout.connect(p.queue_free)
