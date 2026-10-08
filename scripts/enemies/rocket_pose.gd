class_name RocketPose
extends SkeletonModifier3D
## The rocket soldier's procedural animation rig. Lives on his Skeleton3D, after the
## AnimationPlayer (which plays the retargeted run) and before two TwoBoneIK3D modifiers it
## creates itself:
##
##   AnimationPlayer  run cycle (legs, hips bob)
##   RocketPose       kneel (hips drop + lean), shooter's torso twist, recoil kick,
##                    and places the launcher at his right shoulder
##   ArmsIK           both hands locked to the launcher's grips, always
##   LegsIK           kneel stance (front foot planted, back knee on the ground),
##                    influence = crouch, so it blends in and out with the kneel
##
## The AI drives three numbers: crouch (0-1), recoil (kicked to 1 on fire, decays here),
## and nothing else; everything else follows.
##
## Spaces: all offsets below are in his MODEL space, which for this Mixamo/Tripo rig is
## Y up, +Z forward, his right hand side = -X. Measured from the rig (see DEVLOG):
## shoulders at y 1.25, hips 0.87, arm reach 0.57 m, thigh 0.40, shin 0.29.

const LAUNCHER := preload("res://assets/props/rocket_launcher.glb")
## Launcher model (units): tube centreline y 0.258, radius 0.112, bore at +Z (z 0.5),
## pistol grip at z 0.03, front grip at z 0.32, both ~0.1 below the tube.
const GRIP_RIGHT := Vector3(0.0, 0.08, 0.03)
const GRIP_LEFT := Vector3(0.0, 0.08, 0.32)
const MUZZLE := Vector3(0.0, 0.258, 0.52)
const BREECH := Vector3(0.0, 0.258, -0.52)

## 0 = running upright, 1 = full kneel.
var crouch: float = 0.0
## Fire kick: set to 1 on the shot, decays to 0 over recoil_time.
var recoil: float = 0.0

## Launcher size (1.0 = 1 m tube). Bigger needs longer arms: at 1.0 the front grip is ~0.53 m
## from his left shoulder with the torso twist, just inside his 0.57 m reach.
var launcher_scale: float = 1.0
## Where the launcher's origin (bottom of the tube, centre) sits relative to Spine2, in model
## space. Tube beside his helmet at shoulder height, pistol grip in front of the right shoulder.
var launcher_offset: Vector3 = Vector3(-0.27, -0.08, 0.06)
## Chest yaw (degrees) toward his right, bringing the left shoulder forward to reach the front grip.
var torso_twist: float = 30.0
## How far the hips drop (m) at full crouch, and the forward lean (degrees).
var kneel_drop: float = 0.37
var kneel_lean: float = 10.0
var recoil_time: float = 0.45
var recoil_back: float = 0.12
var recoil_pitch: float = 8.0
var recoil_lean: float = 6.0

var launcher: Node3D
var muzzle: Node3D
var breech: Node3D

var _arms: TwoBoneIK3D
var _legs: TwoBoneIK3D
var _model: Node3D
var _bones: Dictionary = {}


## Builds the launcher, grip markers and IK. Call once, after this node is a child of the skeleton.
func setup(model: Node3D) -> void:
	_model = model
	var sk := get_skeleton()
	for b in ["Hips", "Spine", "Spine1", "Spine2", "Neck", "RightArm", "RightForeArm", "RightHand",
			"LeftArm", "LeftForeArm", "LeftHand", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]:
		_bones[b] = sk.find_bone("mixamorig_" + b)

	launcher = LAUNCHER.instantiate()
	launcher.name = "Launcher"
	model.add_child(launcher)
	muzzle = _marker(launcher, "Muzzle", MUZZLE)
	breech = _marker(launcher, "Breech", BREECH)
	var grip_r := _marker(launcher, "GripRight", GRIP_RIGHT)
	var grip_l := _marker(launcher, "GripLeft", GRIP_LEFT)
	# Elbows: right elbow down and out to his right, left elbow down under the tube.
	var pole_r := _marker(launcher, "PoleRight", GRIP_RIGHT + Vector3(-0.45, -0.5, -0.25))
	var pole_l := _marker(launcher, "PoleLeft", GRIP_LEFT + Vector3(0.25, -0.55, -0.1))

	# Kneel stance targets live in model space (they move with him, not with the launcher).
	var foot_l := _marker(model, "KneelFootLeft", Vector3(0.15, 0.105, 0.45))   # Front foot flat, shin vertical.
	var foot_r := _marker(model, "KneelFootRight", Vector3(-0.14, 0.12, -0.40))  # Back shin flat on the floor.
	var knee_l := _marker(model, "KneelPoleLeft", Vector3(0.15, 0.6, 1.5))     # Front knee up and forward.
	var knee_r := _marker(model, "KneelPoleRight", Vector3(-0.13, -1.0, 0.0))  # Back knee down to the floor.

	_arms = _make_ik(sk, "ArmsIK", [
		["RightArm", "RightForeArm", "RightHand", grip_r, pole_r],
		["LeftArm", "LeftForeArm", "LeftHand", grip_l, pole_l],
	])
	_legs = _make_ik(sk, "LegsIK", [
		["LeftUpLeg", "LeftLeg", "LeftFoot", foot_l, knee_l],
		["RightUpLeg", "RightLeg", "RightFoot", foot_r, knee_r],
	])
	_legs.influence = 0.0


