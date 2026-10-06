class_name ImpactWatcher
extends RefCounted
## Tracks one rigid body and reports how hard it just hit something.
## Shared by Ragdoll and FlyingBody so both splat by the same rule.
##
## HOW: compare this frame's velocity with last frame's. Flying freely, velocity only changes
## by gravity (about 0.16 m/s per frame). Slamming into the floor or a wall changes it by
## 10+ m/s in one frame. That jump IS the impact strength. No contact monitoring needed,
## which keeps it cheap with dozens of bodies in the air.

## A RigidBody3D or a ragdoll PhysicalBone3D: anything with a linear_velocity.
var body: PhysicsBody3D
var _prev_velocity: Vector3
var _primed: bool = false
var _incoming := Vector3.ZERO
var _velocity_change := Vector3.ZERO


func _init(watched: PhysicsBody3D) -> void:
	body = watched


## Call once per physics frame. Returns the impact strength in m/s (0 when flying freely).
func sample() -> float:
	var v: Vector3 = body.get("linear_velocity")
	if not _primed:
		# First frame: the body was just launched, so there's no real "previous" velocity yet.
		_primed = true
		_prev_velocity = v
		return 0.0
	_incoming = _prev_velocity
	_velocity_change = _prev_velocity - v
	var change := _velocity_change.length()
	_prev_velocity = v
	return change


## Confirm a sharp horizontal stop against nearby world geometry, excluding floors.
## Called after sample(). Joint motion alone is not enough to produce a comic burst.
func wall_contact(min_speed: float) -> Dictionary:
	var horizontal := Vector3(_incoming.x,0.0,_incoming.z)
	if horizontal.length() < min_speed or Vector2(_velocity_change.x,_velocity_change.z).length() < min_speed:
		return {}
	var origin := body.global_position
	var query := PhysicsRayQueryParameters3D.create(origin,origin+horizontal.normalized()*0.85,1)
	var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or absf(hit.normal.y) > 0.35:
		return {}
	if -_incoming.dot(hit.normal) < min_speed or -_velocity_change.dot(hit.normal) < min_speed:
		return {}
	return hit
