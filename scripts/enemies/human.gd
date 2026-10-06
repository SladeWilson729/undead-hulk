class_name Human
extends CharacterBody3D
## A run-of-the-mill soldier trying to stop the Hulk.
## Chases in a straight line, piles up around the Hulk, and punches it for 1 damage
## on its own cooldown. Dies in one hit: attacks call kill().
## Looks: one of the rigged soldiers in SoldierVariants, picked at random on spawn.

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
## Fastest the Running clip may play. Above this the legs blur; a little foot slide is better.
@export var max_run_playback: float = 2.2
## Punch Combo throws four punches between ~0.45 s and ~1.55 s. While attacking we loop that
## window. Damage stays on attack_cooldown; the animation is purely visual.
@export var punch_loop_start: float = 0.45
@export var punch_loop_end: float = 1.55
@export var anim_blend: float = 0.15

var target: Hulk
var state: State = State.CHASE
var _speed: float
var _flank_side: float  # +1 or -1: which way this human circles. Random so the crowd splits.
var _cooldown: float = 0.0
var _dead: bool = false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## Which soldier this is (an entry from SoldierVariants.VARIANTS). Set before add_child to
## force one (tests do); otherwise it's rolled in _ready().
var variant: Dictionary = {}
## The soldier model instance (child of Visual). DeathDirector hands it to the corpse.
var model: Node3D
## Uniform-colored material for this soldier's gibs when he explodes.
var gib_material: Material

var _ap: AnimationPlayer
var _run_speed: float = 3.0

@onready var visual: Node3D = $Visual


func _ready() -> void:
	add_to_group("enemies")
	_speed = move_speed * randf_range(1.0 - speed_variance, 1.0 + speed_variance)
	# Stagger the first swing so a group that arrives together doesn't hit in perfect sync.
	_cooldown = randf_range(0.0, 0.4)
	_flank_side = 1.0 if randf() < 0.5 else -1.0
	_build_model()
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
	_animate()


func _build_model() -> void:
	if variant.is_empty():
		variant = SoldierVariants.pick_random()
	var data := SoldierVariants.data_for(variant)
	gib_material = data.gib_material
	_run_speed = variant.run_speed
	model = data.scene.instantiate()
	visual.add_child(model)
	# Mixamo characters face +Z; Godot's forward is -Z.
	model.rotation.y = PI
	_ap = SoldierVariants.find_player(model)
	_ap.add_animation_library("soldier", data.library)
	_ap.play("soldier/run")
	# Start each soldier at a random point in the stride so the crowd doesn't step in unison.
	_ap.seek(randf() * _ap.current_animation_length, true)


## Running scales with actual ground speed; attacking loops the punch flurry.
func _animate() -> void:
	if state == State.ATTACK:
		if _ap.current_animation != "soldier/punch":
			_ap.play("soldier/punch", anim_blend)
			_ap.seek(punch_loop_start, true)
		elif _ap.current_animation_position >= punch_loop_end:
			_ap.seek(punch_loop_start, true)
		_ap.speed_scale = 1.0
		return
	if _ap.current_animation != "soldier/run":
		_ap.play("soldier/run", anim_blend)
	var speed := Vector2(velocity.x, velocity.z).length()
	# Nearly stopped (e.g. the Hulk is dead): freeze mid-stride rather than moonwalk.
	_ap.speed_scale = 0.0 if speed < 0.3 else clampf(speed / _run_speed, 0.4, max_run_playback)


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
