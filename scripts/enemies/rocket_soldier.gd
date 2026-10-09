class_name RocketSoldier
extends Human
## The rocket soldier: keeps his distance, kneels, aims, fires. One per wave (WaveSpawner).
## A Human underneath, so dying, being eaten, pinned to a car, ragdolls and kill counts all
## work exactly like any soldier.
##
## Behaviour (state machine on top of Human's movement and obstacle avoidance):
##   APPROACH  run toward the Hulk until within preferred_range with a clear shot
##   KNEEL     drop to one knee (kneel_time)
##   AIM       turn to face him, red aim laser on (aim_time): this is the player's warning
##   FIRE      rocket out, recoil, barrel fire + backblast; then reload_time on the knee
##             and AIM again while he's still in range and in sight
##   STAND     get up (kneel_time) to APPROACH or RETREAT
##   RETREAT   Hulk closer than min_range: run away from him until preferred_range
##
## Animation: retargeted Mixamo run (AnimRetarget) + RocketPose (kneel, twist, recoil,
## launcher on the shoulder, hands locked to the grips by IK). See rocket_pose.gd.

signal fired(rocket: Rocket)

enum Mode { APPROACH, KNEEL, AIM, RELOAD, STAND, RETREAT }

const MODEL := preload("res://assets/base_models/tripo_convert_0ef4d69c-8b8b-4940-88c3-ccca39dd4951.fbx")
const RUN_SOURCE := preload("res://assets/humans/soldier_b_run.fbx")
## Soldier B's planted-foot speed; the rocket soldier's legs are within 3% of B's.
const RUN_SPEED := 3.4

@export_group("Rocket soldier")
## Fires from up to this far (m)...
@export var max_range: float = 20.0
## ...settles in at about this distance...
@export var preferred_range: float = 13.0
## ...and backs off when the Hulk gets closer than this.
@export var min_range: float = 6.0
@export var kneel_time: float = 0.35
## The warning: laser on, then the shot. Shorter = harder to dodge.
@export var aim_time: float = 0.9
## Time on the knee between shots.
@export var reload_time: float = 2.2
## Show the red aim laser while aiming.
@export var show_aim_laser: bool = true

var mode: Mode = Mode.APPROACH
var pose: RocketPose
var _mode_timer: float = 0.0
var _laser: MeshInstance3D
var _sight_query := PhysicsRayQueryParameters3D.new()

static var _run_anim: Animation  # Retargeted once, shared by every rocket soldier.


func _ready() -> void:
	super._ready()
	_sight_query.collision_mask = 1  # World only: walls, pillars, parked cars block the shot.
	gib_material = StandardMaterial3D.new()
	(gib_material as StandardMaterial3D).albedo_color = Color(0.42, 0.45, 0.28)  # Olive drab.
	_build_laser()


## Replaces Human's random soldier with the rocket soldier model, run clip and pose rig.
func _build_model() -> void:
	model = MODEL.instantiate()
	visual.add_child(model)
	if painterly_enabled:
		preload("res://scripts/vfx/character_paint.gd").apply_to(model, paint_style)
	model.rotation.y = PI  # Model faces +Z; Godot forward is -Z.
	_run_speed = RUN_SPEED
	if _run_anim == null:
		var src: Node3D = RUN_SOURCE.instantiate()
		var src_player := SoldierVariants.find_player(src)
		_run_anim = AnimRetarget.retarget(src_player.get_animation(src_player.get_animation_list()[0]), src, model)
		_run_anim.loop_mode = Animation.LOOP_LINEAR
		src.free()
	_ap = AnimationPlayer.new()
	model.add_child(_ap)
	var lib := AnimationLibrary.new()
	lib.add_animation("run", _run_anim)
	_ap.add_animation_library("soldier", lib)
	_ap.play("soldier/run")
	_ap.seek(randf() * _run_anim.length, true)
	var sk := SoldierVariants.find_skeleton(model)
	pose = RocketPose.new()
	pose.name = "RocketPose"
	sk.add_child(pose)
	pose.setup(model)
	if painterly_enabled:
		pose.painterly(paint_style)


func _physics_process(delta: float) -> void:
	if global_position.y < -10.0:
		kill(Vector3.ZERO, KillCause.FELL)
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var desired := Vector3.ZERO
	if target == null or target.health.is_dead:
		_set_mode(Mode.STAND if pose.crouch > 0.0 else Mode.APPROACH)
		target = null
	else:
		desired = _think(delta)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()
	_update_laser()
	_animate()


