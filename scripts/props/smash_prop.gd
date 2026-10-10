class_name SmashProp
extends RigidBody3D
## Street junk the Hulk can bat around: trash cans, shopping carts, fuel barrels.
## One script, three kinds (set `kind` in the scene):
##   TRASH_CAN - punched, it flies like a cannonball and flattens whoever it hits.
##   CART      - punched or charged, it rolls along the floor and bowls soldiers over.
##   BARREL    - punched, it flies with a lit fuse and blows up when it lands (or when the
##               fuse runs out). A rocket blast or another barrel sets it off where it stands.
##
## Who moves them: PunchAttack (cone), GroundPound (pops them up), FoolsballCharge (punts),
## the Hulk walking into them (a nudge), blasts (rockets, barrels). Everything calls hit().
##
## Collision: at rest they're world-layer cover (layer 1), so soldiers path around them. In
## flight they're layer 0 (nobody bumps them off course) and only collide with the world;
## soldiers are found by distance each frame. WHY: a 20 kg can bouncing off soldier capsules
## would stop dead on the first one. Same reasoning as the thrown car.
##
## Every wave start, a prop that's gone (exploded, fell off) or was moved pops back home.

## A soldier was flattened (for sounds and shake).
signal hit_soldier(at: Vector3)
## A barrel went off. hulk_damage = what the blast did to him (0 if he was clear).
signal exploded(at: Vector3, hulk_damage: int)
## Hit something solid fast (clang).
signal impacted(at: Vector3, speed: float)

enum Kind { TRASH_CAN, CART, BARREL }
enum State { IDLE, FLYING, GONE }

const COMIC := preload("res://scripts/vfx/comic_wall_impact.gd")

@export var kind: Kind = Kind.TRASH_CAN

@export_group("Launch")
## Speed a punch sends it flying (m/s), and the upward part. Carts mostly roll.
@export var punch_speed: float = 18.0
@export var punch_lift: float = 5.0
## How hard the Hulk walking into it nudges it (x his speed).
@export var nudge: float = 1.1

@export_group("Hitting soldiers")
## Moving at least this fast (m/s) flattens a soldier it passes.
@export var kill_speed: float = 5.0
## How close (m, flat, center to center) it has to pass.
@export var hit_radius: float = 1.0
## Speed kept after each soldier it hits (carts plow on, cans slow down).
@export_range(0.0, 1.0) var keep_speed: float = 0.85

@export_group("Barrel")
## Seconds of fuse after a punch lights it. A hard landing sets it off sooner.
@export var fuse: float = 1.4
## Landing harder than this (m/s, sudden stop) sets a lit barrel off at once.
@export var impact_detonate_speed: float = 6.0
@export var blast_radius: float = 4.5
## Damage to the Hulk if he's caught in it (center / edge). His own barrels sting too.
@export var max_damage: int = 12
@export var min_damage: int = 3
@export var blast_launch: float = 14.0

var state: State = State.IDLE
## Lit fuse seconds left (barrels), or -1.
var fuse_left: float = -1.0
## The kill cause a barrel blast hands out (a rocket-triggered one counts as Friendly Fire).
var blast_cause: int = KillCause.BLOWN_UP
var _home: Transform3D
var _prev_velocity: Vector3
var _still: float = 0.0
var _last_impact_ms: int = -10000
var _fuse_tween: Tween
var _model: Node3D
var _model_scale: Vector3 = Vector3.ONE  # The scene's own model scale (props are sized there).


func _ready() -> void:
	add_to_group("smash_props")
	_home = global_transform
	_model = get_node_or_null("Model")
	if _model:
		_model_scale = _model.scale
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	_set_flying(false)


func is_lit() -> bool:
	return fuse_left >= 0.0


## Every way of hitting a prop ends up here. velocity = where to send it.
## lights = a barrel's fuse starts (punches, charges); blasts set barrels off directly.
func hit(velocity: Vector3, lights: bool = true) -> void:
	if state == State.GONE:
		return
	if kind == Kind.CART:
		velocity.y = minf(velocity.y, 1.5)  # Carts roll, they don't fly.
	if state == State.IDLE:
		global_position += Vector3.UP * 0.12  # Off the floor first, so friction doesn't eat the launch.
	_set_flying(true)
	linear_velocity = velocity
	angular_velocity = _spin_for(velocity)
	_prev_velocity = velocity
	_still = 0.0
	if kind == Kind.BARREL and lights and not is_lit():
		_light()


## Punch / charge from `from`: sends it away from that point along `forward`.
func punch_from(from: Vector3, forward: Vector3, power: float = 1.0) -> void:
	var away := global_position - from
	away.y = 0.0
	var dir := (forward.normalized() + away.normalized()).normalized() if away.length() > 0.05 else forward.normalized()
	hit(dir * punch_speed * power + Vector3.UP * punch_lift * power)


## A blast at `at` (rocket, another barrel). Barrels go off; everything else gets thrown.
func blasted(at: Vector3, radius: float, cause: int = KillCause.BLOWN_UP) -> void:
	if state == State.GONE:
		return
	var off := global_position + Vector3.UP * 0.5 - at
	if off.length() > radius + 0.5:
		return
	if kind == Kind.BARREL:
		blast_cause = cause
		# A beat later, so chains ripple instead of all popping on one frame.
		get_tree().create_timer(0.12, false).timeout.connect(explode)
		return
	hit(off.normalized() * 14.0 + Vector3.UP * 7.0, false)


