class_name ConfettiBurst
extends Node3D
## A party-popper burst of confetti: bright paper flecks that pop out, flutter and drift down,
## plus a quick white flash. Used by the Glitter Bomb augment instead of gore.
## Spawn with ConfettiBurst.spawn(parent, position, velocity). Frees itself.

const COLORS := [
	Color(1.0, 0.25, 0.45), Color(1.0, 0.8, 0.15), Color(0.25, 0.85, 0.45),
	Color(0.25, 0.6, 1.0), Color(0.8, 0.35, 1.0), Color(1.0, 0.55, 0.15),
]

static var _mesh: QuadMesh


static func spawn(parent: Node, at: Vector3, inherit_velocity: Vector3 = Vector3.ZERO) -> ConfettiBurst:
	var c := ConfettiBurst.new()
	parent.add_child(c)
	c.global_position = at
	c._build(inherit_velocity)
	return c


func _build(inherit_velocity: Vector3) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if _mesh == null:
		_mesh = QuadMesh.new()
		_mesh.size = Vector2(0.12, 0.07)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mesh.material = m
	# One burst per colour so each fleck keeps a solid colour all the way down.
	for col in COLORS:
		var p := VfxMat.burst(14, 2.2)
		p.mesh = _mesh
		p.color = col
		p.direction = Vector3.UP
		p.spread = 80.0
		p.initial_velocity_min = 4.0
		p.initial_velocity_max = 9.0
		p.gravity = Vector3(0, -4.0, 0)  # Paper falls slowly.
		p.damping_min = 2.5
		p.damping_max = 4.0
		p.angular_velocity_min = -720.0
		p.angular_velocity_max = 720.0
		p.angle_min = 0.0
		p.angle_max = 360.0
		p.scale_amount_min = 0.8
		p.scale_amount_max = 1.6
		p.particle_flag_rotate_y = true
		add_child(p)
		p.global_position = global_position + inherit_velocity * 0.02
		p.emitting = true
	# Flash.
	var flash := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.6
	s.height = 1.2
	flash.mesh = s
	var mat := VfxMat.glow(Color(1.0, 1.0, 0.9), 0.85)
	flash.material_override = mat
	add_child(flash)
	var t := create_tween()
	t.tween_property(flash, "scale", Vector3.ONE * 1.8, 0.12)
	t.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.18)
	t.tween_callback(flash.queue_free)
	get_tree().create_timer(2.6).timeout.connect(queue_free)