## Returns the desired ground velocity for this frame.
func _think(delta: float) -> Vector3:
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	var dir := to_target / maxf(dist, 0.01)
	_mode_timer -= delta
	match mode:
		Mode.APPROACH:
			pose.crouch = move_toward(pose.crouch, 0.0, delta / kneel_time)
			_face(to_target, delta)
			if dist < min_range:
				_set_mode(Mode.RETREAT)
			elif dist <= preferred_range and _clear_shot():
				_set_mode(Mode.KNEEL, kneel_time)
			else:
				return _avoid(dir, dist, delta) * _speed
		Mode.RETREAT:
			pose.crouch = move_toward(pose.crouch, 0.0, delta / kneel_time)
			var away := -dir
			_face(away, delta)
			if dist >= preferred_range or (_mode_timer < -4.0 and dist > min_range):
				_set_mode(Mode.APPROACH)  # Far enough (or he's had 4 s to get away).
			return _avoid(away, 20.0, delta) * _speed
		Mode.KNEEL:
			pose.crouch = move_toward(pose.crouch, 1.0, delta / kneel_time)
			_face(to_target, delta)
			if _mode_timer <= 0.0:
				_set_mode(Mode.AIM, aim_time)
		Mode.AIM:
			pose.crouch = 1.0
			_face(to_target, delta)
			if _mode_timer <= 0.0:
				if _clear_shot() and dist <= max_range:
					_fire()
					_set_mode(Mode.RELOAD, reload_time)
				else:
					_set_mode(Mode.STAND, kneel_time)
		Mode.RELOAD:
			_face(to_target, delta)
			if dist < min_range or dist > max_range + 2.0 or not _clear_shot():
				_set_mode(Mode.STAND, kneel_time)
			elif _mode_timer <= 0.0:
				_set_mode(Mode.AIM, aim_time)
		Mode.STAND:
			pose.crouch = move_toward(pose.crouch, 0.0, delta / kneel_time)
			if pose.crouch <= 0.0:
				_set_mode(Mode.RETREAT if dist < min_range else Mode.APPROACH)
	return Vector3.ZERO


func _set_mode(m: Mode, timer: float = 0.0) -> void:
	mode = m
	_mode_timer = timer


## Rocket's path from the muzzle to the Hulk's chest is free of walls, pillars and cars.
func _clear_shot() -> bool:
	if pose == null or pose.muzzle == null:
		return false
	_sight_query.from = global_position + Vector3.UP * 1.2
	_sight_query.to = _aim_point()
	return get_world_3d().direct_space_state.intersect_ray(_sight_query).is_empty()


func _aim_point() -> Vector3:
	return target.global_position + Vector3.UP * 1.6


func _fire() -> void:
	var from := pose.muzzle.global_position
	var rocket := Rocket.launch(get_parent(), from, _aim_point(), self)
	pose.recoil = 1.0
	MuzzleFlash.fire(get_parent(), pose.muzzle, pose.breech)
	fired.emit(rocket)


func _build_laser() -> void:
	_laser = MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.015
	c.bottom_radius = 0.015
	c.height = 1.0
	c.radial_segments = 6
	_laser.mesh = c
	_laser.material_override = VfxMat.glow(Color(1.0, 0.1, 0.05), 0.55)
	_laser.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_laser.top_level = true
	_laser.visible = false
	add_child(_laser)


## Thin red beam from the muzzle to where the rocket will go, only while aiming.
func _update_laser() -> void:
	var on := show_aim_laser and mode == Mode.AIM and target != null and pose.muzzle != null
	_laser.visible = on
	if not on:
		return
	var a := pose.muzzle.global_position
	var b := _aim_point()
	var length := a.distance_to(b)
	_laser.global_transform = Transform3D(Basis.looking_at(b - a, Vector3.UP) * Basis(Vector3.RIGHT, -PI / 2), (a + b) * 0.5)
	_laser.scale = Vector3(1.0, length, 1.0)
	# Pulse so it reads as "about to fire".
	_laser.transparency = 0.3 + 0.3 * sin(Time.get_ticks_msec() * 0.03)


## Run cycle speed follows his ground speed; frozen mid-stride while kneeling (the legs are
## posed by IK then, and a looping hip bob would make him bounce on his knee).
func _animate() -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	if pose.crouch > 0.3 or speed < 0.3:
		_ap.speed_scale = 0.0
	else:
		_ap.speed_scale = clampf(speed / _run_speed, 0.4, max_run_playback)


## Dies like any soldier, but first the rig lets go (the ragdoll needs the bones) and the
## launcher drops as a loose prop.
func kill(launch_velocity: Vector3 = Vector3.ZERO, cause: int = KillCause.UNKNOWN) -> void:
	if not is_in_group("enemies"):
		return
	_release_gear(launch_velocity)
	super.kill(launch_velocity, cause)


func pin_to(carrier: Node3D, cause: int = KillCause.UNKNOWN) -> Node3D:
	if not is_in_group("enemies"):
		return null
	_release_gear(Vector3.ZERO)
	return super.pin_to(carrier, cause)


func _release_gear(launch_velocity: Vector3) -> void:
	_laser.visible = false
	if pose == null:
		return
	pose.shutdown()
	var launcher := pose.launcher
	if launcher == null or not is_instance_valid(launcher):
		return
	# The launcher clatters away as a rubble-style prop (settles, then sinks after a while).
	var body: RubbleChunk = preload("res://scripts/level/rubble_chunk.gd").new()
	body.kill_speed = 1000.0  # A tumbling launcher shouldn't kill anyone.
	body.lifetime = 6.0
	body.mass = 8.0
	get_parent().add_child(body)
	body.global_transform = launcher.global_transform.orthonormalized()
	launcher.reparent(body, true)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.22, 0.25, 1.0) * pose.launcher_scale
	shape.shape = box
	shape.position = Vector3(0, 0.26, 0) * pose.launcher_scale
	body.add_child(shape)
	body.reset_physics_interpolation()
	body.linear_velocity = launch_velocity * 0.6 + Vector3.UP * 3.0
	body.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
