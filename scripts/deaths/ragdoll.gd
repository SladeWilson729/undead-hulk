class_name Ragdoll
extends Node3D
## A dead soldier, simulated on his own skeleton. DeathDirector moves the soldier's model under
## this node, then setup() builds physics bodies for 11 main bones and lets physics take over.
## The body that flies is the exact soldier who got hit, mid-stride, same pose.
##
## WHY build the bones in code instead of in each model's scene: there are four soldiers (and a
## 41-bone rig among them). One bone list that finds the bones by name works for all of them,
## and for any Mixamo soldier added later.
##
## Bones collide with the world only (layer 4 "ragdolls", mask 1): they never block the Hulk or
## the living swarm, which keeps the simulation cheap.

## Torso height (meters) above which the body counts as "in the air" for juggle explosions.
const AIRBORNE_HEIGHT := 1.2

## [bone, the bone its capsule reaches toward, capsule radius, mass]
## Names are Mixamo's, minus the "mixamorig_" prefix.
const BONES := [
	["Hips", "Spine1", 0.14, 12.0],
	["Spine1", "Neck", 0.16, 14.0],
	["Head", "HeadTop_End", 0.12, 5.0],
	["LeftArm", "LeftForeArm", 0.06, 2.5],
	["LeftForeArm", "LeftHand", 0.05, 1.5],
	["RightArm", "RightForeArm", 0.06, 2.5],
	["RightForeArm", "RightHand", 0.05, 1.5],
	["LeftUpLeg", "LeftLeg", 0.08, 6.0],
	["LeftLeg", "LeftFoot", 0.06, 4.0],
	["RightUpLeg", "RightLeg", 0.08, 6.0],
	["RightLeg", "RightFoot", 0.06, 4.0],
]
const PREFIX := "mixamorig_"

## Seconds before the body sinks through the floor and is removed.
@export var lifetime: float = 6.0

var director: DeathDirector
var gib_material: Material
## Light impacts leave a small stain. Capped per body so a flopping corpse can't paint the whole floor.
var small_stains_left: int = 2
## The chest body. Used as the corpse's center for juggles and explosions.
var torso: PhysicalBone3D

var _skeleton: Skeleton3D
var _sim: PhysicalBoneSimulator3D
var _bodies: Array[PhysicalBone3D] = []
# One watcher per body part. Watching only the torso misses most landings: limbs hit the
# floor first and cushion it, so the torso barely registers a bump.
var _watchers: Array[ImpactWatcher] = []
var _sinking: bool = false
var _removed: bool = false


func _ready() -> void:
	add_to_group("corpses")


## Called by DeathDirector after the soldier's Visual node has been moved under this ragdoll.
func setup(visual: Node3D, material: Material, owner_director: DeathDirector) -> void:
	director = owner_director
	gib_material = material
	# Freeze the animation on its current frame: the ragdoll starts from the exact pose he died in.
	var player := SoldierVariants.find_player(visual)
	if player:
		player.pause()
	_skeleton = SoldierVariants.find_skeleton(visual)
	_sim = PhysicalBoneSimulator3D.new()
	_skeleton.add_child(_sim)
	for spec in BONES:
		var body := _make_body(spec[0], spec[1], spec[2], spec[3])
		if body:
			_sim.add_child(body)
			_bodies.append(body)
			_watchers.append(ImpactWatcher.new(body))
			if spec[0] == "Spine1":
				torso = body
	_sim.physical_bones_start_simulation()


## Every part gets the launch velocity (so joints don't yank on the first frame) plus a little
## noise so the limbs flail. The chest gets the spin.
func launch(launch_velocity: Vector3) -> void:
	for body in _bodies:
		var jitter := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 1.5
		body.linear_velocity = launch_velocity + jitter
	if torso:
		var axis := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		torso.angular_velocity = axis * randf_range(5.0, 9.0)


func get_center() -> Vector3:
	return torso.global_position if torso else global_position


func is_airborne() -> bool:
	return not _removed and not _sinking and get_center().y > AIRBORNE_HEIGHT


func get_velocity() -> Vector3:
	return torso.linear_velocity if torso else Vector3.ZERO


## Glitter Bomb: the body bursts into confetti instead of gore.
func confetti() -> void:
	if _removed:
		return
	if director:
		director.confetti_at(get_center(), get_velocity())
	remove_now()


## Juggle hit: blow the body into gibs.
func explode() -> void:
	if _removed:
		return
	if director:
		director.explode_at(get_center(), torso.linear_velocity if torso else Vector3.ZERO, gib_material)
	remove_now()


## Removes the body immediately (used by splat and explode).
func remove_now() -> void:
	if _removed:
		return
	_removed = true
	remove_from_group("corpses")
	queue_free()


func _physics_process(delta: float) -> void:
	if _removed or _bodies.is_empty():
		return
	lifetime -= delta
	if not _sinking:
		# The hardest-hit part this frame decides the impact (and where the stain goes).
		var impact := 0.0
		var where := get_center()
		for w in _watchers:
			var s := w.sample()
			if director and s >= director.comic_min_speed:
				var wall := w.wall_contact(director.comic_min_speed)
				if not wall.is_empty():
					director.show_wall_comic(self,wall.position,wall.normal,s)
			if s > impact:
				impact = s
				where = w.body.global_position
		if impact > 0.0 and director:
			director.on_corpse_impact(self, where, impact)
		if _removed:
			return  # The impact may have splatted us.
	if get_center().y < -30.0:
		remove_now()
	elif lifetime <= 0.0 and not _sinking:
		# Clean-up: stop colliding with the floor so the body drops out of sight, then free it.
		_sinking = true
		remove_from_group("corpses")
		for body in _bodies:
			body.collision_mask = 0
		get_tree().create_timer(1.0).timeout.connect(remove_now)


## Builds one physics body: a capsule laid along the bone, from the bone toward `tip`,
## jointed to the nearest parent bone that also has a body.
func _make_body(bone: String, tip: String, radius: float, mass: float) -> PhysicalBone3D:
	var bone_idx := _skeleton.find_bone(PREFIX + bone)
	var tip_idx := _skeleton.find_bone(PREFIX + tip)
	if bone_idx < 0 or tip_idx < 0:
		push_warning("Ragdoll: bone %s or %s missing on %s" % [bone, tip, _skeleton.get_parent().name])
		return null
	var bone_pose := _skeleton.get_bone_global_pose(bone_idx)
	var tip_pos := _skeleton.get_bone_global_pose(tip_idx).origin
	# Direction and length of the capsule, in the bone's own space.
	var local_span := bone_pose.affine_inverse() * tip_pos
	var length := local_span.length()
	var align := _basis_with_y(local_span.normalized())

	var body := PhysicalBone3D.new()
	body.name = "Body_" + bone
	body.bone_name = PREFIX + bone
	# Capsule centered halfway along the bone, its long (Y) axis along the bone.
	body.body_offset = Transform3D(align, local_span * 0.5)
	# The joint sits at the bone's head, i.e. half a length back down the capsule.
	body.joint_offset = Transform3D(Basis(), Vector3(0.0, -length * 0.5, 0.0))
	body.joint_type = PhysicalBone3D.JOINT_TYPE_CONE if bone != "Hips" else PhysicalBone3D.JOINT_TYPE_NONE
	body.mass = mass
	body.friction = 0.8
	body.bounce = 0.2
	body.collision_layer = 8  # ragdolls
	body.collision_mask = 1   # world only
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(length + radius, radius * 2.0 + 0.01)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	return body


## A rotation whose Y axis points along `y` (capsules are built along Y).
static func _basis_with_y(y: Vector3) -> Basis:
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)
