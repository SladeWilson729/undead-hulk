class_name Rocket
extends Node3D
## A rocket from the rocket soldier's launcher. Built in code: olive body, nose cone, fins,
## a flickering exhaust with a light, and a smoke trail that lingers after it's gone.
##
## Flies straight at speed and checks a ray along each step's movement (so it can't tunnel
## through anything at 18 m/s). Hits the world, the Hulk, or another soldier, then explodes:
##   - Hulk inside the blast: damage from max_damage (centre) down to min_damage (edge)
##   - soldiers inside: killed and thrown outward (friendly fire is part of the fun)
##   - bodies still in the air: blown apart; pillars: smashed; a parked car: shoved
## No hit within max_life seconds: explodes in mid-air.
##
## Collision mask: world (1) + Hulk (2) + soldiers (4). The shooter is excluded.

signal exploded(at: Vector3, hulk_damage: int)
## The rocket came within flyby_distance of the Hulk (once per rocket). Main plays the whoosh.
signal flew_close(at: Vector3)

@export var speed: float = 18.0
@export var max_life: float = 3.0
@export var blast_radius: float = 3.5
@export var max_damage: int = 14
@export var min_damage: int = 4
## Within this distance (m) of the Hulk's chest, the rocket whooshes (flew_close). At 18 m/s,
## 6 m gives about a third of a second of warning before a direct hit.
@export var flyby_distance: float = 6.0
## Launch speed (m/s) given to soldiers caught in the blast, at the centre.
@export var blast_launch: float = 12.0

var shooter: Node3D
var _life: float = 0.0
var _done: bool = false
var _whooshed: bool = false
var _query := PhysicsRayQueryParameters3D.new()
var _exhaust: MeshInstance3D
var _trail: CPUParticles3D


## Spawns a rocket at `from` flying toward `to`.
static func launch(parent: Node, from: Vector3, to: Vector3, owner_body: Node3D) -> Rocket:
	var r := Rocket.new()
	r.shooter = owner_body
	parent.add_child(r)
	r.global_position = from
	r.look_at(to, Vector3.UP)
	r.reset_physics_interpolation()
	r._build()
	return r


func _build() -> void:
	_query.collision_mask = 1 | 2 | 4
	if shooter is CollisionObject3D:
		_query.exclude = [(shooter as CollisionObject3D).get_rid()]
	var olive := StandardMaterial3D.new()
	olive.albedo_color = Color(0.33, 0.36, 0.2)
	olive.roughness = 0.7
	# Body along -Z (the node's forward), 0.5 m long.
	_add_cylinder(0.055, 0.055, 0.42, Vector3(0, 0, 0.0), olive)
	_add_cylinder(0.0, 0.055, 0.16, Vector3(0, 0, -0.29), olive)  # Nose cone.
	var band := StandardMaterial3D.new()
	band.albedo_color = Color(0.85, 0.6, 0.1)
	_add_cylinder(0.057, 0.057, 0.04, Vector3(0, 0, -0.12), band)  # Warning stripe.
	for i in 4:
		var fin := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.012, 0.11, 0.12)
		fin.mesh = b
		fin.material_override = olive
		fin.position = Vector3(0, 0, 0.17)
		fin.rotation.z = i * PI / 2
		fin.translate_object_local(Vector3(0, 0.07, 0))
		add_child(fin)
	# Exhaust: a flickering hot sphere and a light at the tail.
	_exhaust = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.09
	s.height = 0.18
	_exhaust.mesh = s
	_exhaust.material_override = VfxMat.glow(Color(1.0, 0.75, 0.3), 1.0)
	_exhaust.position = Vector3(0, 0, 0.25)
	add_child(_exhaust)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 2.0
	light.omni_range = 3.0
	light.position = Vector3(0, 0, 0.3)
	add_child(light)
	# Smoke trail: world-space puffs left behind, growing and fading.
	_trail = CPUParticles3D.new()
	_trail.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_trail.local_coords = false
	_trail.amount = 70
	_trail.lifetime = 1.2
	_trail.direction = Vector3(0, 0, 1)
	_trail.spread = 12.0
	_trail.initial_velocity_min = 0.5
	_trail.initial_velocity_max = 1.2
	_trail.gravity = Vector3(0, 0.6, 0)
	# Big enough to read from the high gameplay camera; they swell as they age.
	_trail.scale_amount_min = 0.45
	_trail.scale_amount_max = 0.7
	_trail.scale_amount_curve = VfxMat.grow_curve()
	_trail.color_ramp = VfxMat.fade_ramp(Color(0.92, 0.9, 0.86), Color(0.6, 0.58, 0.55))
	_trail.mesh = VfxMat.puff_mesh()
	_trail.position = Vector3(0, 0, 0.3)
	add_child(_trail)


