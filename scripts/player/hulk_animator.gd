class_name HulkAnimator
extends Node
## Drives the Hulk model's animations. Gameplay never waits on animation: attacks keep their
## own timers (PunchAttack, GroundPound) and tell this node what to show. This node lines the
## clips up so the visual impact lands on the same frame as the gameplay impact.
##
## All ten FBX files come from Mixamo with the same character and skeleton, so their tracks
## ("Skeleton3D:mixamorig_*") plug straight into the model's AnimationPlayer. No retargeting.
##
## Clip timings below were measured from the files (hand reach and hip height over time).

## Emitted when the victory roar actually starts playing (not when it's queued).
signal victory_started

const IDLE_SCENE_ANIM := "mixamo_com"  # The idle clip ships inside hulk_idle.fbx, the model itself.
const CLIP_FILES := {
	"walk": "res://assets/hulk/hulk_walk.fbx",
	"punch_a": "res://assets/hulk/hulk_punch_a.fbx",
	"punch_b": "res://assets/hulk/hulk_punch_b.fbx",
	"pound": "res://assets/hulk/hulk_jump_attack.fbx",
	"death": "res://assets/hulk/Death.fbx",
	"victory": "res://assets/hulk/victory.fbx",
	"lift": "res://assets/hulk/Overhead Squat.fbx",
	"throw": "res://assets/hulk/Throw In.fbx",
	"pickup": "res://assets/hulk/Picking Up.fbx",
	"eat": "res://assets/hulk/eating.fbx",
}
## Bones driven by the carry pose (arms, spine, head) when we build carry_idle / carry_walk.
## Matched by substring: "Arm" also catches ForeArm, "Hand" catches every finger bone.
const UPPER_BODY := ["Spine", "Neck", "Head", "Shoulder", "Arm", "Hand"]
## Clips that keep their baked travel. The death fall carries him ~1.7 m back as he goes down;
## pinning the hips would make him topple in place and slide his feet.
const KEEP_ROOT_MOTION := ["death"]
const HIPS_TRACK := ^"Skeleton3D:mixamorig_Hips"

## The model node (instance of hulk_idle.fbx) whose AnimationPlayer we drive.
@export var model: Node3D

@export_group("Locomotion")
## Ground speed (m/s) at which the walk clip's feet match the floor at 1x playback.
## Measured: 0.398 m/s in model units x 4.71 model scale.
@export var walk_natural_speed: float = 1.88
## Above this playback rate the walk looks frantic, so we cap it and accept a little foot slide.
## A proper run clip would remove the slide (see DEVLOG).
@export var max_walk_playback: float = 2.4
## Below this speed (m/s) the Hulk counts as standing still.
@export var idle_threshold: float = 0.6
@export var locomotion_blend: float = 0.2

@export_group("Punch clips")
## In both Zombie Punching clips the big haymaker lands at ~1.2 s (punch_a: right hand, punch_b: left hand).
@export var punch_impact_time: float = 1.2
## Where we cut back to idle/walk after the haymaker.
@export var punch_end_time: float = 1.7
## Playback rate during a punch. 3x keeps the windup at ~0.07 s of real time.
@export var punch_speed: float = 3.0

@export_group("Pound clip")
## Jump Attack: crouch ends ~0.45 s, airborne ~0.6-1.4 s, hands hit the floor ~1.65 s.
@export var pound_start_time: float = 0.45
@export var pound_impact_time: float = 1.65
@export var pound_end_time: float = 2.5
## Playback rate after the slam lands (the recovery crouch).
@export var pound_recover_speed: float = 1.6

@export_group("Victory clip")
## Victory: still for ~0.4 s, right-arm pump 0.6-1.6 s, three double-arm roars peaking at
## ~2.4, 3.3 and 4.2 s, settled by ~5.4 s, then 0.8 s of dead frames. The clip also drifts
## ~2 m backward, which the hips pin removes.
@export var victory_start_time: float = 0.35
@export var victory_end_time: float = 5.4
## Blend in slowly so the celebration eases out of whatever he was doing.
@export var victory_blend: float = 0.3

@export_group("Carry clips")
## Overhead Squat: squats to the floor (hands down ~2.3-3.6 s), stands with the load
## (3.9-4.6 s), presses it overhead (4.6-5.1 s), holds (hands ~4.4 m up at 5.8 s).
## We start in the squat with hands on the car and skip the slow walk-up.
@export var lift_start_time: float = 3.5
@export var lift_speed: float = 2.5
## Throw In: hands fully overhead ~1.1 s, snap forward ~1.5 s, follow-through to ~2.2 s.
## The clip lunges ~5.5 m forward; the hips pin keeps him in place.
@export var throw_start_time: float = 1.0
## The car leaves his hands here.
@export var throw_release_time: float = 1.5
@export var throw_end_time: float = 2.2
@export var throw_speed: float = 2.0

