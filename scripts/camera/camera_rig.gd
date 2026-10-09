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
@export var shake_decay: float = 2.4
## Largest camera offset (meters) at full trauma. The camera is ~19 m from the action, so
## anything under ~0.3 m barely reads; 1.1 makes a full-trauma hit rattle.
@export var max_shake_offset: float = 1.1
## How fast the shake wobbles (noise speed). Smooth noise instead of a new random offset every
## frame: it reads as the camera being knocked around, not as video static.
@export var shake_frequency: float = 28.0

@export_group("Impact kick")
## Big landings (ground pound, the charge hitting a wall) also jolt the camera: a quick zoom-in
## and a drop, springing back. Shake alone is all sideways jitter; the kick sells the weight.
## Degrees of FOV the camera punches in at a full kick.
@export var kick_fov: float = 5.0
## Meters the view drops at a full kick (the "thud").
@export var kick_drop: float = 0.6
## Seconds for the kick to spring back.
@export var kick_time: float = 0.3

@onready var camera: Camera3D = $Camera3D

var _trauma: float = 0.0
var _kick: float = 0.0
var _base_fov: float
var _noise := FastNoiseLite.new()
var _noise_t: float = 0.0


func _ready() -> void:
	_base_fov = camera.fov
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.seed = randi()
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


## Impact jolt for heavy landings: zoom-in plus a drop that springs back. amount 0..1.
func add_kick(amount: float) -> void:
	_kick = clampf(maxf(_kick, amount), 0.0, 1.0)


## Current shake trauma (0..1). For tests and debug.
func trauma() -> float:
	return _trauma


# Shake and kick use the camera's h_offset/v_offset and fov instead of moving its transform.
# WHY: those are applied at render time and don't fight physics interpolation.
func _process(delta: float) -> void:
	if _trauma <= 0.0 and _kick <= 0.0:
		return
	_trauma = maxf(_trauma - shake_decay * delta, 0.0)
	_kick = maxf(_kick - delta / maxf(kick_time, 0.01), 0.0)
	_noise_t += delta * shake_frequency
	var strength := _trauma * _trauma * max_shake_offset
	# Ease the kick out: snaps in at once, eases back.
	var k := _kick * _kick
	camera.h_offset = _noise.get_noise_2d(_noise_t, 0.0) * strength
	camera.v_offset = _noise.get_noise_2d(0.0, _noise_t) * strength - k * kick_drop
	camera.fov = _base_fov - k * kick_fov
