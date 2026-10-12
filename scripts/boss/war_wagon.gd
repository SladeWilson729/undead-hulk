class_name WarWagon
extends CharacterBody3D
## The bridge is flat, so it never falls: no gravity, y stays at 0 (it also drives through the
## end cap with collision off on the way in, which would drop it through the floor otherwise).
##
## Boss phase 1: Deacon Mayhem's armored truck, with the Deacon standing in the bed behind a
## machine gun. Built entirely in code from Will's models (no scene to keep in sync).
##
##   ENTER    - roars in from the far end of the bridge (through the end cap).
##   PATROL   - keeps ~14 m from the Hulk, the Deacon firing bursts at him.
##   REV      - stops, swings to face the Hulk, flashes and revs (the "it's coming" tell).
##   RAM      - floors it in a straight line. Anything in the way gets run down (his own men
##              too). Hitting the Hulk hurts and throws him. Hitting a wall stuns the truck.
##   STUNNED  - smoking, stopped, takes extra damage. The window to unload on it.
##   DEAD     - blows up. The wreck stays as cover; the Deacon is thrown clear (phase 2).
##
## Takes damage through take_boss_hit() from punches, pounds, the charge, thrown cars,
## barrels, flying junk and thrown soldiers (they look for the "boss_targets" group).

signal health_changed(fraction: float)
signal hit_hulk(damage: int)
signal destroyed(at: Vector3)
## A burst of fire started (sound), and each bullet (tracer already drawn).
signal burst_started(at: Vector3)
signal rammed_wall(at: Vector3)
signal revving(at: Vector3)

enum Mode { ENTER, PATROL, REV, RAM, STUNNED, DEAD }

const TRUCK := preload("res://assets/props/armored+vehicle+3d+model.glb")
const DEACON := preload("res://assets/base_models/tattooed+fighter+3d+model.fbx")
const GUN := preload("res://assets/props/machine_gun.glb")
const PUNCH_SOURCE := preload("res://assets/humans/soldier_b_punch.fbx")
const RUN_SOURCE := preload("res://assets/humans/soldier_b_run.fbx")
const ENGINE := preload("res://assets/sound/sound effects/boss-battle-sounds/truck_engine_running_#2-1791518785681.mp3")

@export_group("Toughness")
@export var max_health: float = 300.0
## Damage multiplier while stunned after a wall crash.
@export var stunned_damage_scale: float = 1.5

@export_group("Driving")
## Truck size: the model is 1 unit long, so this is its length in meters.
@export var truck_length: float = 7.0
@export var patrol_speed: float = 8.0
## Distance it tries to keep from the Hulk while shooting.
@export var keep_distance: float = 11.0
@export var turn_rate: float = 2.2
## Seconds between rams (random in this range).
@export var ram_every_min: float = 8.0
@export var ram_every_max: float = 12.0
@export var rev_time: float = 1.1
@export var ram_speed: float = 21.0
@export var ram_distance: float = 34.0
@export var stun_time: float = 2.6

@export_group("Ram")
@export var ram_damage: int = 15
@export var ram_knock: float = 16.0

@export_group("Machine gun")
@export var burst_time: float = 1.2
@export var burst_gap: float = 2.2
@export var bullet_interval: float = 0.11
@export var bullet_damage: int = 1
## Chance a bullet hits him: standing still vs. moving at full speed.
@export_range(0.0, 1.0) var hit_chance_still: float = 0.8
@export_range(0.0, 1.0) var hit_chance_moving: float = 0.45
@export var gun_range: float = 30.0

var mode: Mode = Mode.ENTER
var health: float
var hulk: Hulk
## The end it came in from: +1 east, -1 west.
var side: float = 1.0
var deacon: Node3D  # The gunner model (removed when the truck dies).
var _model: Node3D
var _deacon_pivot: Node3D
var _muzzle: Node3D
var _timer: float = 0.0
var _ram_timer: float = 0.0
var _ram_dir: Vector3
var _ram_travelled: float = 0.0
var _ram_hit: bool = false
var _burst_left: float = 0.0
var _gap_left: float = 1.5
var _bullet_timer: float = 0.0
var _flash: StandardMaterial3D
var _flash_tween: Tween
var _engine: AudioStreamPlayer3D
var _lights: Array[OmniLight3D] = []
var _smoke: CPUParticles3D
var _plowed: Array[PhysicsBody3D] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("boss_targets")
	health = max_health
	collision_layer = 1  # Cover, like the car: soldiers path around it, the Hulk bumps it.
	collision_mask = 0   # Off while driving in through the end cap; on once inside.
	_build()
	_ram_timer = _rng.randf_range(ram_every_min, ram_every_max)
	if hulk == null:
		hulk = get_tree().get_first_node_in_group("player") as Hulk