func _physics_process(delta: float) -> void:
	if state == State.GONE:
		return
	if global_position.y < -15.0:
		_vanish()
		return
	if state == State.IDLE:
		_nudged_by_hulk()
		return
	var speed := linear_velocity.length()
	if speed >= kill_speed:
		_sweep_soldiers()
	# Barrel: fuse, or a hard landing.
	if is_lit():
		fuse_left -= delta
		var h_prev := _prev_velocity.length()
		if fuse_left <= 0.0 or (h_prev >= impact_detonate_speed and linear_velocity.length() < h_prev * 0.5):
			explode()
			return
	_prev_velocity = linear_velocity
	if speed < 0.4 and angular_velocity.length() < 1.0:
		_still += delta
		if _still > 0.4 and not is_lit():
			_set_flying(false)
	else:
		_still = 0.0


func _sweep_soldiers() -> void:
	var c := global_position + Vector3.UP * 0.5
	for node in get_tree().get_nodes_in_group("enemies"):
		var human := node as Human
		if human == null:
			continue
		var p := human.global_position
		if c.y > p.y + 2.4:
			continue  # Flying over his head.
		if Vector2(c.x - p.x, c.z - p.z).length() > hit_radius:
			continue
		var v := linear_velocity
		human.kill(Vector3(v.x, 0.0, v.z) * 0.8 + Vector3.UP * 6.0, KillCause.CRUSHED)
		hit_soldier.emit(p + Vector3.UP * 1.2)
		linear_velocity = v * keep_speed
		if is_lit():
			explode()  # A barrel that hits a soldier goes off in his face.
			return


## The Hulk shoulders it out of the way as he walks.
func _nudged_by_hulk() -> void:
	var hulk := get_tree().get_first_node_in_group("player") as Hulk
	if hulk == null or hulk.health.is_dead:
		return
	var v := Vector3(hulk.velocity.x, 0.0, hulk.velocity.z)
	if v.length() < 1.0:
		return
	var off := global_position - hulk.global_position
	off.y = 0.0
	if off.length() > hulk.body_radius + 0.55 or off.dot(v) <= 0.0:
		return
	hit(off.normalized() * v.length() * nudge + Vector3.UP * 1.0, false)


func explode() -> void:
	if state == State.GONE:
		return
	var at := global_position + Vector3.UP * 0.5
	_vanish()
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
		var off := human.global_position + Vector3.UP * 0.9 - at
		if off.length() > blast_radius:
			continue
		var t := off.length() / blast_radius
		var away := Vector3(off.x, 0.0, off.z).normalized() if Vector2(off.x, off.z).length() > 0.05 else Vector3.FORWARD
		human.kill(away * blast_launch * (1.0 - t * 0.5) + Vector3.UP * lerpf(11.0, 5.0, t), blast_cause)
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
	for node in get_tree().get_nodes_in_group("smash_props"):
		if node != self:
			(node as SmashProp).blasted(at, blast_radius, blast_cause)
	Explosion.spawn(get_parent(), at, blast_radius * 0.8)
	exploded.emit(at, damage)


## Gone until the next wave (exploded, or fell off the bridge).
func _vanish() -> void:
	state = State.GONE
	fuse_left = -1.0
	if _fuse_tween:
		_fuse_tween.kill()
	if _model:
		_model.scale = _model_scale
	visible = false
	freeze = true
	collision_layer = 0
	collision_mask = 0


## New wave: anything gone or knocked away comes back home with a little pop. (Waves start
## after a 5 s break, so nothing is still in flight that anyone's watching.)
func reset_home() -> void:
	if state == State.IDLE and global_position.distance_to(_home.origin) < 1.5:
		return
	state = State.IDLE
	fuse_left = -1.0
	blast_cause = KillCause.BLOWN_UP
	if _fuse_tween:
		_fuse_tween.kill()
	visible = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = _home
	reset_physics_interpolation()
	_set_flying(false)
	if _model:
		_model.scale = _model_scale * 0.01
		create_tween().tween_property(_model, "scale", _model_scale, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _light() -> void:
	fuse_left = fuse
	if _model == null:
		return
	# Swells and throbs while the fuse burns: you can read "about to blow" at a glance.
	_fuse_tween = create_tween().set_loops()
	_fuse_tween.tween_property(_model, "scale", _model_scale * 1.18, 0.12)
	_fuse_tween.tween_property(_model, "scale", _model_scale, 0.12)


func _set_flying(flying: bool) -> void:
	freeze = false
	state = State.FLYING if flying else State.IDLE
	collision_layer = 0 if flying else 1
	collision_mask = 1


func _spin_for(velocity: Vector3) -> Vector3:
	match kind:
		Kind.CART:
			return Vector3.UP * randf_range(-2.0, 2.0)  # A lazy twirl as it rolls.
		_:
			var axis := velocity.cross(Vector3.UP).normalized()
			if axis.length() < 0.1:
				axis = Vector3.RIGHT
			# A slow tumble. Fast end-over-end spin made the can's rim dig into the floor on the
			# way out and kick it skyward, over the heads it was meant to hit.
			return -axis * velocity.length() * 0.3 + Vector3.UP * randf_range(-3.0, 3.0)


func _on_body_entered(_body: Node) -> void:
	if state != State.FLYING:
		return
	var speed := _prev_velocity.length()
	var now := Time.get_ticks_msec()
	if speed >= 4.0 and now - _last_impact_ms > 200:
		_last_impact_ms = now
		impacted.emit(global_position + Vector3.UP * 0.5, speed)
