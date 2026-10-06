class_name CarryThrow
extends Node
## Lets the Hulk pick up a ThrowableCar and throw it. Child node of the Hulk, a sibling of
## PunchAttack and GroundPound, built the same way.
##
## Controls:
##   E (grab)            - pick up the nearest car in reach. While holding: throw it.
##   Left mouse (punch)  - while holding: throw it.
## Throws go where the Hulk is facing (the mouse), like punches.
##
## Timeline:  LIFT (Overhead Squat clip, rooted) -> CARRY (slow walk) -> THROW windup -> release
## The car is glued to the midpoint of his hand bones the whole time, so it comes up off the
## floor with the lift and leaves his hands on the throw clip's release frame.
## While holding he can't punch or pound (Hulk.can_attack() asks is_busy()).

## Emitted when he grabs a car (start of the lift).
signal lifted
## Emitted when the throw starts (the click), before the car leaves his hands.
signal throw_started

@export_group("Pick up")
## How far (meters, flat) from the Hulk's center a car's center can be and still be grabbed.
## A car is 4.2 m long, so its center is ~2 m from its end: 4 m reaches from beside either end.
@export var pickup_range: float = 4.0
## Seconds for the car to slide from where it sat into his hands at the start of the lift.
@export var grab_snap_time: float = 0.2
## Movement multiplier during the lift. Near zero: lifting a car is a commitment.
@export_range(0.0, 1.0) var lift_move: float = 0.1

@export_group("Carry")
## Movement speed multiplier while carrying.
@export_range(0.1, 1.0) var carry_speed: float = 0.75
## Car underside relative to his hands (m). Slightly negative: hands grip the sills, not the floor pan.
@export var grip_offset: float = -0.15

@export_group("Throw")
## Movement multiplier during the throw windup. He plants his feet to heave.
@export_range(0.0, 1.0) var throw_move: float = 0.3
## Seconds after the release before he can punch, pound, or grab again. Also stops the same
## click that threw the car from starting a punch.
@export var throw_lockout: float = 0.3

var held: ThrowableCar
var _snap_t: float = 0.0
var _snap_from: Transform3D
var _lift_remaining: float = 0.0
var _release_timer: float = -1.0
var _lockout: float = 0.0
var _skeleton: Skeleton3D
var _left_hand: int = -1
var _right_hand: int = -1

@onready var hulk: Hulk = get_parent()


func _ready() -> void:
	# Children are ready before their parent, so Hulk's @onready vars aren't set yet: look Health up directly.
	(hulk.get_node("Health") as Health).died.connect(_on_hulk_died)
	_skeleton = hulk.get_node("Visual/Model").find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton:
		_left_hand = _skeleton.find_bone("mixamorig_LeftHand")
		_right_hand = _skeleton.find_bone("mixamorig_RightHand")


## True while holding a car or just after throwing one.
func is_busy() -> bool:
	return held != null or _lockout > 0.0


## True once the lift has finished and he's not mid-throw.
func can_throw() -> bool:
	return held != null and _lift_remaining <= 0.0 and _release_timer < 0.0


func _physics_process(delta: float) -> void:
	_lockout = maxf(_lockout - delta, 0.0)
	if held == null:
		if Input.is_action_just_pressed("grab"):
			try_pick_up()
		return
	if _lift_remaining > 0.0:
		_lift_remaining -= delta
		if _lift_remaining <= 0.0:
			hulk.move_speed_multiplier = carry_speed
	_follow_hands(delta)
	if _release_timer >= 0.0:
		_release_timer -= delta
		if _release_timer < 0.0:
			_release()
	elif can_throw() and (Input.is_action_just_pressed("grab") or Input.is_action_just_pressed("punch")):
		throw()


## Grabs the nearest car in reach. Public so tests can call it without the keyboard.
func try_pick_up() -> bool:
	if held or _lockout > 0.0 or not hulk.can_attack():
		return false
	var best: ThrowableCar
	var best_dist := pickup_range
	for node in get_tree().get_nodes_in_group("throwables"):
		var car := node as ThrowableCar
		if car == null or not car.can_pick_up():
			continue
		var offset := car.global_position - hulk.global_position
		offset.y = 0.0
		if offset.length() <= best_dist:
			best = car
			best_dist = offset.length()
	if best == null:
		return false
	held = best
	held.pick_up()
	_snap_from = held.global_transform
	_snap_t = 0.0
	_release_timer = -1.0
	_lift_remaining = hulk.animator.play_lift()
	hulk.move_speed_multiplier = lift_move
	lifted.emit()
	return true


## Starts the throw clip. The car actually leaves his hands on the release frame.
func throw() -> void:
	if not can_throw():
		return
	_release_timer = hulk.animator.play_throw()
	hulk.move_speed_multiplier = throw_move
	throw_started.emit()


func _release() -> void:
	var car := held
	held = null
	_release_timer = -1.0
	car.global_transform = _hand_transform()
	car.throw(_forward())
	hulk.move_speed_multiplier = 1.0
	_lockout = throw_lockout


## Car glued to his hands, lying crosswise (its length across his shoulders). For the
## first grab_snap_time it slides from where it was sitting into his grip.
func _follow_hands(delta: float) -> void:
	var target := _hand_transform()
	if _snap_t < 1.0:
		_snap_t = minf(_snap_t + delta / grab_snap_time, 1.0)
		held.global_transform = _snap_from.interpolate_with(target, ease(_snap_t, 0.5))
	else:
		held.global_transform = target


func _hand_transform() -> Transform3D:
	var fwd := _forward()
	# Car's length runs along its local Z; turn it 90 degrees so it lies across his shoulders.
	var basis := Basis.looking_at(fwd, Vector3.UP).rotated(Vector3.UP, PI * 0.5)
	var grip := hulk.global_position + Vector3.UP * 4.2 + fwd * 0.4  # Fallback: no skeleton found.
	if _skeleton and _left_hand >= 0 and _right_hand >= 0:
		var l := _skeleton.global_transform * _skeleton.get_bone_global_pose(_left_hand).origin
		var r := _skeleton.global_transform * _skeleton.get_bone_global_pose(_right_hand).origin
		grip = (l + r) * 0.5
	# Never below the floor, even when his hands are at his feet in the squat.
	var origin := grip + Vector3.UP * grip_offset
	origin.y = maxf(origin.y, 0.0)
	return Transform3D(basis, origin)


func _forward() -> Vector3:
	var f := -hulk.global_basis.z
	f.y = 0.0
	return f.normalized()


## Dying drops the car where it is.
func _on_hulk_died() -> void:
	if held:
		var car := held
		held = null
		_release_timer = -1.0
		car.throw(_forward(), 0.0)