func _build() -> void:
	_model = TRUCK.instantiate()
	_model.scale = Vector3.ONE * truck_length
	_model.rotation.y = PI  # The model's grille faces +Z; our forward is -Z.
	add_child(_model)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5 * truck_length, 0.36 * truck_length, 0.96 * truck_length)
	shape.shape = box
	shape.position = Vector3(0, box.size.y * 0.5, 0)
	add_child(shape)
	# The Deacon in the bed, behind the cab, turning on a pivot to face the Hulk.
	_deacon_pivot = Node3D.new()
	_deacon_pivot.position = Vector3(0, 0.36 * truck_length * 0.62, 0.22 * truck_length)
	add_child(_deacon_pivot)
	deacon = DEACON.instantiate()
	deacon.scale = Vector3.ONE * 2.4
	deacon.rotation.y = PI
	_deacon_pivot.add_child(deacon)
	_pose_gunner()
	var gun: Node3D = GUN.instantiate()
	gun.scale = Vector3.ONE * 1.8
	gun.position = Vector3(0.0, 1.35, -0.75)
	_deacon_pivot.add_child(gun)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0.0, 1.5, -1.7)
	_deacon_pivot.add_child(_muzzle)
	# Headlights: flash on the rev.
	for x in [-1.0, 1.0]:
		var light := OmniLight3D.new()
		light.position = Vector3(x * 0.17 * truck_length, 0.16 * truck_length, -0.5 * truck_length)
		light.light_color = Color(1.0, 0.85, 0.5)
		light.omni_range = 6.0
		light.light_energy = 0.0
		add_child(light)
		_lights.append(light)
	_engine = AudioStreamPlayer3D.new()
	var loop := ENGINE.duplicate() as AudioStreamMP3
	if loop:
		loop.loop = true
		_engine.stream = loop
	_engine.bus = &"SFX"
	_engine.unit_size = 20.0
	_engine.volume_db = -6.0
	add_child(_engine)
	if DisplayServer.get_name() != "headless":
		_engine.play()


## Freezes the Deacon in a guard pose (soldier punch clip, retargeted) so his arms come
## forward onto the gun instead of hanging in a T-pose. Phase 2 gets his own animations.
func _pose_gunner() -> void:
	var src: Node3D = RUN_SOURCE.instantiate()
	var lib: AnimationLibrary = PUNCH_SOURCE
	var clip := lib.get_animation(lib.get_animation_list()[0])
	var anim := AnimRetarget.retarget(clip, src, deacon)
	src.free()
	var ap := AnimationPlayer.new()
	deacon.add_child(ap)
	var l := AnimationLibrary.new()
	l.add_animation("guard", anim)
	ap.add_animation_library("deacon", l)
	ap.play("deacon/guard")
	ap.seek(0.2, true)
	ap.pause()


func _physics_process(delta: float) -> void:
	if mode == Mode.DEAD:
		return
	if hulk == null or hulk.health.is_dead:
		velocity = velocity.move_toward(Vector3.ZERO, 20.0 * delta)
		move_and_slide()
		return
	_aim_gunner(delta)
	match mode:
		Mode.ENTER:
			_drive_toward(Vector3(side * 26.0, 0, 0), patrol_speed * 1.6, delta)
			if collision_mask == 0 and absf(global_position.x) < 35.0:
				collision_mask = 1
			if absf(global_position.x - side * 26.0) < 2.0:
				mode = Mode.PATROL
		Mode.PATROL:
			var goal_x := clampf(hulk.global_position.x + keep_distance * signf(global_position.x - hulk.global_position.x + 0.001), -33.0, 33.0)
			var goal := Vector3(goal_x, 0, clampf(hulk.global_position.z * 0.3, -1.5, 1.5))
			if global_position.distance_to(goal) > 2.0:
				_drive_toward(goal, patrol_speed, delta)
			else:
				_brake(delta)
			_gun(delta)
			_ram_timer -= delta
			if _ram_timer <= 0.0:
				_start_rev()
		Mode.REV:
			_brake(delta)
			var to := hulk.global_position - global_position
			to.y = 0.0
			_turn_toward(to, turn_rate * 2.5, delta)
			var flash := 1.0 if fmod(_timer, 0.2) < 0.1 else 0.2
			for l in _lights:
				l.light_energy = flash * 6.0
			_timer -= delta
			if _timer <= 0.0:
				_start_ram()
		Mode.RAM:
			velocity = _ram_dir * ram_speed
			_plow_ahead(delta)
			var before := global_position
			move_and_slide()
			_ram_travelled += (global_position - before).length()
			_run_over()
			if _hit_wall():
				_crash()
			elif _ram_travelled >= ram_distance:
				_end_ram()
			return
		Mode.STUNNED:
			_brake(delta)
			_timer -= delta
			if _timer <= 0.0:
				_smoke.emitting = false
				mode = Mode.PATROL
				_ram_timer = _rng.randf_range(ram_every_min, ram_every_max)
	move_and_slide()
	if _engine.playing:
		_engine.pitch_scale = 0.8 + clampf(velocity.length() / ram_speed, 0.0, 1.0) * 0.6


