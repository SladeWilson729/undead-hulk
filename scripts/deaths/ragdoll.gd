class_name Ragdoll
extends Node3D
## A dead human as six jointed rigid bodies: torso, head, two arms, two legs.
## The layout matches human.tscn part for part, so the swap from alive to dead is seamless.
##
## WHY jointed bodies and not PhysicalBoneSimulator3D: Godot's bone ragdolls need a rigged,
## skinned model, and the art pass (step 8) hasn't happened yet. When real models arrive,
## only this scene and script change. DeathDirector and everything that calls it stay the same.
##
## Parts collide with the world only (layer 4, mask 1). They pass through each other, the Hulk,
## and living humans, which keeps the simulation cheap and stable.

## Torso height (meters) above which the body counts as "in the air" for juggle explosions.
const AIRBORNE_HEIGHT := 1.2

## Seconds before the body shrinks away.
@export var lifetime: float = 6.0

var director: DeathDirector
## Light impacts leave a small stain. Capped per body so a flopping corpse can't paint the whole floor.
var small_stains_left: int = 2

# One watcher per part. Measuring only the torso missed most landings: the limbs hit
# the floor first and cushion it, so the torso barely registers a bump.
var _watchers: Array[ImpactWatcher] = []
var _parts: Array[RigidBody3D] = []
var _fading: bool = false
var _removed: bool = false

@onready var torso: RigidBody3D = $Torso


func _ready() -> void:
	add_to_group("corpses")
	for child in get_children():
		if child is RigidBody3D:
			_parts.append(child)
	for part in _parts:
		_watchers.append(ImpactWatcher.new(part))


## Called by DeathDirector right after placing us. Paints the shirt to match the living human.
func setup(shirt: Material, owner_director: DeathDirector) -> void:
	director = owner_director
	for path in ["Torso/Mesh", "ArmL/Mesh", "ArmR/Mesh"]:
		(get_node(path) as MeshInstance3D).material_override = shirt


## Every part gets the same velocity (so the joints don't yank on launch) plus a little noise
## so limbs flail. The torso gets the spin.
func launch(launch_velocity: Vector3) -> void:
	for part in _parts:
		part.reset_physics_interpolation()
		var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 1.5
		part.linear_velocity = launch_velocity + jitter
	var axis := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	torso.angular_velocity = axis * randf_range(5.0, 9.0)


func get_center() -> Vector3:
	return torso.global_position


func is_airborne() -> bool:
	return not _removed and torso.global_position.y > AIRBORNE_HEIGHT


## Juggle hit: blow the body into gibs.
func explode() -> void:
	if _removed:
		return
	director.explode_at(get_center(), torso.linear_velocity, (get_node("Torso/Mesh") as MeshInstance3D).material_override)
	remove_now()


## Removes the body immediately (used by splat and explode).
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
	# The hardest-hit part this frame decides the impact (and where the stain goes).
	var impact := 0.0
	var where := torso.global_position
	for w in _watchers:
		var s := w.sample()
		if s > impact:
			impact = s
			where = w.body.global_position
	if impact > 0.0 and director:
		director.on_corpse_impact(self, where, impact)
	if _removed:
		return  # The impact may have splatted us.
	if torso.global_position.y < -30.0:
		remove_now()
	elif lifetime <= 0.5 and not _fading:
		_fading = true
		var tween := create_tween().set_parallel(true)
		for part in _parts:
			tween.tween_property(part.get_node("Mesh"), "scale", Vector3.ONE * 0.01, 0.5)
		tween.chain().tween_callback(remove_now)
