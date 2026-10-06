class_name RubbleChunk
extends RigidBody3D
## One piece of a smashed BreakablePillar. Flies, hurts soldiers, settles, then sinks away.
##
## Collision: layer 6 (debris, value 32). Mask = world (1) + enemies (4) + debris (32).
## WHY not the player: the Hulk walks through rubble. Getting snagged on a brick after
## every smash would feel terrible, and the Hulk is the one doing the smashing anyway.
## Soldiers don't mask debris either, so the push is one way: chunks bounce off soldiers
## (and kill them), soldiers never trip over chunks.

const LAYER_DEBRIS := 32

## A chunk moving at least this fast (m/s) kills any soldier it touches.
## Falling from the top of a 4 m pillar lands at ~8 m/s, so the rain of bricks counts.
var kill_speed: float = 6.0
## Seconds before the chunk sinks into the floor and frees itself. 0 = stays forever.
var lifetime: float = 8.0

var _prev_velocity: Vector3 = Vector3.ZERO
var _still_time: float = 0.0
var _resting: bool = false
var _sinking: bool = false


func _ready() -> void:
	collision_layer = LAYER_DEBRIS
	collision_mask = 1 | 4 | LAYER_DEBRIS
	# body_entered needs contact monitoring; 4 contacts is plenty for a box.
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	# Stored BEFORE the physics step. body_entered fires after the step, when the bounce
	# has already killed the speed, so this is the speed the chunk actually hit with.
	_prev_velocity = linear_velocity
	if lifetime > 0.0:
		lifetime -= delta
		if lifetime <= 0.0:
			_sink()
	if _resting:
		return
	if linear_velocity.length() < 0.3 and angular_velocity.length() < 0.6:
		_still_time += delta
		if _still_time > 0.4:
			_rest()
	else:
		_still_time = 0.0


func _on_body_entered(body: Node) -> void:
	var human := body as Human
	if human == null or _prev_velocity.length() < kill_speed:
		return
	# Carry the brick's momentum into the corpse, with a little pop so it reads as a hit.
	human.kill(_prev_velocity * 0.9 + Vector3.UP * 3.0)


## Settled: becomes scenery. Frozen with collision off, so a pile of rubble costs nothing.
func _rest() -> void:
	_resting = true
	freeze = true
	collision_layer = 0
	collision_mask = 0
	contact_monitor = false


func _sink() -> void:
	if _sinking:
		return
	_sinking = true
	_rest()
	var tween := create_tween()
	tween.tween_property(self, "global_position:y", global_position.y - 1.0, 1.0)
	tween.tween_callback(queue_free)
