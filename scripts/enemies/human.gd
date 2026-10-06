class_name Human
extends CharacterBody3D
## A run-of-the-mill human trying to stop the Hulk.
## Chases in a straight line, piles up around the Hulk, and slaps it for 1 damage
## on its own cooldown. Dies in one hit (step 4 calls kill()).

signal died(human: Human)

enum State { CHASE, ATTACK, IDLE }

@export_group("Movement")
## Base run speed. Slower than the Hulk's 7.0 so he can reposition, fast enough to keep pressure on.
@export var move_speed: float = 5.5
## +/- random spread applied per human, so the swarm smears out instead of moving as one block.
@export_range(0.0, 0.5) var speed_variance: float = 0.15
@export var acceleration: float = 25.0
@export var turn_sharpness: float = 10.0
## Within this distance of the Hulk, humans start curving around him instead of
## running straight in. Without it they queue up single file and only a few can hit.
@export var flank_range: float = 4.0
## How hard they curve. 0 = straight line, 1 = 45 degrees off.
@export var flank_strength: float = 0.8

@export_group("Attack")
## Damage per hit. Design rule: 1.
@export var damage: int = 1
## Seconds between hits from THIS human. 10 humans in contact = 10 damage per second.
@export var attack_cooldown: float = 1.0
## Extra gap (meters) beyond touching distance that still counts as "in contact".
## Needed because collision keeps the two capsules from ever exactly touching.
@export var attack_reach: float = 0.35

const BODY_RADIUS := 0.4
const FLYING_BODY := preload("res://scenes/enemies/flying_body.tscn")

@export_group("Animation")
## Leg/arm swing speed per m/s of movement.
@export var stride_rate: float = 2.2
## Leg swing in radians at full speed.
@export var leg_swing: float = 0.7
## How far the arms raise toward the Hulk while attacking (radians; 1.57 = straight forward).
@export var attack_arm_raise: float = 1.4

## Shirt colors so the crowd reads as individuals. Created once and shared by every human (cheap).
static var _shirt_materials: Array[StandardMaterial3D] = []

var target: Hulk
var state: State = State.CHASE
var _speed: float
var _flank_side: float  # +1 or -1: which way this human circles. Random so the crowd splits.
var _cooldown: float = 0.0
var _dead: bool = false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _stride: float = 0.0
## The shirt color this human rolled. DeathDirector passes it to the corpse so the body matches.
var shirt_material: StandardMaterial3D

@onready var visual: Node3D = $Visual
@onready var arm_l: Node3D = $Visual/ArmL
@onready var arm_r: Node3D = $Visual/ArmR
@onready var leg_l: Node3D = $Visual/LegL
@onready var leg_r: Node3D = $Visual/LegR


func _ready() -> void:
	add_to_group("enemies")
	_speed = move_speed * randf_range(1.0 - speed_variance, 1.0 + speed_variance)
	# Stagger the first swing so a group that arrives together doesn't hit in perfect sync.
	_cooldown = randf_range(0.0, 0.4)
	_flank_side = 1.0 if randf() < 0.5 else -1.0
	shirt_material = _random_shirt()
	for mesh_path in ["Visual/Body", "Visual/ArmL/Mesh", "Visual/ArmR/Mesh"]:
		(get_node(mesh_path) as MeshInstance3D).material_override = shirt_material
	_stride = randf() * TAU  # Start mid-stride so the crowd doesn't step in unison.
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Hulk


