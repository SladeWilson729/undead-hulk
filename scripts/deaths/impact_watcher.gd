class_name ImpactWatcher
extends RefCounted
## Tracks one rigid body and reports how hard it just hit something.
## Shared by Ragdoll and FlyingBody so both splat by the same rule.
##
## HOW: compare this frame's velocity with last frame's. Flying freely, velocity only changes
## by gravity (about 0.16 m/s per frame). Slamming into the floor or a wall changes it by
## 10+ m/s in one frame. That jump IS the impact strength. No contact monitoring needed,
## which keeps it cheap with dozens of bodies in the air.

var body: RigidBody3D
var _prev_velocity: Vector3
var _primed: bool = false


func _init(watched: RigidBody3D) -> void:
	body = watched


## Call once per physics frame. Returns the impact strength in m/s (0 when flying freely).
func sample() -> float:
	var v := body.linear_velocity
	if not _primed:
		# First frame: the body was just launched, so there's no real "previous" velocity yet.
		_primed = true
		_prev_velocity = v
		return 0.0
	var change := (_prev_velocity - v).length()
	_prev_velocity = v
	return change
