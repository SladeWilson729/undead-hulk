class_name AnimRetarget
extends RefCounted
## Moves a Mixamo clip from one character's skeleton to another's, when the two skeletons share
## bone names but NOT rest poses or bone axes (e.g. a Mixamo soldier clip onto the Tripo-rigged
## rocket soldier: hips differ by 90 deg, thighs by ~177 deg in their rest rotations).
##
## Copying the raw rotations would twist the target. Instead, per bone, per frame:
##   1. Sample the source pose and build each bone's WORLD rotation down the hierarchy.
##   2. Take how far that bone has turned from its own world rest:   delta = pose * rest^-1
##   3. Apply the same world turn to the target bone's world rest:    target = delta * rest_t
##   4. Convert back to a local rotation under the (already retargeted) parent.
## World space makes bone axis conventions irrelevant; only the rest SHAPE (both T-pose) matters.
##
## The hips position is kept in place horizontally (the CharacterBody owns movement). Its height
## is the clip's own hips height scaled by the ratio of the two characters' leg lengths.
## (Not by rest heights: Mixamo files can store the hips rest in a different frame from the
## clip's keys; soldier B's rest says 0.002 m while its clip says 0.71 m.)

## src_model / dst_model: the character roots, both modelled facing +Z (their own root
## transforms are ignored). Returns a new Animation whose track paths are relative to dst_model.
static func retarget(src_anim: Animation, src_model: Node3D, dst_model: Node3D, fps: float = 30.0) -> Animation:
	var src: Skeleton3D = SoldierVariants.find_skeleton(src_model)
	var dst: Skeleton3D = SoldierVariants.find_skeleton(dst_model)
	var src_prefix := "Skeleton3D:"
	var dst_prefix := String(dst_model.get_path_to(dst)) + ":"
	# Skeleton orientation relative to its character root, from the node chain (works before
	# the characters are in the scene tree, e.g. while a soldier is still being built).
	var src_space := _space(src_model, src)
	var dst_space := _space(dst_model, dst)

	var n := dst.get_bone_count()
	var map: Array[int] = []
	for b in n:
		map.append(src.find_bone(dst.get_bone_name(b)))

	var src_rest_world := _world_rest(src, src_space)
	var dst_rest_world := _world_rest(dst, dst_space)

	var out := Animation.new()
	out.length = src_anim.length
	out.loop_mode = src_anim.loop_mode
	var tracks: Array[int] = []
	for b in n:
		if map[b] < 0:
			tracks.append(-1)
			continue
		var t := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(t, NodePath(dst_prefix + dst.get_bone_name(b)))
		tracks.append(t)

	var hips_dst := dst.find_bone("mixamorig_Hips")
	var hips_src := src.find_bone("mixamorig_Hips")
	var hips_track := -1
	var hips_src_track := src_anim.find_track(NodePath(src_prefix + "mixamorig_Hips"), Animation.TYPE_POSITION_3D)
	var hips_ratio := 1.0
	if hips_dst >= 0 and hips_src >= 0 and hips_src_track >= 0:
		hips_track = out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(hips_track, NodePath(dst_prefix + "mixamorig_Hips"))
		hips_ratio = _leg_length(dst) / maxf(_leg_length(src), 0.0001)

	var frames := maxi(int(ceil(src_anim.length * fps)), 1)
	var lowest_toe := INF  # Over the whole clip, for the ground fix below.
	var toes: Array[int] = [dst.find_bone("mixamorig_LeftToeBase"), dst.find_bone("mixamorig_RightToeBase")]
	for f in frames + 1:
		var time := minf(f / fps, src_anim.length)
		# 1. Source local rotations at this time (rest where the clip has no track).
		var src_local: Array[Quaternion] = []
		for sb in src.get_bone_count():
			var st := src_anim.find_track(NodePath(src_prefix + src.get_bone_name(sb)), Animation.TYPE_ROTATION_3D)
			src_local.append(src_anim.rotation_track_interpolate(st, time) if st >= 0 else src.get_bone_rest(sb).basis.get_rotation_quaternion())
		var src_world := _world_from_local(src, src_local, src_space)
		# 2-4. Target world, then local, parents first.
		var dst_world: Array[Quaternion] = []
		dst_world.resize(n)
		var done: Array[bool] = []
		done.resize(n)
		for b in n:
			_solve(b, dst, map, src_world, src_rest_world, dst_rest_world, dst_world, done, dst_space)
		for b in n:
			if tracks[b] < 0:
				continue
			var parent := dst.get_bone_parent(b)
			var parent_world := dst_world[parent] if parent >= 0 else dst_space
			out.rotation_track_insert_key(tracks[b], time, (parent_world.inverse() * dst_world[b]).normalized())
		if hips_track >= 0:
			var p := src_anim.position_track_interpolate(hips_src_track, time)
			var rest_d := dst.get_bone_rest(hips_dst).origin
			var hips_pos := Vector3(rest_d.x, p.y * hips_ratio, rest_d.z)
			out.position_track_insert_key(hips_track, time, hips_pos)
			for toe in toes:
				if toe >= 0:
					lowest_toe = minf(lowest_toe, _bone_height(dst, toe, hips_dst, hips_pos, dst_world))
	# Different foot shapes leave the planted foot a few cm off the floor: shift the whole clip so
	# the lowest toe point of the stride is exactly at floor level.
	if hips_track >= 0 and lowest_toe < INF:
		for k in out.track_get_key_count(hips_track):
			var v: Vector3 = out.track_get_key_value(hips_track, k)
			out.track_set_key_value(hips_track, k, v - Vector3(0.0, lowest_toe, 0.0))
	return out