@export_group("Eat clips")
## Picking Up: bends from ~0.4 s, right hand on the floor ~1.6 m ahead at ~1.25 s (the grab),
## back up with the hand at chest height by ~2.4 s. Right hand only.
@export var pickup_start_time: float = 0.4
@export var pickup_grab_time: float = 1.25
@export var pickup_end_time: float = 2.4
@export var pickup_speed: float = 2.0
## eating: opens with the right hand at his mouth, closest at ~0.45 s (the chomp), then
## lowers to his chest by ~1.3 s.
@export var eat_start_time: float = 0.0
@export var eat_chomp_time: float = 0.45
@export var eat_end_time: float = 1.3
@export var eat_speed: float = 1.5

var _ap: AnimationPlayer
var _in_action: bool = false
var _action_end: float = 0.0
var _dead: bool = false
## A cleared wave sets this; the victory plays the next time he is standing still.
var _victory_pending: bool = false
## Holding a car: locomotion uses carry_idle / carry_walk.
var _carrying: bool = false


func _ready() -> void:
	_ap = _find_player(model)
	var lib := AnimationLibrary.new()
	lib.add_animation("idle", _prepare(_ap.get_animation(IDLE_SCENE_ANIM), true))
	for clip_name in CLIP_FILES:
		var source: AnimationLibrary = load(CLIP_FILES[clip_name])
		var anim := source.get_animation(source.get_animation_list()[0])
		lib.add_animation(clip_name, _prepare(anim, clip_name == "walk", clip_name not in KEEP_ROOT_MOTION))
	# Carry locomotion: idle/walk legs with the arms locked overhead in the lift's final pose.
	var lift := lib.get_animation("lift")
	lib.add_animation("carry_idle", _with_upper_body(lib.get_animation("idle"), lift, lift.length))
	lib.add_animation("carry_walk", _with_upper_body(lib.get_animation("walk"), lift, lift.length))
	_ap.add_animation_library("hulk", lib)
	_ap.play("hulk/idle")


## Call every physics frame with the Hulk's horizontal speed. Ignored while an attack plays.
func update_locomotion(speed: float) -> void:
	if _dead:
		return
	if _in_action:
		if _ap.current_animation_position >= _action_end or not _ap.is_playing():
			_in_action = false
		elif is_celebrating() and speed > idle_threshold:
			# Moving cancels the celebration on the spot. The player never waits on it.
			_in_action = false
		else:
			return
	if _victory_pending and speed <= idle_threshold and not _carrying:
		_victory_pending = false
		_start_action("hulk/victory", victory_start_time, 1.0, victory_end_time, victory_blend)
		victory_started.emit()
		return
	if speed > idle_threshold:
		_play_if_new("hulk/carry_walk" if _carrying else "hulk/walk", locomotion_blend)
		_ap.speed_scale = clampf(speed / walk_natural_speed, 0.6, max_walk_playback)
	else:
		_play_if_new("hulk/carry_idle" if _carrying else "hulk/idle", locomotion_blend)
		_ap.speed_scale = 1.0


## left = true swings the left-hand haymaker (punch_b), false the right (punch_a).
## windup = real seconds until the gameplay hit lands; the clip is started early enough
## that the fist reaches full extension on that exact frame.
func play_punch(left: bool, windup: float) -> void:
	var clip := "hulk/punch_b" if left else "hulk/punch_a"
	_start_action(clip, punch_impact_time - windup * punch_speed, punch_speed, punch_end_time, 0.05)


## windup = real seconds from takeoff to the slam (GroundPound.rise_time).
func play_pound(windup: float) -> void:
	var rate := (pound_impact_time - pound_start_time) / maxf(windup, 0.05)
	_start_action("hulk/pound", pound_start_time, rate, pound_end_time, 0.08)


## Squat, grab, press overhead. Returns real seconds until the car is up (CarryThrow
## won't allow a throw before then). Afterwards locomotion switches to the carry clips.
func play_lift() -> float:
	_carrying = true
	var length := _ap.get_animation("hulk/lift").length
	_start_action("hulk/lift", lift_start_time, lift_speed, length - 0.02, 0.12)
	return (length - lift_start_time) / lift_speed


