class_name HulkAnimator
extends Node
## Drives the Hulk model's animations. Gameplay never waits on animation: attacks keep their
## own timers (PunchAttack, GroundPound) and tell this node what to show. This node lines the
## clips up so the visual impact lands on the same frame as the gameplay impact.
##
## All five FBX files come from Mixamo with the same character and skeleton, so their tracks
## ("Skeleton3D:mixamorig_*") plug straight into the model's AnimationPlayer. No retargeting.
##
## Clip timings below were measured from the files (hand reach and hip height over time).

const IDLE_SCENE_ANIM := "mixamo_com"  # The idle clip ships inside hulk_idle.fbx, the model itself.
const CLIP_FILES := {
	"walk": "res://assets/hulk/hulk_walk.fbx",
	"punch_a": "res://assets/hulk/hulk_punch_a.fbx",
	"punch_b": "res://assets/hulk/hulk_punch_b.fbx",
	"pound": "res://assets/hulk/hulk_jump_attack.fbx",
}
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

var _ap: AnimationPlayer
var _in_action: bool = false
var _action_end: float = 0.0


func _ready() -> void:
	_ap = _find_player(model)
	var lib := AnimationLibrary.new()
	lib.add_animation("idle", _prepare(_ap.get_animation(IDLE_SCENE_ANIM), true))
	for clip_name in CLIP_FILES:
		var source: AnimationLibrary = load(CLIP_FILES[clip_name])
		var anim := source.get_animation(source.get_animation_list()[0])
		lib.add_animation(clip_name, _prepare(anim, clip_name == "walk"))
	_ap.add_animation_library("hulk", lib)
	_ap.play("hulk/idle")


## Call every physics frame with the Hulk's horizontal speed. Ignored while an attack plays.
func update_locomotion(speed: float) -> void:
	if _in_action:
		if _ap.current_animation_position >= _action_end or not _ap.is_playing():
			_in_action = false
		else:
			return
	if speed > idle_threshold:
		_play_if_new("hulk/walk", locomotion_blend)
		_ap.speed_scale = clampf(speed / walk_natural_speed, 0.6, max_walk_playback)
	else:
		_play_if_new("hulk/idle", locomotion_blend)
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
func _prepare(source: Animation, loop: bool) -> Animation:
	var anim: Animation = source.duplicate(true)
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var track := anim.find_track(HIPS_TRACK, Animation.TYPE_POSITION_3D)
	if track >= 0 and anim.track_get_key_count(track) > 0:
		var anchor: Vector3 = anim.track_get_key_value(track, 0)
		for k in anim.track_get_key_count(track):
			var p: Vector3 = anim.track_get_key_value(track, k)
			anim.track_set_key_value(track, k, Vector3(anchor.x, p.y, anchor.z))
	return anim


static func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found:
			return found
	return null