## Skeleton-space height of bone b's joint, given the hips position and this frame's world rotations.
static func _bone_height(sk: Skeleton3D, b: int, hips: int, hips_pos: Vector3, world: Array[Quaternion]) -> float:
	var chain: Array[int] = []
	var cur := b
	while cur >= 0 and cur != hips:
		chain.push_front(cur)
		cur = sk.get_bone_parent(cur)
	var pos := hips_pos
	for c in chain:
		pos += world[sk.get_bone_parent(c)] * sk.get_bone_rest(c).origin
	return pos.y


## Rotation of `node` relative to `root`: the product of the transforms between them.
static func _space(root: Node, node: Node3D) -> Quaternion:
	var q := Quaternion.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			q = (n as Node3D).basis.get_rotation_quaternion() * q
		n = n.get_parent()
	return q


## Thigh + shin + ankle height: how tall the hips stand on straight legs, in skeleton units.
static func _leg_length(sk: Skeleton3D) -> float:
	var total := 0.0
	for b in ["mixamorig_LeftLeg", "mixamorig_LeftFoot", "mixamorig_LeftToeBase"]:
		var i := sk.find_bone(b)
		if i >= 0:
			total += sk.get_bone_rest(i).origin.length()
	return total


static func _solve(b: int, dst: Skeleton3D, map: Array[int], src_world: Array[Quaternion], src_rest_world: Array[Quaternion],
		dst_rest_world: Array[Quaternion], dst_world: Array[Quaternion], done: Array[bool], dst_space: Quaternion) -> void:
	if done[b]:
		return
	var parent := dst.get_bone_parent(b)
	if parent >= 0:
		_solve(parent, dst, map, src_world, src_rest_world, dst_rest_world, dst_world, done, dst_space)
	var sb := map[b]
	if sb >= 0:
		var delta := src_world[sb] * src_rest_world[sb].inverse()
		dst_world[b] = (delta * dst_rest_world[b]).normalized()
	else:
		# Bone the source doesn't have: keep it at rest relative to its parent.
		var parent_world := dst_world[parent] if parent >= 0 else dst_space
		dst_world[b] = parent_world * dst.get_bone_rest(b).basis.get_rotation_quaternion()
	done[b] = true


static func _world_rest(sk: Skeleton3D, space: Quaternion) -> Array[Quaternion]:
	var local: Array[Quaternion] = []
	for b in sk.get_bone_count():
		local.append(sk.get_bone_rest(b).basis.get_rotation_quaternion())
	return _world_from_local(sk, local, space)


