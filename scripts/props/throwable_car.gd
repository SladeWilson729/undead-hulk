class_name ThrowableCar
extends RigidBody3D
## A wrecked car the Hulk can pick up and throw.
##
## States:
##   IDLE    - sitting in the level. Solid cover (world layer) for everyone. Can be picked up.
##   HELD    - frozen over the Hulk's head. CarryThrow moves it every physics frame.
##   FLYING  - thrown. Soldiers it touches get pinned to it (or just killed if it's slow or
##             already full). Hitting a wall hard crushes everyone pinned into gibs.
##             Plows straight through BreakablePillars. Settles back to IDLE.
##
## Collision while FLYING: layer 0 (nobody bumps into it, so it can't snag on the Hulk as it
## leaves his hands), mask 1 (world: floor, walls, pillars, other cars).
## Soldiers are found by the CrushZone Area3D (mask 4, enemies), not by physical contact.
## WHY: a 900 kg car bouncing off soldier capsules would lose its speed on the first one.
## With the area, it mows through the crowd and only real walls stop it.

signal picked_up
signal thrown
## Hard horizontal impact. count = soldiers that were pinned and got crushed.
signal crushed(position: Vector3, count: int)
## Flying car hit something solid (floor, wall, another car) at `speed` m/s. For the clang.
signal impacted(position: Vector3, speed: float)

enum State { IDLE, HELD, FLYING }

const FLYING_BODY := preload("res://scenes/enemies/flying_body.tscn")
const COMIC := preload("res://scripts/vfx/comic_wall_impact.gd")

@export_group("Throw")
## Forward speed of the throw (m/s).
@export var throw_speed: float = 22.0
## Vertical speed at release. Negative: the car is hurled down into the crowd from over his
## head (released ~3.5 m up), so it hits walls low instead of skimming the 4 m wall's top
## edge, and touches down ~12 m out before sliding.
@export var throw_lift: float = -4.0
## Flat spin (radians/second) around the vertical axis, random direction. Cartoon flair.
@export var throw_spin: float = 3.0

@export_group("Crush")
## Car speed (m/s) needed to pin a soldier to it.
@export var pin_speed: float = 10.0
## Car speed (m/s) needed to kill a soldier at all. Between kill_speed and pin_speed they get knocked flying.
@export var kill_speed: float = 4.0
## Most soldiers that can ride the car at once. Extras are killed and launched instead.
@export var max_pinned: int = 6
## Horizontal speed (m/s) the car must be doing for a sudden stop to count as a crush.
@export var crush_speed: float = 7.0
## A crush = horizontal speed drops below this fraction of last frame's in one physics frame.
@export_range(0.1, 0.9) var crush_drop: float = 0.55

@export_group("Level")
## Below this height (fell off the bridge) the car returns to where it started.
@export var respawn_height: float = -20.0

@export_group("Sound")
## Impacts slower than this (m/s) make no clang.
@export var impact_sound_speed: float = 4.0

var state: State = State.IDLE
var _last_impact_ms: int = -10000

var _home: Transform3D
var _prev_velocity: Vector3 = Vector3.ZERO
var _still_time: float = 0.0
## Each entry: {"visual": Node3D, "material": Material}
var _pinned: Array[Dictionary] = []

@onready var crush_zone: Area3D = $CrushZone


func _ready() -> void:
	add_to_group("throwables")
	_home = global_transform
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	_set_solid(true)


func can_pick_up() -> bool:
	return state == State.IDLE and linear_velocity.length() < 2.0


## CarryThrow calls this, then moves the car itself every frame until throw().
func pick_up() -> void:
	state = State.HELD
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_layer = 0
	collision_mask = 0
	crush_zone.set_deferred("monitoring", false)
	picked_up.emit()


## direction = flat throw direction (the Hulk's facing). speed_scale 0 just drops it (Hulk died).
func throw(direction: Vector3, speed_scale: float = 1.0) -> void:
	direction.y = 0.0
	direction = direction.normalized()
	state = State.FLYING
	freeze = false
	collision_layer = 0
	collision_mask = 1
	_still_time = 0.0
	linear_velocity = direction * throw_speed * speed_scale + Vector3.UP * throw_lift * speed_scale
	angular_velocity = Vector3.UP * throw_spin * (1.0 if randf() < 0.5 else -1.0) * speed_scale
	_prev_velocity = linear_velocity
	crush_zone.set_deferred("monitoring", true)
	reset_physics_interpolation()
	thrown.emit()