func forward() -> Vector3:
	var f := -global_basis.z
	f.y = 0.0
	return f.normalized()


func _drive_toward(goal: Vector3, speed: float, delta: float) -> void:
	var to := goal - global_position
	to.y = 0.0
	_turn_toward(to, turn_rate, delta)
	# Ease off when the turn is sharp: trucks don't strafe.
	var align := maxf(forward().dot(to.normalized()), 0.25)
	var target_v := forward() * speed * align
	velocity = velocity.move_toward(Vector3(target_v.x, 0.0, target_v.z), 18.0 * delta)


func _brake(delta: float) -> void:
	velocity = velocity.move_toward(Vector3.ZERO, 22.0 * delta)


func _turn_toward(dir: Vector3, rate: float, delta: float) -> void:
	if dir.length_squared() < 0.01:
		return
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = rotate_toward(rotation.y, target_yaw, rate * delta)


func _aim_gunner(delta: float) -> void:
	if deacon == null or hulk == null:
		return
	var to := hulk.global_position - _deacon_pivot.global_position
	to.y = 0.0
	if to.length_squared() < 0.01:
		return
	var yaw := atan2(-to.x, -to.z)
	_deacon_pivot.global_rotation.y = rotate_toward(_deacon_pivot.global_rotation.y, yaw, 4.0 * delta)


## Machine gun: bursts with gaps. Each bullet is a hitscan line with a tracer. The first of
## his own soldiers standing in the line takes it instead (Friendly Fire).
func _gun(delta: float) -> void:
	if deacon == null:
		return
	if _burst_left <= 0.0:
		_gap_left -= delta
		if _gap_left <= 0.0:
			var dist := hulk.global_position.distance_to(global_position)
			if dist <= gun_range:
				_burst_left = burst_time
				_bullet_timer = 0.0
				burst_started.emit(_muzzle.global_position)
			_gap_left = burst_gap
		return
	_burst_left -= delta
	_bullet_timer -= delta
	while _bullet_timer <= 0.0 and _burst_left > 0.0:
		_bullet_timer += bullet_interval
		_fire_bullet()


func _fire_bullet() -> void:
	var from := _muzzle.global_position
	var target := hulk.global_position + Vector3.UP * 1.6
	var moving := clampf(Vector2(hulk.velocity.x, hulk.velocity.z).length() / hulk.move_speed, 0.0, 1.0)
	var chance := lerpf(hit_chance_still, hit_chance_moving, moving)
	var hits := _rng.randf() < chance
	if not hits:
		target += Vector3(_rng.randf_range(-2.0, 2.0), _rng.randf_range(-1.4, -0.2), _rng.randf_range(-2.0, 2.0))
	# His own men in the line of fire.
	var seg := target - from
	var victim: Human = null
	var best := 1.0
	for node in get_tree().get_nodes_in_group("enemies"):
		var h := node as Human
		if h == null or h.is_in_group("boss"):  # Not by class: that would loop the script dependencies.
			continue
		var c := h.global_position + Vector3.UP * 1.0
		var t := clampf((c - from).dot(seg) / seg.length_squared(), 0.0, 1.0)
		if t < best and (from + seg * t).distance_to(c) < 0.6:
			best = t
			victim = h
	if victim:
		target = victim.global_position + Vector3.UP * 1.0
		victim.kill(seg.normalized() * 6.0 + Vector3.UP * 3.0, KillCause.FRIENDLY_FIRE)
	elif hits:
		hulk.health.take_damage(bullet_damage)
		hit_hulk.emit(bullet_damage)
	_tracer(from, target)


