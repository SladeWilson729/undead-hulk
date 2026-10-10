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
##
## Or throw him: click (punch) any time before the chomp and he hurls the soldier where he's
## aiming instead. No heal, but the body is a missile: it flattens up to `throw_max_hits`
## soldiers it flies through (all counted as Yeeted, him included). Clicking during the reach
## queues the throw for the moment the soldier is in his hand.

signal grabbed
## Chomp. at = mouth position.
signal eaten(at: Vector3)
## The throw started (the click). For the voice.
signal throw_started
## The soldier left his hand as a missile.
signal thrown(body: Node3D)
## A thrown soldier flattened another one.
signal yeet_hit(at: Vector3)

enum Phase { READY, REACH, LIFT, EAT, SWALLOW, THROW, COOLDOWN }

const FLYING_BODY := preload("res://scenes/enemies/flying_body.tscn")

@export_group("Grab")
## How far (meters, flat) from the Hulk's center a soldier can be grabbed.
@export var eat_range: float = 3.2
## Width of the grab cone in front of him, degrees. Wide: grabbing should feel generous.
@export_range(10.0, 360.0) var arc_degrees: float = 140.0
## How far below the fist the soldier's feet hang (he's held by the scruff of the neck).
@export var hang_drop: float = 1.5

@export_group("Eat")
## HP back per soldier eaten. Raised from 5 after playtesting: deep waves were a slow bleed out.
@export var heal_amount: int = 10
## Seconds after swallowing before he can eat again.
@export var cooldown: float = 3.0
## Movement multiplier while grabbing and eating.
@export_range(0.0, 1.0) var move_while_eating: float = 0.1

@export_group("Throw")
## Throw speed (m/s) toward where he's aiming, and the upward part. Slightly down: he lets
## go about 3.2 m up, so this drops the body through soldier height from ~5 m out to ~15 m
## where it lands, instead of sailing over the crowd.
@export var throw_speed: float = 24.0
@export var throw_lift: float = -3.0
## The thrown body flattens soldiers it passes within this distance (m, flat)...
@export var throw_hit_radius: float = 1.1
## ...while it's still moving this fast (m/s)...
@export var throw_kill_speed: float = 6.0
## ...up to this many, then it's just a body.
@export var throw_max_hits: int = 3

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
var _throw_queued: bool = false
## Thrown bodies still hunting: [{"body": FlyingBody, "hits": int}]
var _missiles: Array[Dictionary] = []

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
	_update_missiles()
	if (phase == Phase.REACH or phase == Phase.LIFT or phase == Phase.EAT) and Input.is_action_just_pressed("punch"):
		throw()
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
				if _throw_queued:
					_throw_queued = false
					_start_throw()
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
		Phase.THROW:
			_timer -= delta
			if _timer <= 0.0:
				_release()
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
	_throw_queued = false
	hulk.move_speed_multiplier = move_while_eating
	grabbed.emit()
	return true


## Throw the soldier he's holding instead of eating him. Public so tests can call it.
## During the reach it's queued until the soldier is in his hand.
func throw() -> void:
	match phase:
		Phase.REACH:
			_throw_queued = true
		Phase.LIFT, Phase.EAT:
			_start_throw()


func _start_throw() -> void:
	phase = Phase.THROW
	_slide_t = 1.0  # Already in hand.
	_timer = hulk.animator.play_throw()
	hulk.move_speed_multiplier = move_while_eating
	throw_started.emit()


func _release() -> void:
	if not is_instance_valid(_victim):
		return
	var director := get_tree().get_first_node_in_group("death_director") as DeathDirector
	var body: FlyingBody = FLYING_BODY.instantiate()
	var parent: Node = director if director else hulk.get_parent()
	parent.add_child(body)
	body.global_transform = Transform3D(_victim.global_basis, _victim.global_position + Vector3.UP * 0.9)
	_victim.reparent(body, true)
	body.director = director
	body.gib_material = _victim_material
	body.reset_physics_interpolation()
	var forward := -hulk.global_basis.z
	forward.y = 0.0
	body.launch(forward.normalized() * throw_speed + Vector3.UP * throw_lift)
	_missiles.append({"body": body, "hits": 0})
	_victim = null
	thrown.emit(body)


## Thrown bodies flatten whoever they fly through.
func _update_missiles() -> void:
	for i in range(_missiles.size() - 1, -1, -1):
		var m: Dictionary = _missiles[i]
		var body = m["body"]
		if not is_instance_valid(body) or not body.is_inside_tree():
			_missiles.remove_at(i)
			continue
		var v: Vector3 = body.get_velocity()
		if v.length() < throw_kill_speed or m["hits"] >= throw_max_hits:
			_missiles.remove_at(i)
			continue
		var c: Vector3 = body.get_center()
		for node in get_tree().get_nodes_in_group("enemies"):
			var human := node as Human
			if human == null:
				continue
			var p := human.global_position
			if c.y > p.y + 2.8 or c.y < p.y - 0.3:
				continue
			if Vector2(c.x - p.x, c.z - p.z).length() > throw_hit_radius:
				continue
			human.kill(Vector3(v.x, 0.0, v.z) * 0.6 + Vector3.UP * 5.0, KillCause.YEETED)
			yeet_hit.emit(p + Vector3.UP * 1.2)
			m["hits"] += 1
			if m["hits"] >= throw_max_hits:
				break


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
	if phase == Phase.LIFT or phase == Phase.EAT or phase == Phase.THROW:
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
	_throw_queued = false
	phase = Phase.READY
	cooldown_remaining = 0.0