## Re-skin the launcher with the same painterly preset as the soldier (optional).
func painterly(style: ShaderMaterial) -> void:
	if style and launcher:
		preload("res://scripts/vfx/character_paint.gd").apply_to(launcher, style)


## Turns the whole rig off (death): the ragdoll takes over the bones from here.
func shutdown() -> void:
	active = false
	if _arms:
		_arms.active = false
	if _legs:
		_legs.active = false


func _process_modification_with_delta(delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or _model == null:
		return
	recoil = move_toward(recoil, 0.0, delta / recoil_time)
	var kick := ease(recoil, 0.4)  # Snappy out, soft settle.
	_legs.influence = clampf(crouch, 0.0, 1.0)

	# Kneel: hips straight down; legs IK does the rest.
	var hips: int = _bones.Hips
	sk.set_bone_pose_position(hips, sk.get_bone_pose_position(hips) - Vector3(0.0, kneel_drop * crouch, 0.0))
	# Lean forward when kneeling, rock back on the kick (pitch about his model X axis).
	_rotate_world(sk, _bones.Spine, Vector3.RIGHT, deg_to_rad(kneel_lean * crouch - recoil_lean * kick))
	# Shooter's twist: chest turns right (left shoulder forward), head turns back to the front.
	_rotate_world(sk, _bones.Spine1, Vector3.UP, deg_to_rad(-torso_twist * 0.5))
	_rotate_world(sk, _bones.Spine2, Vector3.UP, deg_to_rad(-torso_twist * 0.5))
	_rotate_world(sk, _bones.Neck, Vector3.UP, deg_to_rad(torso_twist * 0.8))

	# Launcher: rides on Spine2's position (bobs with the run, drops with the kneel) but keeps
	# pointing straight ahead; recoil kicks it back and up.
	var spine2 := sk.get_bone_global_pose(_bones.Spine2).origin
	var pos := spine2 + launcher_offset + Vector3(0.0, 0.03, -recoil_back) * kick
	var basis := Basis(Vector3.RIGHT, deg_to_rad(-recoil_pitch * kick)).scaled(Vector3.ONE * launcher_scale)
	launcher.global_transform = sk.global_transform * Transform3D(basis, pos)


## Rotates bone b by `angle` about a MODEL-space axis, keeping its children attached.
func _rotate_world(sk: Skeleton3D, b: int, axis: Vector3, angle: float) -> void:
	if b < 0 or is_zero_approx(angle):
		return
	var global := sk.get_bone_global_pose(b)
	var parent := sk.get_bone_parent(b)
	var parent_basis := sk.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	var turned := Basis(axis, angle) * global.basis
	sk.set_bone_pose_rotation(b, (parent_basis.inverse() * turned).get_rotation_quaternion())


func _make_ik(sk: Skeleton3D, ik_name: String, limbs: Array) -> TwoBoneIK3D:
	var ik := TwoBoneIK3D.new()
	ik.name = ik_name
	sk.add_child(ik)
	ik.setting_count = limbs.size()
	for i in limbs.size():
		var limb: Array = limbs[i]
		ik.set_root_bone_name(i, "mixamorig_" + limb[0])
		ik.set_middle_bone_name(i, "mixamorig_" + limb[1])
		ik.set_end_bone_name(i, "mixamorig_" + limb[2])
		ik.set_target_node(i, ik.get_path_to(limb[3]))
		ik.set_pole_node(i, ik.get_path_to(limb[4]))
	return ik


func _marker(parent: Node3D, marker_name: String, at: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = marker_name
	n.position = at
	parent.add_child(n)
	return n