func _add_cylinder(top: float, bottom: float, length: float, at: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = length
	c.radial_segments = 12
	mi.mesh = c
	mi.material_override = mat
	mi.rotation.x = -PI / 2  # Cylinder's +Y (top) points along -Z: the nose leads.
	mi.position = at
	add_child(mi)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_life += delta
	if _exhaust:
		_exhaust.scale = Vector3.ONE * randf_range(0.8, 1.3)
	var from := global_position
	var to := from - global_basis.z * speed * delta
	_query.from = from
	_query.to = to
	var hit := get_world_3d().direct_space_state.intersect_ray(_query)
	if not hit.is_empty():
		_explode(hit.position)
		return
	global_position = to
	if not _whooshed:
		var hulk := get_tree().get_first_node_in_group("player") as Node3D
		if hulk and global_position.distance_to(hulk.global_position + Vector3.UP * 1.5) <= flyby_distance:
			_whooshed = true
			flew_close.emit(global_position)
	if _life >= max_life:
		_explode(global_position)


func _explode(at: Vector3) -> void:
	_done = true
	var damage := 0
	var hulk := get_tree().get_first_node_in_group("player") as Hulk
	if hulk and not hulk.health.is_dead:
		var d := (hulk.global_position + Vector3.UP * 1.5).distance_to(at) - hulk.body_radius
		if d <= blast_radius:
			damage = roundi(lerpf(max_damage, min_damage, clampf(d / blast_radius, 0.0, 1.0)))
			hulk.health.take_damage(damage)
	for node in get_tree().get_nodes_in_group("enemies").duplicate():
		var human := node as Human
		if human == null:
			continue
		var offset := human.global_position + Vector3.UP * 0.9 - at
		if offset.length() <= blast_radius:
			var t := offset.length() / blast_radius
			var away := Vector3(offset.x, 0.0, offset.z).normalized() if Vector2(offset.x, offset.z).length() > 0.05 else Vector3.FORWARD
			human.kill(away * blast_launch * (1.0 - t * 0.5) + Vector3.UP * lerpf(10.0, 5.0, t), KillCause.FRIENDLY_FIRE)
	var director := get_tree().get_first_node_in_group("death_director") as DeathDirector
	if director:
		for corpse in director.airborne_corpses():
			if corpse.get_center().distance_to(at) <= blast_radius:
				corpse.explode()
	for node in get_tree().get_nodes_in_group("breakables"):
		var pillar := node as BreakablePillar
		if pillar and not pillar.broken:
			var to_pillar := pillar.global_position - at
			to_pillar.y = 0.0
			if to_pillar.length() <= blast_radius + pillar.footprint_radius():
				pillar.take_hit(to_pillar, clampf(at.y - pillar.global_position.y, 0.3, pillar.size.y), 0.9)
	for node in get_tree().get_nodes_in_group("throwables"):
		var car := node as ThrowableCar
		if car and car.state == ThrowableCar.State.IDLE:
			var to_car := car.global_position + Vector3.UP * 0.8 - at
			if to_car.length() <= blast_radius + 1.5:
				car.apply_central_impulse((to_car.normalized() + Vector3.UP * 0.6) * car.mass * 3.0)
	# Barrels caught in a soldier's own rocket blast go off, and those kills are on him too.
	for node in get_tree().get_nodes_in_group("smash_props"):
		(node as SmashProp).blasted(at, blast_radius, KillCause.FRIENDLY_FIRE)
	Explosion.spawn(get_parent(), at, blast_radius * 0.85)
	exploded.emit(at, damage)
	# The smoke trail hangs around a moment after the rocket body is gone.
	for child in get_children():
		if child != _trail:
			child.queue_free()
	_trail.emitting = false
	get_tree().create_timer(_trail.lifetime + 0.1).timeout.connect(queue_free)