func _tracer(from: Vector3, to: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	var length := from.distance_to(to)
	box.size = Vector3(0.06, 0.06, length)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.85, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	get_parent().add_child(mi)
	mi.global_transform = Transform3D(Basis.looking_at(to - from), from.lerp(to, 0.5))
	var t := mi.create_tween()
	t.tween_property(mat, "albedo_color:a", 0.0, 0.08)
	t.tween_callback(mi.queue_free)


func _start_rev() -> void:
	mode = Mode.REV
	_timer = rev_time
	revving.emit(global_position)


func _start_ram() -> void:
	mode = Mode.RAM
	var to := hulk.global_position - global_position
	to.y = 0.0
	_ram_dir = to.normalized() if to.length() > 0.5 else forward()
	rotation.y = atan2(-_ram_dir.x, -_ram_dir.z)
	_ram_travelled = 0.0
	_ram_hit = false
	for l in _lights:
		l.light_energy = 4.0


func _end_ram() -> void:
	mode = Mode.PATROL
	_ram_timer = _rng.randf_range(ram_every_min, ram_every_max)
	velocity = _ram_dir * ram_speed * 0.4
	_unplow()
	for l in _lights:
		l.light_energy = 0.0


func _crash() -> void:
	mode = Mode.STUNNED
	_timer = stun_time
	velocity = -_ram_dir * 2.0
	_unplow()
	for l in _lights:
		l.light_energy = 0.0
	_ensure_smoke()
	_smoke.emitting = true
	rammed_wall.emit(global_position + forward() * truck_length * 0.5 + Vector3.UP * 1.5)


## Running people (and the Hulk) down. The front half of the truck is the danger zone.
func _run_over() -> void:
	var half_w := 0.25 * truck_length + 0.5
	var f := forward()
	var right := f.cross(Vector3.UP)
	for node in get_tree().get_nodes_in_group("enemies").duplicate():
		var h := node as Human
		if h == null or h.is_in_group("boss"):  # Not by class: that would loop the script dependencies.
			continue
		var off := h.global_position - global_position
		var along := off.dot(f)
		if along > -0.1 * truck_length and along < 0.55 * truck_length and absf(off.dot(right)) < half_w:
			h.kill(f * ram_speed * 0.8 + right * signf(off.dot(right)) * 6.0 + Vector3.UP * 7.0, KillCause.FRIENDLY_FIRE)
	if not _ram_hit:
		var off := hulk.global_position - global_position
		var along := off.dot(f)
		if along > -0.1 * truck_length and along < 0.5 * truck_length + hulk.body_radius and absf(off.dot(right)) < half_w + hulk.body_radius * 0.5:
			_ram_hit = true
			hulk.health.take_damage(ram_damage)
			# Always shoved toward the open rail: a ram puts him near the edge, the next one
			# (if he stays there, under the EDGE! warning) throws him over.
			hulk.boss_knock((Vector3(0, 0, 1) * 0.7 + f * 0.5).normalized() * ram_knock + Vector3.UP * 6.0)
			hit_hulk.emit(ram_damage)


## Pillars, junk and the parked car in its path get smashed out of the way.
func _plow_ahead(delta: float) -> void:
	var ahead := 0.5 * truck_length + ram_speed * delta * 2.0 + 0.5
	var f := forward()
	for node in get_tree().get_nodes_in_group("breakables"):
		var pillar := node as BreakablePillar
		if pillar == null or pillar.broken:
			continue
		var to := pillar.global_position - global_position
		to.y = 0.0
		if to.dot(f) > 0.0 and to.length() <= ahead + pillar.footprint_radius() and absf(to.dot(f.cross(Vector3.UP))) < 0.25 * truck_length + pillar.footprint_radius():
			pillar.take_hit(f, 1.2, 1.4)
			add_collision_exception_with(pillar)
			_plowed.append(pillar)
	for node in get_tree().get_nodes_in_group("smash_props"):
		var prop := node as SmashProp
		if prop == null or prop.state == SmashProp.State.GONE:
			continue
		var to := prop.global_position - global_position
		to.y = 0.0
		if to.dot(f) > 0.0 and to.length() <= ahead + 0.5 and absf(to.dot(f.cross(Vector3.UP))) < 0.25 * truck_length + 0.6:
			prop.punch_from(global_position, f, 1.2)
			prop.truck_spent = true  # Junk it shoves aside doesn't count as hitting it.
	for node in get_tree().get_nodes_in_group("throwables"):
		var car := node as ThrowableCar
		if car == null or not car.can_pick_up():
			continue
		var to := car.global_position - global_position
		to.y = 0.0
		if to.dot(f) > 0.0 and to.length() <= ahead + 2.0 and absf(to.dot(f.cross(Vector3.UP))) < 0.25 * truck_length + 1.2:
			car.throw(f, 0.9)
			car.truck_spent = true  # Its own shove doesn't hurt it.


func _unplow() -> void:
	for b in _plowed:
		if is_instance_valid(b):
			remove_collision_exception_with(b)
	_plowed.clear()


func _hit_wall() -> bool:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		if absf(n.y) > 0.6:
			continue
		if Vector3(n.x, 0, n.z).normalized().dot(_ram_dir) <= -0.5:
			return true
	return false


## Hits every live truck whose body is within `radius` (flat, from `at` to the nearest point
## of its footprint, roughly). For blasts, pounds and flying things. Returns the total dealt.
static func hit_near(tree: SceneTree, at: Vector3, radius: float, amount: float, source: String) -> float:
	var total := 0.0
	for node in tree.get_nodes_in_group("boss_targets"):
		var w := node as WarWagon
		if w == null or not w.is_alive():
			continue
		if w.footprint_distance(at) <= radius:
			total += w.take_boss_hit(amount, source)
	return total


## Flat distance from a point to the truck's footprint (0 inside it).
func footprint_distance(point: Vector3) -> float:
	var local := global_transform.affine_inverse() * point
	var hx := 0.25 * truck_length
	var hz := 0.48 * truck_length
	var dx := maxf(absf(local.x) - hx, 0.0)
	var dz := maxf(absf(local.z) - hz, 0.0)
	return Vector2(dx, dz).length()


## Every damage source calls this. Returns the damage actually dealt.
func take_boss_hit(amount: float, _source: String = "") -> float:
	if mode == Mode.DEAD or mode == Mode.ENTER:
		return 0.0
	if mode == Mode.STUNNED:
		amount *= stunned_damage_scale
	health = maxf(health - amount, 0.0)
	_flash_hit()
	health_changed.emit(health / max_health)
	if health <= 0.0:
		_die()
	return amount


func is_alive() -> bool:
	return mode != Mode.DEAD


func _flash_hit() -> void:
	if _flash == null:
		_flash = StandardMaterial3D.new()
		_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash.albedo_color = Color(1, 1, 1, 0)
		for m in _model.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).material_overlay = _flash
	if _flash_tween:
		_flash_tween.kill()
	_flash.albedo_color = Color(1, 1, 1, 0.6)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "albedo_color:a", 0.0, 0.15)


