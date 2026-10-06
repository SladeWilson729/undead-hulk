class_name Hulk
extends CharacterBody3D
## The player. Heavy, slightly slow to get moving, always faces the mouse cursor.
## Movement is WASD relative to the camera; facing is independent of movement,
## so you can back away from the swarm while still facing it (twin-stick style).

@export_group("Movement")
## Top ground speed in meters/second. Humans will run around 5.5, so the Hulk can't simply outrun them.
@export var move_speed: float = 7.0
## How fast we reach top speed (m/s per second). Lower = heavier, more sluggish feel.
@export var acceleration: float = 35.0
## How fast we stop when keys are released. Higher than acceleration so it never feels slippery.
@export var deceleration: float = 50.0
## How quickly the body turns toward the cursor. Higher = snappier aim.
@export var turn_sharpness: float = 14.0

@export_group("Body")
## Collision radius in meters. Humans read this to know when they are close enough to hit.
@export var body_radius: float = 0.9
## How hard walking into humans shoves them aside (multiplier on our current speed).
@export var shove_strength: float = 1.3

@onready var health: Health = $Health
@onready var body_mesh: MeshInstance3D = $Visual/Body
@onready var punch: PunchAttack = $PunchAttack
@onready var pound: GroundPound = $GroundPound

## Set by Main. The Hulk needs the camera to project the mouse onto the floor.
var camera: Camera3D
## Where the mouse is pointing on the floor plane, in world space. The camera rig reads this for look-ahead.
var aim_point: Vector3
## Attacks set this below 1.0 to slow the Hulk while swinging. 1.0 = full speed.
var move_speed_multiplier: float = 1.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _hurt_overlay: StandardMaterial3D
var _hurt_tween: Tween
var _last_hp: int


func _ready() -> void:
	add_to_group("player")
	aim_point = global_position + Vector3.FORWARD
	health.died.connect(_on_died)
	health.health_changed.connect(_on_health_changed)
	_setup_hurt_flash()
	_last_hp = health.max_health


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta

	# Dead hulks skid to a stop and stop reading input.
	var input := Vector2.ZERO
	if not health.is_dead:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var move_dir := _camera_relative(input)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := acceleration if move_dir != Vector3.ZERO else deceleration
	horizontal = horizontal.move_toward(move_dir * move_speed * move_speed_multiplier, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	move_and_slide()
	_shove_humans()

	if not health.is_dead:
		_update_aim(delta)


## Converts WASD into a world direction based on where the camera is looking,
## so "W" always means "up the screen" even if we rotate the camera later.
func _camera_relative(input: Vector2) -> Vector3:
	if input == Vector2.ZERO:
		return Vector3.ZERO
	if camera == null:
		return Vector3(input.x, 0.0, input.y).normalized()
	var forward := -camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right := camera.global_basis.x
	right.y = 0.0
	right = right.normalized()
	# input.y is negative when pressing W (Godot's get_vector convention), hence the minus.
	return (right * input.x - forward * input.y).normalized()


## Casts a ray from the camera through the mouse and finds where it hits
## a flat plane at the Hulk's feet. No physics raycast needed, so it is cheap
## and it never "snags" on enemies standing under the cursor.
func _update_aim(delta: float) -> void:
	if camera == null:
		return
	var mouse := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse)
	var ray_dir := camera.project_ray_normal(mouse)
	var floor_plane := Plane(Vector3.UP, global_position.y)
	var hit: Variant = floor_plane.intersects_ray(ray_origin, ray_dir)
	if hit != null:
		aim_point = hit
	face_point(aim_point, delta)


## Smoothly rotates the body so its forward (-Z) points at a world position.
## Public so attacks and tests can reuse it.
func face_point(point: Vector3, delta: float) -> void:
	var to_target := point - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.04:
		return  # Cursor is on top of us; don't spin wildly.
	var target_yaw := atan2(-to_target.x, -to_target.z)
	# Frame-rate independent smoothing: same feel at 60 or 240 fps.
	var weight := 1.0 - exp(-turn_sharpness * delta)
	rotation.y = lerp_angle(rotation.y, target_yaw, weight)


## True when no attack is in progress and we're alive. Attacks check this before starting,
## so a punch can't fire mid-pound and vice versa.
func can_attack() -> bool:
	return not health.is_dead and punch.phase == PunchAttack.Phase.READY and not pound.is_busy()


## The Hulk does NOT collide with humans (collision mask = world only), so the swarm can never
## pin him in place. Instead he bulldozes: any human he walks into gets pushed out of the way.
## Humans DO collide with the Hulk, so they still pile up around him instead of overlapping him.
func _shove_humans() -> void:
	var my_speed := Vector2(velocity.x, velocity.z).length()
	if my_speed < 0.5:
		return
	var reach := body_radius + Human.BODY_RADIUS + 0.1
	for node in get_tree().get_nodes_in_group("enemies"):
		var human := node as Human
		var offset := human.global_position - global_position
		offset.y = 0.0
		var dist := offset.length()
		if dist > reach or dist < 0.001:
			continue
		var away := offset / dist
		# Only shove people we are actually walking INTO, not ones behind us.
		if away.dot(Vector3(velocity.x, 0.0, velocity.z)) <= 0.0:
			continue
		human.shove(away * my_speed * shove_strength)


## Brief red flash on the body whenever we lose HP, so you feel every slap.
func _setup_hurt_flash() -> void:
	_hurt_overlay = StandardMaterial3D.new()
	_hurt_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hurt_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hurt_overlay.albedo_color = Color(1.0, 0.1, 0.1, 0.0)
	body_mesh.material_overlay = _hurt_overlay


func _on_health_changed(current: int, _maximum: int) -> void:
	var was_damage := current < _last_hp
	_last_hp = current
	if not was_damage:
		return  # Healing shouldn't flash red.
	if _hurt_tween:
		_hurt_tween.kill()
	_hurt_overlay.albedo_color.a = 0.55
	_hurt_tween = create_tween()
	_hurt_tween.tween_property(_hurt_overlay, "albedo_color:a", 0.0, 0.18)


func _on_died() -> void:
	# Placeholder death: tip over. Step 6 replaces this with a proper ragdoll collapse.
	var tween := create_tween()
	tween.tween_property($Visual, "rotation:x", deg_to_rad(-80.0), 0.6) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