## The heave. Returns real seconds until the release frame, when CarryThrow lets go.
func play_throw() -> float:
	_carrying = false
	_start_action("hulk/throw", throw_start_time, throw_speed, throw_end_time, 0.08)
	return (throw_release_time - throw_start_time) / throw_speed


## Bend down for a soldier. Returns real seconds until the hand reaches the floor (the grab).
func play_pickup() -> float:
	_start_action("hulk/pickup", pickup_start_time, pickup_speed, pickup_end_time, 0.1)
	return (pickup_grab_time - pickup_start_time) / pickup_speed


## Real seconds the pickup takes from start to standing back up.
func pickup_duration() -> float:
	return (pickup_end_time - pickup_start_time) / pickup_speed


## Hand to mouth. Returns real seconds until the chomp.
func play_eat() -> float:
	_start_action("hulk/eat", eat_start_time, eat_speed, eat_end_time, 0.15)
	return (eat_chomp_time - eat_start_time) / eat_speed


func eat_duration() -> float:
	return (eat_end_time - eat_start_time) / eat_speed


func is_carrying() -> bool:
	return _carrying


## Wave cleared. The celebration waits until he stands still (a punch or walk in progress
## finishes first), so it never yanks control away mid-move.
func queue_victory() -> void:
	if not _dead:
		_victory_pending = true


## Next wave started: drop a celebration that never got to play, and cut one that is playing.
func cancel_victory() -> void:
	_victory_pending = false
	if is_celebrating():
		_in_action = false


func is_celebrating() -> bool:
	return _in_action and _ap.current_animation == "hulk/victory"


## Plays the death fall once and holds the last frame. Nothing else plays after this.
func play_death() -> void:
	_dead = true
	_victory_pending = false
	_carrying = false
	_in_action = true
	_ap.speed_scale = 1.0
	_ap.play("hulk/death", 0.1)


## Called on the gameplay impact frame: snap to the clip's slam pose and play the recovery.
func pound_landed() -> void:
	if _ap.current_animation == "hulk/pound":
		_ap.seek(pound_impact_time, true)
		_ap.speed_scale = pound_recover_speed


func _start_action(clip: String, from_time: float, rate: float, end_time: float, blend: float) -> void:
	_ap.play(clip, blend)
	_ap.seek(maxf(from_time, 0.0), true)
	_ap.speed_scale = rate
	_in_action = true
	_action_end = end_time


func _play_if_new(clip: String, blend: float) -> void:
	if _ap.current_animation != clip:
		_ap.play(clip, blend)


## Copies a clip so the imported resource stays untouched, sets looping, and pins the hips
## horizontally. Mixamo bakes travel into the hips (Jump Attack moves him ~3 m forward);
## the CharacterBody3D owns movement, so the animation must stay in place.
func _prepare(source: Animation, loop: bool, pin_hips: bool = true) -> Animation:
	var anim: Animation = source.duplicate(true)
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var track := anim.find_track(HIPS_TRACK, Animation.TYPE_POSITION_3D)
	if pin_hips and track >= 0 and anim.track_get_key_count(track) > 0:
		var anchor: Vector3 = anim.track_get_key_value(track, 0)
		for k in anim.track_get_key_count(track):
			var p: Vector3 = anim.track_get_key_value(track, k)
			anim.track_set_key_value(track, k, Vector3(anchor.x, p.y, anchor.z))
	return anim


## Copy of `base` where every upper-body bone is held still at `pose`'s frame `time`.
## Tracks missing from `base` (Godot strips tracks that never move) are added, so the
## arms can't keep whatever pose the previous clip left them in.
func _with_upper_body(base: Animation, pose: Animation, time: float) -> Animation:
	var anim: Animation = base.duplicate(true)
	for s in pose.get_track_count():
		var path := pose.track_get_path(s)
		var bone := String(path).get_slice(":", 1)
		if not UPPER_BODY.any(func(hint: String) -> bool: return bone.contains(hint)):
			continue
		var type := pose.track_get_type(s)
		var value: Variant
		match type:
			Animation.TYPE_ROTATION_3D:
				value = pose.rotation_track_interpolate(s, time)
			Animation.TYPE_POSITION_3D:
				value = pose.position_track_interpolate(s, time)
			Animation.TYPE_SCALE_3D:
				value = pose.scale_track_interpolate(s, time)
			_:
				continue
		var t := anim.find_track(path, type)
		if t < 0:
			t = anim.add_track(type)
			anim.track_set_path(t, path)
		else:
			while anim.track_get_key_count(t) > 0:
				anim.track_remove_key(t, 0)
		anim.track_insert_key(t, 0.0, value)
	return anim


static func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found:
			return found
	return null
