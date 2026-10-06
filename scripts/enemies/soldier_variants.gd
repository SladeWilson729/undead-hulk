class_name SoldierVariants
extends RefCounted
## The rigged soldier models a Human can wear. Each spawned human rolls one at random.
##
## Every soldier is two Mixamo files with that soldier's own skeleton:
##   soldier_X_run.fbx   = model + textures + Running clip (imported as a scene)
##   soldier_X_punch.fbx = Punch Combo clip only (imported as an animation library)
## The .import files scale each one to 1.8 m tall (nodes/root_scale), so there is no node
## scaling anywhere. That matters for the ragdoll: physics bodies can't be scaled.
##
## To add a soldier: run it through Mixamo with Running + Punch Combo (With Skin), drop both
## files in assets/humans/, copy an existing pair of .import files (delete their uid= lines and
## set root_scale = 1.8 / model height), and add an entry below.

const VARIANTS := [
	# run_speed: ground speed (m/s) at which the Running clip's planted foot matches the floor
	# at 1x playback. Measured from the clips (median foot speed during ground contact).
	# gib_color: main uniform color, used for this soldier's chunks when he explodes.
	{"id": "a", "run": "res://assets/humans/soldier_a_run.fbx", "punch": "res://assets/humans/soldier_a_punch.fbx",
		"run_speed": 2.7, "gib_color": Color(0.74, 0.64, 0.48)},  # Bush hat, desert camo
	{"id": "b", "run": "res://assets/humans/soldier_b_run.fbx", "punch": "res://assets/humans/soldier_b_punch.fbx",
		"run_speed": 3.4, "gib_color": Color(0.52, 0.54, 0.52)},  # Helmet, grey camo
	{"id": "c", "run": "res://assets/humans/soldier_c_run.fbx", "punch": "res://assets/humans/soldier_c_punch.fbx",
		"run_speed": 3.6, "gib_color": Color(0.70, 0.60, 0.45)},  # Cap, tan (41-bone rig, no fingers)
	{"id": "d", "run": "res://assets/humans/soldier_d_run.fbx", "punch": "res://assets/humans/soldier_d_punch.fbx",
		"run_speed": 3.4, "gib_color": Color(0.60, 0.55, 0.44)},  # Bald, tan vest
]

const HIPS_TRACK := ^"Skeleton3D:mixamorig_Hips"

# id -> {"scene": PackedScene, "library": AnimationLibrary, "gib_material": Material}
# Built once per soldier type and shared by every human wearing it, so spawning stays cheap.
static var _cache: Dictionary = {}


static func pick_random() -> Dictionary:
	return VARIANTS.pick_random()


## The loaded scene, a ready-to-use animation library ("run", "punch"), and the gib material.
static func data_for(variant: Dictionary) -> Dictionary:
	var id: String = variant.id
	if _cache.has(id):
		return _cache[id]
	var scene: PackedScene = load(variant.run)
	# The Running clip lives inside the model scene, so peek at a throwaway instance to grab it.
	var probe := scene.instantiate()
	var probe_player := find_player(probe)
	var run_anim := probe_player.get_animation(probe_player.get_animation_list()[0])
	var punch_lib: AnimationLibrary = load(variant.punch)
	var punch_anim := punch_lib.get_animation(punch_lib.get_animation_list()[0])
	var library := AnimationLibrary.new()
	library.add_animation("run", _prepare(run_anim, true))
	library.add_animation("punch", _prepare(punch_anim, false))
	probe.free()
	var gib := StandardMaterial3D.new()
	gib.albedo_color = variant.gib_color
	gib.roughness = 0.85
	_cache[id] = {"scene": scene, "library": library, "gib_material": gib}
	return _cache[id]


## Copy, set looping, and pin the hips horizontally so the clip never drags the model away
## from the CharacterBody3D that actually owns movement.
static func _prepare(source: Animation, loop: bool) -> Animation:
	var anim: Animation = source.duplicate(true)
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var track := anim.find_track(HIPS_TRACK, Animation.TYPE_POSITION_3D)
	if track >= 0 and anim.track_get_key_count(track) > 0:
		var anchor: Vector3 = anim.track_get_key_value(track, 0)
		for k in anim.track_get_key_count(track):
			var p: Vector3 = anim.track_get_key_value(track, k)
			anim.track_set_key_value(track, k, Vector3(anchor.x, p.y, anchor.z))
	return anim


static func find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := find_player(child)
		if found:
			return found
	return null


static func find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := find_skeleton(child)
		if found:
			return found
	return null
