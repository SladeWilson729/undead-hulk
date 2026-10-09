class_name Human
extends CharacterBody3D
## A run-of-the-mill soldier trying to stop the Hulk.
## Chases in a straight line, piles up around the Hulk, and punches it for 1 damage
## on its own cooldown. Dies in one hit: attacks call kill().
## Tougher enemies (the specials) set hits_to_kill above 1: then kill() from a punch, pound,
## rubble or blast only takes a hit off (flash, knockback, a short stagger) until the last one.
## Eating, a thrown car, the Foolsball charge and falling always kill outright.
## Looks: one of the rigged soldiers in SoldierVariants, picked at random on spawn.

signal died(human: Human)
## Took a hit and lived (only enemies with hits_to_kill > 1). hits_left = hits still needed.
signal hurt(human: Human, hits_left: int)

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

@export_group("Obstacle avoidance")
## How far ahead (m) a soldier checks that his straight line to the Hulk is clear.
@export var avoid_lookahead: float = 2.5
## Seconds between checks (staggered per soldier). One sphere cast per check when the way is
## clear; 16 when blocked.
@export var avoid_interval: float = 0.1
## Preference for keeping the side (left/right) he already chose, so he doesn't dither
## in front of the obstacle.
@export var avoid_side_bias: float = 0.4

@export_group("Attack")
## Damage per hit. Design rule: 1.
@export var damage: int = 1
## Seconds between hits from THIS human. 10 humans in contact = 10 damage per second.
@export var attack_cooldown: float = 1.0
## Extra gap (meters) beyond touching distance that still counts as "in contact".
## Needed because collision keeps the two capsules from ever exactly touching.
@export var attack_reach: float = 0.35

const BODY_RADIUS := 0.4
## Obstacle probe: a sphere slightly thinner than the body (so a soldier already touching a
## pillar isn't "inside" it), centred low enough to catch a 0.44 m pillar stump while its
## bottom still clears the floor.
const PROBE_RADIUS := 0.35
const PROBE_HEIGHT := 0.45
const AVOID_DIRECTIONS := 16
const FLYING_BODY := preload("res://scenes/enemies/flying_body.tscn")
## These causes kill anyone, however tough. UNKNOWN is a plain kill() call (debug, tests).
const INSTANT_CAUSES := [KillCause.UNKNOWN, KillCause.EATEN, KillCause.CRUSHED, KillCause.TACKLED, KillCause.FELL]

@export_group("Animation")
## Fastest the Running clip may play. Above this the legs blur; a little foot slide is better.
@export var max_run_playback: float = 2.2
## Punch Combo throws four punches between ~0.45 s and ~1.55 s. While attacking we loop that
## window. Damage stays on attack_cooldown; the animation is purely visual.
@export var punch_loop_start: float = 0.45
@export var punch_loop_end: float = 1.55
@export var anim_blend: float = 0.15

@export_group("Toughness")
## Hits from punches, pounds, rubble, rocket blasts and Glitter Bombs it takes to die.
## Grunts are 1. Eaten, crushed by a car, tackled or fallen always dies at once.
@export var hits_to_kill: int = 1
## Seconds a hit that doesn't kill leaves him reeling (no moving, no attacking).
@export var stagger_time: float = 0.45
## How much of the hit's sideways launch becomes knockback on a hit that doesn't kill.
@export var hit_knockback: float = 0.35

@export_group("Score")
## Name on the run summary (special enemies are listed by name).
@export var kind_name: String = "Soldier"
## Extra score for killing this one. 0 = regular grunt; specials set it in their scene.
@export var bounty: int = 0

@export_group("Painterly look")
@export var painterly_enabled: bool = true
@export var paint_style: ShaderMaterial = preload("res://assets/materials/painterly/soldier_character.tres")

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
## How he died (a KillCause), set just before `died` fires. The Run record reads it.
var death_cause: int = KillCause.UNKNOWN
## Extra score for this kill as a fraction (0.5 = +50%). Augments add to it at death
## (Bobbleheads head pop, Glitter Bomb confetti kill); the Run record reads it.
var score_bonus: float = 0.0
## Set before kill() to burst this soldier into confetti instead of a corpse (Glitter Bomb).
var force_confetti: bool = false
## Hits still needed to kill him (starts at hits_to_kill).
var hits_left: int = 1
## Seconds of stagger left after a hit that didn't kill.
var stagger_left: float = 0.0
var _flash: StandardMaterial3D
var _flash_tween: Tween