func _physics_process(delta: float) -> void:
	if state != State.FLYING:
		return
	if global_position.y < respawn_height:
		_respawn()
		return
	var speed := linear_velocity.length()
	# Crush check: did we just slam into something? Compares this frame's horizontal speed
	# against last frame's. Floor landings keep most of their horizontal speed; walls don't.
	var h_prev := Vector2(_prev_velocity.x, _prev_velocity.z).length()
	var h_now := Vector2(linear_velocity.x, linear_velocity.z).length()
	if h_prev >= crush_speed and h_now < h_prev * crush_drop:
		_crush()
	if speed >= kill_speed:
		_sweep_soldiers(speed)
	_prev_velocity = linear_velocity
	# Settled?
	if speed < 0.6 and angular_velocity.length() < 1.0:
		_still_time += delta
		if _still_time > 0.5:
			_settle()
	else:
		_still_time = 0.0


## Every soldier inside the crush zone right now. Checked every frame rather than on
## body_entered, so a soldier who was already inside when the car sped up still counts.
func _sweep_soldiers(speed: float) -> void:
	for body in crush_zone.get_overlapping_bodies():
		var human := body as Human
		if human == null or not human.is_in_group("enemies"):
			continue
		if speed >= pin_speed and _pinned.size() < max_pinned:
			var mat := human.gib_material
			var visual := human.pin_to(self)
			if visual:
				_pinned.append({"visual": visual, "material": mat})
		else:
			human.kill(linear_velocity * 0.7 + Vector3.UP * 6.0)


## Hard stop: everyone riding the car bursts. One big shake, one "CRUNCH!".
func _crush() -> void:
	var count := _pinned.size()
	var director := get_tree().get_first_node_in_group("death_director") as DeathDirector
	for entry in _pinned:
		var visual: Node3D = entry["visual"]
		if not is_instance_valid(visual):
			continue
		if director:
			director.explode_at(visual.global_position + Vector3.UP * 0.8, Vector3.ZERO, entry["material"])
		visual.queue_free()
	_pinned.clear()
	var at := global_position + Vector3.UP * 1.0 + _prev_velocity.normalized() * 2.0
	if count > 0:
		_spawn_comic(at, "CRUNCH!")
	crushed.emit(at, count)


## Came to rest without hitting a wall: anyone still riding falls off as a limp body.
## Back to IDLE: solid cover again, and ready to be thrown again.
func _settle() -> void:
	state = State.IDLE
	crush_zone.set_deferred("monitoring", false)
	_drop_pinned()
	_set_solid(true)


func _drop_pinned() -> void:
	var director := get_tree().get_first_node_in_group("death_director") as DeathDirector
	for entry in _pinned:
		var visual: Node3D = entry["visual"]
		if not is_instance_valid(visual):
			continue
		var body: FlyingBody = FLYING_BODY.instantiate()
		var parent: Node = director if director else get_parent()
		parent.add_child(body)
		body.global_transform = Transform3D(visual.global_basis, visual.global_position + Vector3.UP * 0.9)
		visual.reparent(body, true)
		body.director = director
		body.gib_material = entry["material"]
		body.reset_physics_interpolation()
		var away := visual.global_position - global_position
		away.y = 0.0
		body.launch(away.normalized() * 3.0 + Vector3.UP * 2.0)
	_pinned.clear()


func _respawn() -> void:
	for entry in _pinned:
		if is_instance_valid(entry["visual"]):
			entry["visual"].queue_free()
	_pinned.clear()
	state = State.IDLE
	crush_zone.set_deferred("monitoring", false)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = _home
	reset_physics_interpolation()
	_set_solid(true)


## Plow through pillars: smash it and keep most of our speed, so the pillar doesn't
## register as a wall crush.
func _on_body_entered(body: Node) -> void:
	if state != State.FLYING:
		return
	var pillar := body as BreakablePillar
	if pillar == null or pillar.broken:
		# Anything else solid: clang. Rate-limited so a car bouncing and scraping along the
		# floor doesn't fire a sound every physics frame.
		var speed := _prev_velocity.length()
		var now := Time.get_ticks_msec()
		if speed >= impact_sound_speed and now - _last_impact_ms > 200:
			_last_impact_ms = now
			impacted.emit(global_position + Vector3.UP * 0.8, speed)
		return
	if _prev_velocity.length() < kill_speed:
		return
	var hit_height := clampf(global_position.y - pillar.global_position.y + 0.8, 0.3, pillar.size.y)
	pillar.take_hit(_prev_velocity, hit_height, 1.2)
	linear_velocity = _prev_velocity * 0.85


func _set_solid(solid: bool) -> void:
	freeze = false
	collision_layer = 1 if solid else 0
	collision_mask = 1


func _spawn_comic(at: Vector3, word: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	get_parent().add_child(layer)
	var comic := COMIC.new()
	comic.word = word
	comic.style = 0
	comic.anchor = at
	layer.add_child(comic)
	get_tree().create_timer(1.2).timeout.connect(layer.queue_free)
