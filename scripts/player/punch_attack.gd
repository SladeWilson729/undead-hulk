class_name PunchAttack
extends Node
## The Hulk's punch. Child node of the Hulk so each attack lives in its own script
## (the ground pound in step 5 becomes a sibling node built the same way).
##
## Timeline of one punch:  READY -> WINDUP (fist pulls back) -> STRIKE (one hit check) -> RECOVERY -> READY
## Hold left mouse to keep punching.
##
## Hit detection is a cone in front of the Hulk, checked once on the strike frame.
## WHY not an Area3D: an Area3D needs a physics frame after being switched on before it
## reports overlaps, which makes hits land a frame late and unreliably. A direct
## distance + angle check is instant, predictable, and easy to tune in the Inspector.

## Emitted on the strike frame. hits = how many humans got launched (0 = whiff).
signal punched(hits: int)
## Emitted when a punch starts (the click). Voice efforts hang off this, not the impact.
signal swung
## Dead bodies popped in midair by this punch (style points).
signal juggled(count: int)

enum Phase { READY, WINDUP, RECOVERY }

@export_group("Timing")
## Seconds from click to impact. Short = responsive. Longer = heavier, more telegraphed.
@export var windup: float = 0.07
## Seconds after impact before the next punch can start.
@export var recovery: float = 0.28
## Movement speed multiplier while punching. Commits the player to the swing.
@export_range(0.0, 1.0) var move_slow: float = 0.5

@export_group("Hit cone")
## Reach in meters, measured from the Hulk's center to the human's center.
@export var reach: float = 3.0
## Total width of the cone in degrees. 80 = a solid haymaker without hitting everything around you.
@export_range(10.0, 180.0) var arc_degrees: float = 80.0
## Most humans one punch can launch (closest first). 0 = unlimited.
## WHY a cap: uncapped, 4 punches deleted a 30-human swarm in testing, which leaves
## nothing for the ground pound to do. The punch is the precise tool; the pound clears crowds.
@export var max_targets: int = 4

@export_group("Juggle")
## Extra reach for hitting airborne bodies: falling bodies are hard to time, so be generous.
@export var juggle_extra_reach: float = 1.0
## Bodies above this height (meters) are out of fist range.
@export var juggle_max_height: float = 5.0

@export_group("Launch")
## Horizontal launch speed range (m/s). Random per victim so bodies scatter instead of flying in formation.
@export var launch_speed_min: float = 16.0
@export var launch_speed_max: float = 22.0
## Upward launch speed range (m/s). This is what sends them over the railing.
@export var launch_lift_min: float = 6.0
@export var launch_lift_max: float = 9.0

var phase: Phase = Phase.READY
var _timer: float = 0.0
var _use_left: bool = false

@onready var hulk: Hulk = get_parent()


func _physics_process(delta: float) -> void:
	match phase:
		Phase.READY:
			if Input.is_action_pressed("punch"):
				start()
		Phase.WINDUP:
			_timer -= delta
			if _timer <= 0.0:
				_strike()
				phase = Phase.RECOVERY
				_timer = recovery
		Phase.RECOVERY:
			_timer -= delta
			if _timer <= 0.0:
				phase = Phase.READY
				hulk.move_speed_multiplier = 1.0


## Begins a punch. Public so tests (and later, a controller or AI) can trigger it without the mouse.
func start() -> void:
	if not hulk.can_attack():
		return
	phase = Phase.WINDUP
	_timer = windup
	hulk.move_speed_multiplier = move_slow
	# Alternate fists: left, right, left... reads as a flurry when you hold the button.
	hulk.animator.play_punch(_use_left, windup)
	_use_left = not _use_left
	swung.emit()


func _strike() -> void:
	var targets := find_targets()
	var forward := -hulk.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	for human in targets:
		var away := human.global_position - hulk.global_position
		away.y = 0.0
		away = away.normalized()
		# Blend "straight ahead" with "away from the Hulk": victims fan out in a spray
		# instead of all flying down one line.
		var dir := (forward + away).normalized()
		var launch := dir * randf_range(launch_speed_min, launch_speed_max)
		launch.y = randf_range(launch_lift_min, launch_lift_max)
		human.kill(launch, KillCause.SMASHED)
	var juggles := _juggle_airborne_bodies()
	if juggles > 0:
		juggled.emit(juggles)
	_smash_breakables()
	punched.emit(targets.size() + juggles)


## Pillars (anything in the "breakables" group) inside the cone get smashed. Reach is
## measured to the pillar's center, so its half-width is added: you hit its face.
func _smash_breakables() -> void:
	for node in get_tree().get_nodes_in_group("breakables"):
		var pillar := node as BreakablePillar
		if pillar == null or pillar.broken:
			continue
		if _in_cone(pillar.global_position, reach + pillar.footprint_radius()):
			# Rubble flies straight away from the Hulk, at fist height.
			pillar.take_hit(pillar.global_position - hulk.global_position, 1.6, 1.0)


## Juggle: any dead body still falling through the cone explodes.
## Bodies only count up to juggle_max_height, so you can't punch someone 10 m up.
func _juggle_airborne_bodies() -> int:
	var director := get_tree().get_first_node_in_group("death_director") as DeathDirector
	if director == null:
		return 0
	var count := 0
	for corpse in director.airborne_corpses():
		var c: Vector3 = corpse.get_center()
		if c.y <= juggle_max_height and _in_cone(c, reach + juggle_extra_reach):
			corpse.explode()
			count += 1
	return count


## Every living human inside the cone in front of the Hulk right now.
func find_targets() -> Array[Human]:
	var result: Array[Human] = []
	for node in get_tree().get_nodes_in_group("enemies"):
		var human := node as Human
		if _in_cone(human.global_position, reach):
			result.append(human)
	if max_targets > 0 and result.size() > max_targets:
		var origin := hulk.global_position
		result.sort_custom(func(a: Human, b: Human) -> bool:
			return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin))
		result.resize(max_targets)
	return result


## True if a world position is inside the punch cone (flat, ignoring height).
func _in_cone(point: Vector3, max_dist: float) -> bool:
	var forward := -hulk.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var offset := point - hulk.global_position
	offset.y = 0.0
	var dist := offset.length()
	if dist > max_dist:
		return false
	if dist < 0.001:
		return true
	# Anyone pressed right up against the Hulk counts if they are anywhere in front of him,
	# so huggers directly ahead never "slip through" the edge of the cone.
	var point_blank := dist < hulk.body_radius + Human.BODY_RADIUS + 0.3
	var needed_dot := 0.0 if point_blank else cos(deg_to_rad(arc_degrees * 0.5))
	return offset.normalized().dot(forward) >= needed_dot
