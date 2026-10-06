class_name CameraRig
extends Node3D
## High-angle follow camera. The rig (this node) slides along the floor after the Hulk;
## the Camera3D child sits up and back at a fixed angle, so the view never rotates.
## "Looking around" comes from look-ahead: the rig leans toward the mouse cursor,
## so you see more of the corridor in the direction you are aiming.

## The node to follow. Must be a Hulk (it provides aim_point).
@export var target: Hulk
## How tightly the camera tracks. Higher = stiffer. Lower = floatier, more cinematic.
@export var follow_sharpness: float = 6.0
## Fraction of the cursor distance the camera leans toward (0 = off). Keep below 1.
@export_range(0.0, 0.9) var look_ahead_factor: float = 0.3
## Hard cap on how far the camera can lean, in meters.
@export var look_ahead_max: float = 4.0

@export_group("Shake")
## How fast shake fades, in trauma per second. 1 trauma fully decays in 1/shake_decay seconds.
@export var shake_decay: float = 3.0
## Largest camera offset (meters) at full trauma.
@export var max_shake_offset: float = 0.5

@onready var camera: Camera3D = $Camera3D

var _trauma: float = 0.0


func _ready() -> void:
	if target:
		global_position = target.global_position
		# Physics interpolation is on, so tell it this jump is a teleport, not motion.
		reset_physics_interpolation()


# Runs in the physics step so it moves in lockstep with the Hulk.
# Project Settings > Physics > Common > Physics Interpolation smooths it for high-refresh monitors.
func _physics_process(delta: float) -> void:
	if target == null:
		return
	var lean := target.aim_point - target.global_position
	lean.y = 0.0
	lean = (lean * look_ahead_factor).limit_length(look_ahead_max)
	var desired := target.global_position + lean
	desired.y = target.global_position.y
	var weight := 1.0 - exp(-follow_sharpness * delta)
	global_position = global_position.lerp(desired, weight)


## Adds screen shake. amount 0..1, stacks up to 1. Shake strength is trauma squared,
## so small hits barely nudge the camera while big ones really rattle it.
func add_shake(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)


# Shake uses the camera's h_offset/v_offset instead of moving its transform.
# WHY: those offsets are applied at render time and don't fight physics interpolation.
func _process(delta: float) -> void:
	if _trauma <= 0.0:
		return
	_trauma = maxf(_trauma - shake_decay * delta, 0.0)
	var strength := _trauma * _trauma * max_shake_offset
	camera.h_offset = randf_range(-1.0, 1.0) * strength
	camera.v_offset = randf_range(-1.0, 1.0) * strength
