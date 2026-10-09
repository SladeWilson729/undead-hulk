class_name NinjaSoldier
extends Human
## The ninja: a fast hit-and-run skirmisher with two katanas. One per wave (WaveSpawner).
## A Human underneath, so dying, being eaten, pinned to a car, ragdolls and kill counts all
## work exactly like any soldier. Still dies in one hit: the trick is catching her.
##
## Behaviour:
##   STALK    run in to stalk_range, then circle the Hulk for a moment, looking for an opening
##   POUNCE   flip kick: a flying somersault that carries her over the crowd and lands a heel
##            on the Hulk (flip_damage). Her body is steered from where she jumped to a spot
##            right in front of him, so the jump length fits the gap.
##   SLASH    two-katana combo while she's in his face: 3 cuts, slash_damage each.
##            She's rooted for the whole combo: THIS is the window to punch her.
##   RETREAT  sprint back out to stalk_range, then STALK again.
##
## Visibility: smoke afterimages trail her while she's fast (AfterimageTrail), so the player
## can follow a dark ninja across a dark floor.
##
## Animation: Mixamo clips on her own skeleton (rigged in Mixamo), so no retargeting.
## Run (loop), Flip Kick, Two Hand Club Combo. The katanas ride her hand bones.

## Emitted when one of her attacks lands on the Hulk. Main plays the hit sound and shake.
signal struck(at: Vector3, damage: int)

enum Mode { STALK, POUNCE, SLASH, RETREAT, IDLE }

const MODEL := preload("res://assets/humans/ninja/Run.fbx")
const FLIP_LIB := preload("res://assets/humans/ninja/Flip Kick.fbx")
const SLASH_LIB := preload("res://assets/humans/ninja/Two Hand Club Combo.fbx")
const KATANA := preload("res://assets/humans/ninja/katana.glb")
## Planted-foot speed of her Run clip at 1x (measured): playback scales from this.
const RUN_SPEED := 4.1

## Clip moments, in the CLIP's own seconds (measured from the files).
const FLIP_TAKEOFF := 0.45   # Feet leave the floor.
const FLIP_LAND := 1.45      # Feet back down.
const FLIP_STRIKE := 1.35    # Heel comes down.
const FLIP_DONE := 1.85      # Out of the landing crouch.
const SLASH_HITS: Array[float] = [0.85, 1.6, 2.25]  # The three cuts (blade speed peaks).

@export_group("Ninja")
## Circles the Hulk at about this distance while looking for an opening.
@export var stalk_range: float = 6.5
## Seconds spent circling before she pounces (random in this range).
@export var stalk_time_min: float = 1.0
@export var stalk_time_max: float = 2.4
## She only pounces from this band of distances.
@export var pounce_min: float = 2.5
@export var pounce_max: float = 9.0
@export var flip_damage: int = 4
@export var slash_damage: int = 2
## How far past touching distance her heel and blades reach.
@export var strike_reach: float = 1.0
## Playback speed of the attack clips (Mixamo's are a bit stately for a ninja).
@export var flip_speed: float = 1.25
@export var slash_speed: float = 1.3
## Seconds she sprints away after a combo before circling again.
@export var retreat_time: float = 1.4

@export_group("Katanas")
## The katana file is 1 m long; she's about 1.55 m tall.
@export var katana_scale: float = 0.85
## Where along the katana (fraction of its length, from the pommel) her fist closes.
@export_range(0.0, 0.3) var grip_point: float = 0.13
## Splay the two blades apart a little so they don't sit on top of each other mid-swing.
@export var blade_splay_degrees: float = 12.0

var mode: Mode = Mode.STALK
var _mode_timer: float = 0.0
var _hits_done: int = 0
var _jump_from: Vector3
var _jump_to: Vector3
var _sight_query := PhysicsRayQueryParameters3D.new()
var _normal_mask: int
## Smoke afterimages (scripts/vfx/afterimage_trail.gd).
var trail: AfterimageTrail

static var _library: AnimationLibrary  # Built once, shared by every ninja.


func _ready() -> void:
	super._ready()
	_normal_mask = collision_mask
	_sight_query.collision_mask = 1
	gib_material = StandardMaterial3D.new()
	(gib_material as StandardMaterial3D).albedo_color = Color(0.17, 0.2, 0.3)  # Navy.
	_set_mode(Mode.STALK, randf_range(stalk_time_min, stalk_time_max))