var _ap: AnimationPlayer
var _avoid_timer: float = 0.0
## Detour direction while the straight line is blocked; ZERO = path clear, run straight.
var _steer: Vector3 = Vector3.ZERO
var _steer_side: float = 0.0
var _probe: PhysicsShapeQueryParameters3D
var _run_speed: float = 3.0

@onready var visual: Node3D = $Visual


func _ready() -> void:
	add_to_group("enemies")
	hits_left = maxi(hits_to_kill, 1)
	_speed = move_speed * randf_range(1.0 - speed_variance, 1.0 + speed_variance)
	# Stagger the first swing so a group that arrives together doesn't hit in perfect sync.
	_cooldown = randf_range(0.0, 0.4)
	_flank_side = 1.0 if randf() < 0.5 else -1.0
	_avoid_timer = randf() * avoid_interval  # Stagger: not every soldier probes on the same tick.
	var sphere := SphereShape3D.new()
	sphere.radius = PROBE_RADIUS
	_probe = PhysicsShapeQueryParameters3D.new()
	_probe.shape = sphere
	_probe.collision_mask = 1  # World only: walls, rails, pillars, stumps, parked cars. Not the Hulk or the crowd.
	_build_model()
	if target == null:
		target = get_tree().get_first_node_in_group("player") as Hulk


func _physics_process(delta: float) -> void:
	# Safety net: a human that somehow leaves the bridge alive would block "wave cleared" forever.
	if global_position.y < -10.0:
		kill(Vector3.ZERO, KillCause.FELL)
		return
	if _stagger_step(delta):
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
				if state == State.CHASE:
					dir = _avoid(dir, dist - contact_dist, delta)
				desired = dir * _speed
		State.IDLE:
			desired = Vector3.ZERO

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(desired, acceleration * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	var incoming := velocity
	move_and_slide()
	for collision_index in range(get_slide_collision_count()):
		var collision := get_slide_collision(collision_index)
		var collider := collision.get_collider() as CollisionObject3D
		if collider == null or (collider.collision_layer & 1) == 0:
			continue
		var director := get_tree().get_first_node_in_group("death_director") as DeathDirector
		if director:
			director.show_wall_comic(self,collision.get_position(),collision.get_normal(),-incoming.dot(collision.get_normal()))
	_animate()


func _build_model() -> void:
	if variant.is_empty():
		variant = SoldierVariants.pick_random()
	var data := SoldierVariants.data_for(variant)
	gib_material = data.gib_material
	_run_speed = variant.run_speed
	model = data.scene.instantiate()
	visual.add_child(model)
	if painterly_enabled:
		preload("res://scripts/vfx/character_paint.gd").apply_to(model,paint_style)
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


## Steering around obstacles. Every avoid_interval: is the straight line clear for the next
## avoid_lookahead meters? Yes: run straight. No: try 16 directions around the circle and take
## the one that's clear and points most toward the Hulk, preferring the side already chosen.
## No navmesh: obstacles here move and break (thrown cars, smashed pillars), so a baked
## mesh would be stale; probing the world as it is right now always matches the level.
func _avoid(dir: Vector3, room: float, delta: float) -> Vector3:
	_avoid_timer -= delta
	if _avoid_timer <= 0.0:
		_avoid_timer = avoid_interval
		var reach := clampf(room, 0.5, avoid_lookahead)
		if _free_fraction(dir, reach) >= 0.999:
			_steer = Vector3.ZERO
			_steer_side = 0.0
		else:
			_steer = _detour(dir, reach)
	return _steer if _steer != Vector3.ZERO else dir


func _detour(dir: Vector3, reach: float) -> Vector3:
	var best := dir
	var best_score := -INF
	var best_side := 0.0
	for i in range(1, AVOID_DIRECTIONS):
		var d := dir.rotated(Vector3.UP, TAU * i / AVOID_DIRECTIONS)
		var free := _free_fraction(d, reach)
		# Fully clear directions win; partly clear ones only as a last resort.
		var score := d.dot(dir) + (0.0 if free >= 0.999 else -2.0 + free)
		var side := signf(dir.cross(d).y)
		if _steer_side != 0.0 and side == _steer_side:
			score += avoid_side_bias
		if score > best_score:
			best_score = score
			best = d
			best_side = side
	_steer_side = best_side
	return best


## Fraction (0-1) of `reach` meters the body can travel along `dir` before touching the world.
func _free_fraction(dir: Vector3, reach: float) -> float:
	_probe.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP * PROBE_HEIGHT)
	_probe.motion = dir * reach
	var result := get_world_3d().direct_space_state.cast_motion(_probe)
	return result[0]


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


