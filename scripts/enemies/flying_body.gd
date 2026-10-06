class_name FlyingBody
extends RigidBody3D
## The "cheap death": one rigid body, one spin, carrying the human's own visual.
## DeathDirector uses this once the ragdoll cap is reached, so a huge pile of kills
## never tanks the frame rate. It splats and explodes by the same rules as a Ragdoll.
##
## Collision: layer 4 (ragdolls), mask 1 (world only).

const AIRBORNE_HEIGHT := 1.2

## Seconds before the body shrinks away and frees itself.
@export var lifetime: float = 5.0
## Tumble speed in radians/second. Higher = sillier.
@export var spin: float = 14.0
## Anything that falls below this height (off the bridge) is cleaned up immediately.
@export var kill_height: float = -30.0

var director: DeathDirector
var shirt: Material
var small_stains_left: int = 2

var _watcher: ImpactWatcher
var _shrinking: bool = false
var _removed: bool = false


func _ready() -> void:
	add_to_group("corpses")
	_watcher = ImpactWatcher.new(self)


## Called once by DeathDirector right after the body is placed in the world.
func launch(launch_velocity: Vector3) -> void:
	linear_velocity = launch_velocity
	var axis := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	angular_velocity = axis.normalized() * spin


func get_center() -> Vector3:
	return global_position


func is_airborne() -> bool:
	return not _removed and global_position.y > AIRBORNE_HEIGHT


func explode() -> void:
	if _removed:
		return
	if director:
		director.explode_at(global_position, linear_velocity, shirt)
	remove_now()


func remove_now() -> void:
	if _removed:
		return
	_removed = true
	remove_from_group("corpses")
	queue_free()


func _physics_process(delta: float) -> void:
	if _removed:
		return
	lifetime -= delta
	var impact := _watcher.sample()
	if impact > 0.0 and director:
		director.on_corpse_impact(self, global_position, impact)
	if _removed:
		return
	if global_position.y < kill_height:
		remove_now()
	elif lifetime <= 0.5 and not _shrinking:
		_shrinking = true
		var visual := get_node_or_null("Visual") as Node3D
		if visual:
			var tween := create_tween()
			tween.tween_property(visual, "scale", Vector3.ONE * 0.01, 0.5)
			tween.tween_callback(remove_now)
		else:
			remove_now()
