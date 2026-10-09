class_name HeadScale
extends SkeletonModifier3D
## Scales one bone (the head) on top of whatever the animation or ragdoll is doing.
## Used by the Bobbleheads augment. Set `factor` to grow or pop the head.
##
## A SkeletonModifier3D runs after the AnimationPlayer every frame, so the clip can't undo it.
## On death the ragdoll adds its PhysicalBoneSimulator3D (another modifier) to the same
## skeleton; modifiers run in child order, so this node moves itself to the end to stay last
## and keep the corpse's head big.

@export var bone_name: String = "mixamorig_Head"
@export var factor: float = 3.0

var _bone: int = -1


func _ready() -> void:
	var sk := get_skeleton()
	if sk:
		_bone = sk.find_bone(bone_name)


func _process(_delta: float) -> void:
	var parent := get_parent()
	if parent and get_index() != parent.get_child_count() - 1:
		parent.move_child.call_deferred(self, -1)


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _bone < 0:
		return
	sk.set_bone_pose_scale(_bone, Vector3.ONE * factor)


## Bone's current world position (for spawning the pop burst at the head).
func head_position() -> Vector3:
	var sk := get_skeleton()
	if sk == null or _bone < 0:
		return Vector3.ZERO
	return sk.global_transform * sk.get_bone_global_pose(_bone).origin


## Adds a HeadScale to the character's skeleton (once). Returns it.
static func attach(model: Node, scale_factor: float) -> HeadScale:
	var sk := SoldierVariants.find_skeleton(model)
	if sk == null or sk.find_bone("mixamorig_Head") < 0:
		return null
	for child in sk.get_children():
		if child is HeadScale:
			(child as HeadScale).factor = scale_factor
			return child
	var hs := HeadScale.new()
	hs.name = "HeadScale"
	hs.factor = scale_factor
	sk.add_child(hs)
	return hs