static func _world_from_local(sk: Skeleton3D, local: Array[Quaternion], space: Quaternion) -> Array[Quaternion]:
	var world: Array[Quaternion] = []
	world.resize(sk.get_bone_count())
	var done: Array[bool] = []
	done.resize(sk.get_bone_count())
	for b in sk.get_bone_count():
		_world_one(sk, b, local, world, done, space)
	return world


static func _world_one(sk: Skeleton3D, b: int, local: Array[Quaternion], world: Array[Quaternion], done: Array[bool], space: Quaternion) -> void:
	if done[b]:
		return
	var parent := sk.get_bone_parent(b)
	if parent >= 0:
		_world_one(sk, parent, local, world, done, space)
		world[b] = world[parent] * local[b]
	else:
		world[b] = space * local[b]
	done[b] = true


# ---------------------------------------------------------------------------------------------
# Cross-rig retargeting (other naming schemes, e.g. ActorCore / Character Creator "CC_Base_").
# ---------------------------------------------------------------------------------------------

## ActorCore / Character Creator 3+ bone names -> Mixamo names. Twist, share, face and toe
## bones have no Mixamo equivalent and are skipped (their parents carry the motion).
static func actorcore_to_mixamo() -> Dictionary:
	var m := {
		"mixamorig_Hips": "CC_Base_Pelvis",
		"mixamorig_Spine": "CC_Base_Waist",
		"mixamorig_Spine1": "CC_Base_Spine01",
		"mixamorig_Spine2": "CC_Base_Spine02",
		"mixamorig_Neck": "CC_Base_NeckTwist01",
		"mixamorig_Head": "CC_Base_Head",
	}
	for side in [["Left", "L"], ["Right", "R"]]:
		var mx: String = side[0]
		var cc: String = side[1]
		m["mixamorig_%sShoulder" % mx] = "CC_Base_%s_Clavicle" % cc
		m["mixamorig_%sArm" % mx] = "CC_Base_%s_Upperarm" % cc
		m["mixamorig_%sForeArm" % mx] = "CC_Base_%s_Forearm" % cc
		m["mixamorig_%sHand" % mx] = "CC_Base_%s_Hand" % cc
		m["mixamorig_%sUpLeg" % mx] = "CC_Base_%s_Thigh" % cc
		m["mixamorig_%sLeg" % mx] = "CC_Base_%s_Calf" % cc
		m["mixamorig_%sFoot" % mx] = "CC_Base_%s_Foot" % cc
		m["mixamorig_%sToeBase" % mx] = "CC_Base_%s_ToeBase" % cc
		for f in [["Thumb", "Thumb"], ["Index", "Index"], ["Middle", "Mid"], ["Ring", "Ring"], ["Pinky", "Pinky"]]:
			for i in [1, 2, 3]:
				m["mixamorig_%sHand%s%d" % [mx, f[0], i]] = "CC_Base_%s_%s%d" % [cc, f[1], i]
	return m


