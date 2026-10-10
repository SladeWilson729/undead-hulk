class_name GroundPound
extends Node
## The Hulk's crowd-clearer. Sibling of PunchAttack, built the same way.
##
## Timeline:  READY -> RISING (short hop) -> SLAMMING (drives down hard) -> impact on landing -> COOLDOWN -> READY
## Right mouse or Space.
##
## On impact, every human inside kill_radius dies and pops UP (the closer to the center,
## the higher they fly). Humans in the outer ring, out to shove_radius, survive but get knocked back.
## The Hulk can't be hurt from takeoff until impact: the pound is also your panic button
## when you're surrounded.

## Emitted on impact. kills = humans launched (0 = slammed empty ground).
signal pounded(kills: int)
## Emitted at takeoff.
signal leaped
## Dead bodies popped in midair by the shockwave (style points).
signal juggled(count: int)

enum Phase { READY, RISING, SLAMMING, COOLDOWN }

@export_group("Timing")
## Seconds before the pound can be used again, counted from impact.
@export var cooldown: float = 4.0
## Upward speed of the hop (m/s).
## Upward speed of a physical hop (m/s). 0 since the Mixamo Jump Attack clip does the
## jumping visually; the body stays on the ground so the clip's own leap isn't doubled.
@export var hop_speed: float = 0.0
## Seconds from button press to the slam. The animator stretches the clip to fit this.
@export var rise_time: float = 0.45
## Downward speed of the slam (m/s). Faster = punchier landing.
@export var slam_speed: float = 28.0
## Movement speed multiplier while airborne. Small but not zero, so you can nudge your landing spot.
@export_range(0.0, 1.0) var air_control: float = 0.25

@export_group("Blast")
## Everyone inside this radius (meters, from the Hulk's center) dies.
@export var kill_radius: float = 6.0
## Survivors out to this radius get knocked back.
@export var shove_radius: float = 9.0
## Upward launch speed at the center and at the edge of kill_radius.
@export var lift_center: float = 15.0
@export var lift_edge: float = 7.0
## Outward launch speed at the center and at the edge. The edge flies out more, the center flies up more.
## Center victims barely drift sideways: at 3 m/s they sailed right off the 8 m-wide bridge
## before landing, and nobody saw the splat.
@export var outward_center: float = 1.0
@export var outward_edge: float = 11.0
## Knockback speed for survivors in the outer ring.
@export var shove_speed: float = 9.0
## Trash cans, carts and barrels in the kill radius fly out this fast and this high (m/s).
## Mostly outward: a barrel popped straight up comes down on his own head.
@export var prop_outward: float = 11.0
@export var prop_lift: float = 7.0

var phase: Phase = Phase.READY
var cooldown_remaining: float = 0.0
var _timer: float = 0.0

@export_group("Presentation")
@export var impact_effect: PackedScene = preload("res://scenes/vfx/ground_stomp_effect.tscn")

@onready var hulk: Hulk = get_parent()


func _physics_process(delta: float) -> void:
	match phase:
		Phase.READY:
			if Input.is_action_just_pressed("ground_pound"):
				start()
		Phase.RISING:
			_timer -= delta
			if _timer <= 0.0:
				phase = Phase.SLAMMING
				_timer = 1.0  # Safety: never get stuck mid-air if we somehow miss the floor.
				hulk.velocity.y = -slam_speed
		Phase.SLAMMING:
			_timer -= delta
			hulk.velocity.y = -slam_speed
			if hulk.is_on_floor() or _timer <= 0.0:
				_impact()
		Phase.COOLDOWN:
			cooldown_remaining = maxf(cooldown_remaining - delta, 0.0)
			if cooldown_remaining <= 0.0:
				phase = Phase.READY


## Begins a pound. Public so tests and future input schemes can trigger it.
func start() -> void:
	if phase != Phase.READY or not hulk.can_attack():
		return
	phase = Phase.RISING
	_timer = rise_time
	hulk.velocity.y = hop_speed
	hulk.move_speed_multiplier = air_control
	hulk.health.invulnerable = true
	hulk.animator.play_pound(rise_time)
	leaped.emit()


func is_busy() -> bool:
	return phase == Phase.RISING or phase == Phase.SLAMMING


func _impact() -> void:
	phase = Phase.COOLDOWN
	cooldown_remaining = cooldown
	hulk.velocity.y = 0.0
	hulk.move_speed_multiplier = 1.0
	hulk.health.invulnerable = false
	hulk.animator.pound_landed()

	var center := hulk.global_position
	var kills := 0
	# Copy the list first: kill() removes humans from the group while we loop.
	for node in get_tree().get_nodes_in_group("enemies").duplicate():
		var human := node as Human
		var offset := human.global_position - center
		offset.y = 0.0
		var dist := offset.length()
		if dist > shove_radius:
			continue
		var away := offset / dist if dist > 0.01 else Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		if dist <= kill_radius:
			var t := dist / kill_radius  # 0 at the center, 1 at the edge
			var launch := away * lerpf(outward_center, outward_edge, t) * randf_range(0.85, 1.15)
			launch.y = lerpf(lift_center, lift_edge, t) * randf_range(0.9, 1.1)
			human.kill(launch, KillCause.STOMPED)
			kills += 1
		else:
			human.shove(away * shove_speed)

	# Bodies still in the air from an earlier hit get blown apart by the shockwave.
	var director := get_tree().get_first_node_in_group("death_director") as DeathDirector
	if director:
		var popped := 0
		for corpse in director.airborne_corpses():
			var c: Vector3 = corpse.get_center()
			if Vector2(c.x - center.x, c.z - center.z).length() <= kill_radius and c.y <= 6.0:
				corpse.explode()
				kills += 1
				popped += 1
		if popped > 0:
			juggled.emit(popped)

	# Pillars in the kill radius burst outward. Less sideways speed than a punch, the
	# hit lands low (it's a shockwave along the floor), so the tops topple and rain down.
	for node in get_tree().get_nodes_in_group("breakables"):
		var pillar := node as BreakablePillar
		if pillar == null or pillar.broken:
			continue
		var to_pillar := pillar.global_position - center
		to_pillar.y = 0.0
		if to_pillar.length() <= kill_radius + pillar.footprint_radius():
			pillar.take_hit(to_pillar, 0.5, 0.8)

	# Street junk in the blast pops up and out (and barrels light).
	for node in get_tree().get_nodes_in_group("smash_props"):
		var prop := node as SmashProp
		if prop == null or prop.state == SmashProp.State.GONE:
			continue
		var to_prop := prop.global_position - center
		to_prop.y = 0.0
		if to_prop.length() <= kill_radius:
			var away := to_prop.normalized() if to_prop.length() > 0.05 else Vector3.FORWARD
			prop.hit(away * prop_outward + Vector3.UP * prop_lift)

	_spawn_shockwave(center)
	pounded.emit(kills)


## Visuals start on the same frame as damage; their animation does not drive gameplay.
func _spawn_shockwave(center: Vector3) -> void:
	if impact_effect == null:
		return
	var effect = impact_effect.instantiate()
	effect.radius = kill_radius
	effect.pattern_seed = randi()
	hulk.get_parent().add_child(effect)
	effect.global_position = center
	effect.play()
