class_name EatSoldier
extends Node
## Grab a soldier, eat him, heal. Child node of the Hulk, a sibling of PunchAttack,
## GroundPound and CarryThrow, built the same way.
##
## Press F (eat). Timeline:
##   REACH  - Picking Up clip. The victim is caught on the press (so he can't wander off
##            or be killed by something else mid-grab), stands frozen, then slides into the
##            Hulk's right hand on the clip's grab frame.
##   LIFT   - rest of Picking Up, the soldier dangling from his fist.
##   EAT    - eating clip. On the chomp frame: blood and gibs from the mouth, +heal_amount HP.
##   then cooldown.
## He's nearly rooted the whole time (~1.9 s) and soldiers keep hitting him: eating is a
## gamble you take when you can afford the hits, not a free heal.

signal grabbed
## Chomp. at = mouth position.
signal eaten(at: Vector3)

enum Phase { READY, REACH, LIFT, EAT, SWALLOW, COOLDOWN }

@export_group("Grab")
## How far (meters, flat) from the Hulk's center a soldier can be grabbed.
@export var eat_range: float = 3.2
## Width of the grab cone in front of him, degrees. Wide: grabbing should feel generous.
@export_range(10.0, 360.0) var arc_degrees: float = 140.0
## How far below the fist the soldier's feet hang (he's held by the scruff of the neck).
@export var hang_drop: float = 1.5

@export_group("Eat")
@export var heal_amount: int = 5
## Seconds after swallowing before he can eat again.
@export var cooldown: float = 3.0
## Movement multiplier while grabbing and eating.
@export_range(0.0, 1.0) var move_while_eating: float = 0.1

var phase: Phase = Phase.READY
var cooldown_remaining: float = 0.0

var _timer: float = 0.0
var _grab_delay: float = 0.0  # Seconds from the press to the grab frame.
var _chomp_delay: float = 0.0  # Seconds from the eat clip start to the chomp frame.
var _victim: Node3D  # The soldier's visual; the soldier himself is already gone (counted as a kill).
var _victim_material: Material
var _slide_from: Vector3
var _slide_t: float = 0.0
var _skeleton: Skeleton3D
var _right_hand: int = -1
var _head: int = -1

@onready var hulk: Hulk = get_parent()


func _ready() -> void:
	(hulk.get_node("Health") as Health).died.connect(_on_hulk_died)
	_skeleton = hulk.get_node("Visual/Model").find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton:
		_right_hand = _skeleton.find_bone("mixamorig_RightHand")
		_head = _skeleton.find_bone("mixamorig_Head")


## True from the grab until he's done swallowing (not during the cooldown).
func is_busy() -> bool:
	return phase != Phase.READY and phase != Phase.COOLDOWN


func _physics_process(delta: float) -> void:
	match phase:
		Phase.READY:
			if Input.is_action_just_pressed("eat"):
				start()
		Phase.REACH:
			_timer -= delta
			if _timer <= 0.0:
				phase = Phase.LIFT
				_slide_t = 0.0
				_slide_from = _victim.global_position if is_instance_valid(_victim) else Vector3.ZERO
				_timer = hulk.animator.pickup_duration() - _grab_delay
		Phase.LIFT:
			_timer -= delta
			if _timer <= 0.0:
				phase = Phase.EAT
				_chomp_delay = hulk.animator.play_eat()
				_timer = _chomp_delay
		Phase.EAT:
			_timer -= delta
			if _timer <= 0.0:
				_chomp()
				phase = Phase.SWALLOW
				_timer = hulk.animator.eat_duration() - _chomp_delay
		Phase.SWALLOW:
			_timer -= delta
			if _timer <= 0.0:
				phase = Phase.COOLDOWN
				cooldown_remaining = cooldown
				hulk.move_speed_multiplier = 1.0
		Phase.COOLDOWN:
			cooldown_remaining = maxf(cooldown_remaining - delta, 0.0)
			if cooldown_remaining <= 0.0:
				phase = Phase.READY



## Grabs the closest soldier in the cone in front of him. Public so tests can call it.
func start() -> bool:
	if phase != Phase.READY or not hulk.can_attack():
		return false
	var target := _find_target()
	if target == null:
		return false
	_victim_material = target.gib_material
	# Caught: counts as a kill now (he yelps), and his body is ours to move.
	_victim = target.pin_to(hulk.get_parent(), KillCause.EATEN)
	if _victim == null:
		return false
	_victim.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_grab_delay = hulk.animator.play_pickup()
	_timer = _grab_delay
	phase = Phase.REACH
	hulk.move_speed_multiplier = move_while_eating
	grabbed.emit()
	return true


func _find_target() -> Human:
	var forward := -hulk.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var min_dot := cos(deg_to_rad(arc_degrees * 0.5))
	var best: Human
	var best_dist := eat_range
	for node in get_tree().get_nodes_in_group("enemies"):
		var human := node as Human
		if human == null:
			continue
		var offset := human.global_position - hulk.global_position
		offset.y = 0.0
		var dist := offset.length()
		if dist > best_dist:
			continue
		if dist > 0.01 and offset.normalized().dot(forward) < min_dot:
			continue
		best = human
		best_dist = dist
	return best


## Visual follow runs every rendered frame (the hand bone animates per frame, not per tick).
func _process(delta: float) -> void:
	if not is_instance_valid(_victim) or _skeleton == null or _right_hand < 0:
		return
	if phase == Phase.LIFT or phase == Phase.EAT:
		var hang := _bone_pos(_right_hand) + Vector3.DOWN * hang_drop
		# Slide into the fist over 0.12 s instead of teleporting.
		_slide_t = minf(_slide_t + delta / 0.12, 1.0)
		_victim.global_position = _slide_from.lerp(hang, _slide_t)


func _chomp() -> void:
	var mouth := _bone_pos(_head) if _head >= 0 else hulk.global_position + Vector3.UP * 3.4
	var director := get_tree().get_first_node_in_group("death_director") as DeathDirector
	if director:
		# Messy eater: gibs spray out of his mouth and rain down.
		director.explode_at(mouth - hulk.global_basis.z * 0.4, -hulk.global_basis.z * 3.0, _victim_material)
	if is_instance_valid(_victim):
		_victim.queue_free()
	_victim = null
	hulk.health.heal(heal_amount)
	eaten.emit(mouth)


func _bone_pos(bone: int) -> Vector3:
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(bone).origin


## Dying mid-meal: the soldier's body drops where it is (cleaned up, not eaten).
func _on_hulk_died() -> void:
	if is_instance_valid(_victim):
		_victim.queue_free()
	_victim = null
	phase = Phase.READY
	cooldown_remaining = 0.0