func _die() -> void:
	mode = Mode.DEAD
	velocity = Vector3.ZERO
	_unplow()
	var at := global_position + Vector3.UP * 1.5
	for l in _lights:
		l.light_energy = 0.0
	_engine.stop()
	# Burnt-out wreck: dark overlay, smoke, stays as cover.
	if _flash_tween:
		_flash_tween.kill()
	if _flash == null:
		_flash_hit()
	_flash.albedo_color = Color(0.05, 0.04, 0.03, 0.7)
	_ensure_smoke()
	_smoke.amount = 40
	_smoke.emitting = true
	# The gunner is gone from the truck; the Finale puts the real Deacon on the ground.
	if deacon:
		_deacon_pivot.queue_free()
		deacon = null
	destroyed.emit(at)


func gunner_position() -> Vector3:
	return _deacon_pivot.global_position if is_instance_valid(_deacon_pivot) else global_position + Vector3.UP * 3.0


func _ensure_smoke() -> void:
	if _smoke:
		return
	_smoke = CPUParticles3D.new()
	_smoke.amount = 24
	_smoke.lifetime = 2.0
	_smoke.emitting = false
	_smoke.position = Vector3(0, 0.36 * truck_length, -0.3 * truck_length)
	_smoke.direction = Vector3.UP
	_smoke.spread = 25.0
	_smoke.initial_velocity_min = 1.5
	_smoke.initial_velocity_max = 3.0
	_smoke.gravity = Vector3(0, 0.6, 0)
	_smoke.scale_amount_min = 1.2
	_smoke.scale_amount_max = 2.4
	var mesh := SphereMesh.new()
	mesh.radius = 0.4
	mesh.height = 0.8
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.15, 0.15, 0.15, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	_smoke.mesh = mesh
	add_child(_smoke)