## Like retarget(), but for a source rig with different bone names AND any bone layout or
## axis convention: instead of reading keyframes, it PLAYS the clip on the source skeleton and
## reads the final world pose of each bone every frame. Root motion is dropped (the Hulk's
## CharacterBody owns movement); hips height is scaled by leg length and grounded to the toes.
##
## src_model must be inside the scene tree (to pose its skeleton). name_map: dst bone ->
## src bone. src_hips: the source bone whose height drives the hips (CC rigs: "CC_Base_Hip").
static func retarget_sampled(src_model: Node3D, clip: StringName, dst_model: Node3D, name_map: Dictionary,
		src_hips: String, fps: float = 30.0) -> Animation:
	var src: Skeleton3D = SoldierVariants.find_skeleton(src_model)
	var dst: Skeleton3D = SoldierVariants.find_skeleton(dst_model)
	var player := SoldierVariants.find_player(src_model)
	var src_anim := player.get_animation(clip)
	var dst_prefix := String(dst_model.get_path_to(dst)) + ":"
	var src_space := _space(src_model, src)
	var dst_space := _space(dst_model, dst)
	var src_xf := _space_xf(src_model, src)

	var n := dst.get_bone_count()
	var map: Array[int] = []
	for b in n:
		map.append(src.find_bone(name_map.get(dst.get_bone_name(b), "")))
	# World rest rotations: source straight from the skeleton, destination from rest chain.
	var src_rest_world: Array[Quaternion] = []
	for sb in src.get_bone_count():
		src_rest_world.append((src_space * src.get_bone_global_rest(sb).basis.get_rotation_quaternion()).normalized())
	var dst_rest_world := _world_rest(dst, dst_space)

	var out := Animation.new()
	out.length = src_anim.length
	out.loop_mode = src_anim.loop_mode
	var tracks: Array[int] = []
	for b in n:
		if map[b] < 0:
			tracks.append(-1)
			continue
		var t := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(t, NodePath(dst_prefix + dst.get_bone_name(b)))
		tracks.append(t)
	var hips_dst := dst.find_bone("mixamorig_Hips")
	var hips_src := src.find_bone(src_hips)
	var hips_track := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(hips_track, NodePath(dst_prefix + "mixamorig_Hips"))
	var src_leg := _chain_length(src, [name_map["mixamorig_LeftLeg"], name_map["mixamorig_LeftFoot"], name_map["mixamorig_LeftToeBase"]])
	var hips_ratio := _leg_length(dst) / maxf(src_leg, 0.0001)
	# Source ground: its toes at rest (the rig's root may sit at any height).
	var src_ground := minf((src_xf * src.get_bone_global_rest(src.find_bone(name_map["mixamorig_LeftToeBase"]))).origin.y,
		(src_xf * src.get_bone_global_rest(src.find_bone(name_map["mixamorig_RightToeBase"]))).origin.y)

	player.play(clip)
	player.pause()
	var frames := maxi(int(ceil(src_anim.length * fps)), 1)
	var lowest_toe := INF
	var toes: Array[int] = [dst.find_bone("mixamorig_LeftToeBase"), dst.find_bone("mixamorig_RightToeBase")]
	for f in frames + 1:
		var time := minf(f / fps, src_anim.length)
		player.seek(time, true)
		src.force_update_all_bone_transforms()
		var src_world: Array[Quaternion] = []
		for sb in src.get_bone_count():
			src_world.append((src_space * src.get_bone_global_pose(sb).basis.get_rotation_quaternion()).normalized())
		var dst_world: Array[Quaternion] = []
		dst_world.resize(n)
		var done: Array[bool] = []
		done.resize(n)
		for b in n:
			_solve(b, dst, map, src_world, src_rest_world, dst_rest_world, dst_world, done, dst_space)
		for b in n:
			if tracks[b] < 0:
				continue
			var parent := dst.get_bone_parent(b)
			var parent_world := dst_world[parent] if parent >= 0 else dst_space
			out.rotation_track_insert_key(tracks[b], time, (parent_world.inverse() * dst_world[b]).normalized())
		var src_hip_y := (src_xf * src.get_bone_global_pose(hips_src)).origin.y - src_ground
		var rest_d := dst.get_bone_rest(hips_dst).origin
		var hips_pos := Vector3(rest_d.x, src_hip_y * hips_ratio, rest_d.z)
		out.position_track_insert_key(hips_track, time, hips_pos)
		for toe in toes:
			if toe >= 0:
				lowest_toe = minf(lowest_toe, _bone_height(dst, toe, hips_dst, hips_pos, dst_world))
	if lowest_toe < INF:
		for k in out.track_get_key_count(hips_track):
			var v: Vector3 = out.track_get_key_value(hips_track, k)
			out.track_set_key_value(hips_track, k, v - Vector3(0.0, lowest_toe, 0.0))
	player.stop()
	return out


## Full transform of `node` relative to `root` (rotation, scale and offset), from the node chain.
static func _space_xf(root: Node, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Sum of rest bone offsets for a chain of named bones (leg length in skeleton units).
static func _chain_length(sk: Skeleton3D, names: Array) -> float:
	var total := 0.0
	for nm in names:
		var i := sk.find_bone(nm)
		if i >= 0:
			total += sk.get_bone_rest(i).origin.length()
	return total