## Replaces Human's random soldier with the ninja, her clips and her katanas.
func _build_model() -> void:
	model = MODEL.instantiate()
	visual.add_child(model)
	model.rotation.y = PI  # Mixamo faces +Z; Godot forward is -Z.
	_run_speed = RUN_SPEED
	_ap = SoldierVariants.find_player(model)
	if _library == null:
		_library = AnimationLibrary.new()
		_library.add_animation("run", SoldierVariants._prepare(_ap.get_animation(_ap.get_animation_list()[0]), true))
		_library.add_animation("flip", SoldierVariants._prepare(_first(FLIP_LIB), false))
		_library.add_animation("slash", SoldierVariants._prepare(_first(SLASH_LIB), false))
	_ap.add_animation_library("ninja", _library)
	_ap.play("ninja/run")
	_ap.seek(randf() * _ap.current_animation_length, true)
	var sk := SoldierVariants.find_skeleton(model)
	_add_katana(sk, "Right")
	_add_katana(sk, "Left")
	# Paint after the katanas are on, so the blades get the same painterly look.
	if painterly_enabled:
		preload("res://scripts/vfx/character_paint.gd").apply_to(model, paint_style)
	# Smoke afterimages while she's moving fast (and always during the flip), so the player
	# can track her. Tune on the Afterimages node: interval, lifetime, min_speed, colors.
	trail = AfterimageTrail.new()
	trail.name = "Afterimages"
	add_child(trail)
	trail.setup(model)


static func _first(lib: AnimationLibrary) -> Animation:
	return lib.get_animation(lib.get_animation_list()[0])


## A katana in the fist. Hand bone axes (Mixamo): +Y runs to the fingers, the knuckle line runs
## along X (index finger at +X on the right hand, -X on the left), palm faces +Z.
## A closed fist wraps across the knuckle line, so the blade lies along X, out past the index
## finger and thumb.
func _add_katana(sk: Skeleton3D, side: String) -> void:
	var bone := "mixamorig_%sHand" % side
	if sk.find_bone(bone) < 0:
		return
	var attach := BoneAttachment3D.new()
	attach.bone_name = bone
	attach.name = "%sKatana" % side
	sk.add_child(attach)
	var out := 1.0 if side == "Right" else -1.0
	var blade := Vector3(out, 0, 0)  # Katana +Y goes here.
	var edge := Vector3(0, 1, 0)     # Katana +Z (edge side) leads toward the curled fingertips.
	var basis := Basis(blade.cross(edge), blade, edge)
	basis = basis.rotated(Vector3(0, 1, 0), deg_to_rad(blade_splay_degrees) * out)
	basis = basis.scaled(Vector3.ONE * katana_scale)
	# The fist: halfway between the index and ring knuckles, just short of them, toward the palm.
	var fist := Vector3(0.014 * out, 0.085, 0.025)
	var katana: Node3D = KATANA.instantiate()
	katana.transform = Transform3D(basis, fist - basis * Vector3(0, grip_point, 0))
	attach.add_child(katana)


func _physics_process(delta: float) -> void:
	if global_position.y < -10.0:
		kill()
		return
	if target == null or target.health.is_dead:
		target = null
		if mode != Mode.IDLE:
			_end_pounce()
			_set_mode(Mode.IDLE)
	if mode == Mode.POUNCE:
		_pounce(delta)
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var desired := Vector3.ZERO if mode == Mode.IDLE else _think(delta)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()
	_animate()


## Desired ground velocity for this frame.
func _think(delta: float) -> Vector3:
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	var dir := to_target / maxf(dist, 0.01)
	var contact := target.body_radius + BODY_RADIUS + attack_reach
	_mode_timer -= delta
	match mode:
		Mode.STALK:
			_play("ninja/run")
			if dist > stalk_range + 1.0:
				_face(to_target, delta)
				return _avoid(dir, dist - stalk_range, delta) * _speed
			# Circle him, drifting back toward stalk_range.
			var tangent := Vector3(-dir.z, 0.0, dir.x) * _flank_side
			var move := (tangent + dir * clampf((dist - stalk_range) * 0.6, -1.0, 1.0)).normalized()
			_face(move, delta)
			if _mode_timer <= 0.0 and dist >= pounce_min and dist <= pounce_max and _clear_line():
				_start_pounce(dist, dir, contact)
				return Vector3.ZERO
			return _avoid(move, 3.0, delta) * _speed
		Mode.SLASH:
			_face(to_target, delta)
			var pos := _ap.current_animation_position
			if _hits_done < SLASH_HITS.size() and pos >= SLASH_HITS[_hits_done]:
				_hits_done += 1
				_strike(slash_damage, dist, contact)
			if not _ap.is_playing() or pos >= _ap.current_animation_length - 0.05:
				_set_mode(Mode.RETREAT, retreat_time)
				_flank_side = -_flank_side  # Come back around from the other side.
				return Vector3.ZERO
			# Shuffle in if he's drifted out of sword reach.
			return dir * 2.0 if dist > contact + 0.3 else Vector3.ZERO
		Mode.RETREAT:
			_play("ninja/run")
			_face(-to_target, delta)
			if dist >= stalk_range or _mode_timer <= 0.0:
				_set_mode(Mode.STALK, randf_range(stalk_time_min, stalk_time_max))
			return _avoid(-dir, 20.0, delta) * _speed
	return Vector3.ZERO