## Hit by a thrown car: dies (counts as a kill) but his body rides the car, stuck to it.
## Returns the visual so the car can crush it against a wall or drop it later.
## Returns null if he was already dead.
func pin_to(carrier: Node3D, cause: int = KillCause.UNKNOWN) -> Node3D:
	if _dead:
		return null
	_dead = true
	death_cause = cause
	remove_from_group("enemies")
	var pinned := visual
	pinned.reparent(carrier, true)
	# Freeze him mid-stride: splayed against the car.
	var player := SoldierVariants.find_player(pinned)
	if player:
		player.pause()
	died.emit(self)
	queue_free()
	return pinned


## Takes the hit instead of dying when he has hits to spare. Called first thing by kill()
## (and by subclasses' kill() before they drop gear or cancel moves). Returns true if he
## survived, false if this hit kills him. Safe to call twice for the same hit: once he's on
## his last hit it changes nothing.
func absorb_hit(launch_velocity: Vector3, cause: int) -> bool:
	if _dead or hits_left <= 1 or cause in INSTANT_CAUSES:
		return false
	hits_left -= 1
	# Augments set these up for a kill; this hit isn't one.
	force_confetti = false
	score_bonus = 0.0
	velocity = Vector3(launch_velocity.x, 0.0, launch_velocity.z) * hit_knockback
	stagger_left = stagger_time
	_flash_hit()
	_on_hurt()
	hurt.emit(self, hits_left)
	return true


## Subclass hook: a hit landed and he lived (cancel an attack in progress, etc.).
func _on_hurt() -> void:
	pass


## While staggered: slide off the knockback, no thinking, no attacking. Returns true while
## the stagger lasts (the caller skips its normal frame).
func _stagger_step(delta: float) -> bool:
	if stagger_left <= 0.0:
		return false
	stagger_left -= delta
	if not is_on_floor():
		velocity.y -= _gravity * delta
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, acceleration * 0.6 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	move_and_slide()
	if _ap:
		_ap.speed_scale = 0.0  # Frozen mid-pose: reads as a flinch.
	return true


## White flash over the whole model, fading fast.
func _flash_hit() -> void:
	if model == null:
		return
	if _flash == null:
		_flash = StandardMaterial3D.new()
		_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
		for mesh in model.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).material_overlay = _flash
	if _flash_tween:
		_flash_tween.kill()
	_flash.albedo_color.a = 0.85
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "albedo_color:a", 0.0, 0.22)


## Death (or, for tough enemies, a hit: see absorb_hit). Hands off to the level's DeathDirector, which picks ragdoll, cheap body,
## or explosion. The living human is removed either way.
func kill(launch_velocity: Vector3 = Vector3.ZERO, cause: int = KillCause.UNKNOWN) -> void:
	if _dead or absorb_hit(launch_velocity, cause):
		return
	_dead = true
	death_cause = cause
	# Augments that change how a death plays out (head pops) get their say first.
	get_tree().call_group("kill_modifiers", "on_kill", self, launch_velocity)
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