func _physics_process(delta: float) -> void:
	# Safety net: a human that somehow leaves the bridge alive would block "wave cleared" forever.
	if global_position.y < -10.0:
		kill()
		return
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_cooldown = maxf(_cooldown - delta, 0.0)

	if target == null or target.health.is_dead:
		state = State.IDLE

	var desired := Vector3.ZERO
	match state:
		State.CHASE, State.ATTACK:
			var to_target := target.global_position - global_position
			to_target.y = 0.0
			var dist := to_target.length()
			var contact_dist := target.body_radius + BODY_RADIUS + attack_reach
			if dist <= contact_dist:
				state = State.ATTACK
				_try_attack()
			else:
				state = State.CHASE
			# Keep pushing inward even while attacking: that pressure is what makes it feel like a swarm.
			if dist > 0.01:
				var dir := to_target / dist
				_face(to_target, delta)
				if state == State.CHASE and dist < flank_range:
					# Curve around the Hulk to find an open slot instead of shoving the guy in front.
					var tangent := Vector3(-dir.z, 0.0, dir.x) * _flank_side
					dir = (dir + tangent * flank_strength).normalized()
				desired = dir * _speed
		State.IDLE:
			desired = Vector3.ZERO

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(desired, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()
	_animate(delta)


## Procedural run cycle: legs and arms swing opposite each other, scaled by speed.
## While attacking, both arms reach forward and slap. Runs in the physics step so it
## stays smooth with physics interpolation. Throwaway once real animated models arrive (step 8).
func _animate(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	_stride += delta * speed * stride_rate
	var amount := clampf(speed / move_speed, 0.0, 1.0)
	var swing := sin(_stride) * amount
	leg_l.rotation.x = swing * leg_swing
	leg_r.rotation.x = -swing * leg_swing
	var weight := 1.0 - exp(-15.0 * delta)
	var arm_l_target := -swing * leg_swing * 0.8
	var arm_r_target := swing * leg_swing * 0.8
	if state == State.ATTACK:
		# Positive X rotation swings a hanging arm forward (toward -Z, where we face).
		arm_l_target = attack_arm_raise + sin(_stride * 3.0) * 0.2
		arm_r_target = attack_arm_raise - sin(_stride * 3.0) * 0.2
	arm_l.rotation.x = lerpf(arm_l.rotation.x, arm_l_target, weight)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, arm_r_target, weight)


func _try_attack() -> void:
	if _cooldown > 0.0:
		return
	_cooldown = attack_cooldown
	target.health.take_damage(damage)
	# Tiny lunge so you can SEE who is hitting you.
	var tween := create_tween()
	tween.tween_property(visual, "position:z", -0.35, 0.06)
	tween.tween_property(visual, "position:z", 0.0, 0.12)


func _face(dir: Vector3, delta: float) -> void:
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-turn_sharpness * delta))


## Shoved by the Hulk walking into us. Called by the Hulk; see Hulk._shove_humans().
func shove(push_velocity: Vector3) -> void:
	velocity.x = push_velocity.x
	velocity.z = push_velocity.z


## One-hit death. Hands off to the level's DeathDirector, which picks ragdoll, cheap body,
## or explosion. The living human is removed either way.
func kill(launch_velocity: Vector3 = Vector3.ZERO) -> void:
	if _dead:
		return
	_dead = true
	# Leave the group NOW, not at end of frame, so a second attack this same frame
	# (or the Hulk's shove) can't hit a human that is already dead.
	remove_from_group("enemies")
	var director := get_tree().get_first_node_in_group("death_director") as DeathDirector
	if director:
		director.spawn_death(self, launch_velocity)
		died.emit(self)
		queue_free()
		return
	# Fallback when no DeathDirector exists (e.g. running human.tscn on its own): plain flying body.
	var body: FlyingBody = FLYING_BODY.instantiate()
	get_parent().add_child(body)
	# Rigid body pivots around its center, so place it at mid-height, not at the feet.
	body.global_transform = Transform3D(global_basis, global_position + Vector3.UP * 0.9)
	visual.reparent(body, true)
	body.reset_physics_interpolation()
	body.launch(launch_velocity)
	died.emit(self)
	queue_free()


static func _random_shirt() -> StandardMaterial3D:
	if _shirt_materials.is_empty():
		for c in [Color(0.2, 0.4, 0.8), Color(0.85, 0.75, 0.2), Color(0.55, 0.25, 0.6), Color(0.9, 0.45, 0.15), Color(0.35, 0.35, 0.38)]:
			var m := StandardMaterial3D.new()
			m.albedo_color = c
			m.roughness = 0.85
			_shirt_materials.append(m)
	return _shirt_materials.pick_random()