func _start_pounce(dist: float, dir: Vector3, contact: float) -> void:
	_set_mode(Mode.POUNCE)
	_hits_done = 0
	_jump_from = global_position
	_jump_to = global_position + dir * maxf(dist - contact, 0.0)
	rotation.y = atan2(-dir.x, -dir.z)
	# In the air she sails over the crowd: collide with the world only.
	collision_mask = 1
	trail.burst = true  # Trail the whole flip, even the slow takeoff and landing.
	_ap.play("ninja/flip", 0.08)
	_ap.speed_scale = flip_speed


## The flight is steered by code: the clip's own hips are pinned, and her body slides from
## _jump_from to _jump_to between takeoff and landing, eased so it reads as one arc.
func _pounce(delta: float) -> void:
	var pos := _ap.current_animation_position
	var t := clampf(inverse_lerp(FLIP_TAKEOFF, FLIP_LAND, pos), 0.0, 1.0)
	var goal := _jump_from.lerp(_jump_to, smoothstep(0.0, 1.0, t))
	var step := goal - global_position
	velocity = Vector3(step.x / delta, 0.0, step.z / delta)
	move_and_slide()
	if _hits_done == 0 and pos >= FLIP_STRIKE and target:
		_hits_done = 1
		var flat := target.global_position - global_position
		flat.y = 0.0
		_strike(flip_damage, flat.length(), target.body_radius + BODY_RADIUS + attack_reach)
	if pos >= FLIP_LAND:
		collision_mask = _normal_mask
	if pos >= FLIP_DONE or not _ap.is_playing():
		_end_pounce()
		velocity = Vector3.ZERO
		if target == null:
			_set_mode(Mode.IDLE)
			return
		var flat2 := target.global_position - global_position
		flat2.y = 0.0
		if flat2.length() <= target.body_radius + BODY_RADIUS + attack_reach + strike_reach:
			_set_mode(Mode.SLASH)
			_hits_done = 0
			_ap.play("ninja/slash", 0.1)
			_ap.speed_scale = slash_speed
		else:
			_set_mode(Mode.RETREAT, retreat_time * 0.5)


func _end_pounce() -> void:
	collision_mask = _normal_mask
	if trail:
		trail.burst = false


func _strike(damage_amount: int, dist: float, contact: float) -> void:
	if target == null or target.health.is_dead or dist > contact + strike_reach:
		return
	target.health.take_damage(damage_amount)
	struck.emit(target.global_position + Vector3.UP * 1.5, damage_amount)


## World-only line from her to him: no pouncing through walls, pillars or a parked car.
func _clear_line() -> bool:
	_sight_query.from = global_position + Vector3.UP * 1.0
	_sight_query.to = target.global_position + Vector3.UP * 1.0
	return get_world_3d().direct_space_state.intersect_ray(_sight_query).is_empty()


func _play(anim: String) -> void:
	if _ap.current_animation != anim:
		_ap.play(anim, anim_blend)


func _animate() -> void:
	# The attack clips run at their own fixed speed (set when they start).
	if mode == Mode.SLASH or mode == Mode.POUNCE:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	_ap.speed_scale = 0.0 if speed < 0.3 else clampf(speed / _run_speed, 0.4, max_run_playback)


func _set_mode(m: Mode, timer: float = 0.0) -> void:
	mode = m
	_mode_timer = timer


func kill(launch_velocity: Vector3 = Vector3.ZERO) -> void:
	_end_pounce()
	super.kill(launch_velocity)


func pin_to(carrier: Node3D) -> Node3D:
	_end_pounce()
	return super.pin_to(carrier)
