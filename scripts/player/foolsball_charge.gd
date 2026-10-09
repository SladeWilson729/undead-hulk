class_name FoolsballCharge
extends Node
## Foolsball Helmet (Legendary augment): Shift lowers his head and bull-rushes toward the cursor.
## Sibling of PunchAttack / GroundPound, built the same way. Locked until the augment is picked.
##
## Timeline:  READY -> WINDUP (dig in) -> DASH (runs `distance` meters at `speed`)
##            -> RECOVER (pulls up) -> COOLDOWN -> READY
##            A wall mid-dash: -> DAZED (longer stop, stars) -> COOLDOWN
##
## During the dash every soldier in his path dies and flies off to the side (Tackled), pillars
## burst, and a parked car gets punted like a throw. He can't be hurt from windup to the end
## of the dash, same deal as the pound.

## Started digging in (windup begins).
signal charged
## Dash over. tackled = soldiers taken out, wall = ended by hitting a wall.
signal finished(tackled: int, wall: bool)
## Every soldier the instant he's hit (for sounds and shake).
signal tackled(at: Vector3)
## Ran face first into a wall.
signal bonked(at: Vector3)

enum Phase { LOCKED, READY, WINDUP, DASH, RECOVER, DAZED, COOLDOWN }

const COMIC := preload("res://scripts/vfx/comic_wall_impact.gd")

@export_group("Helmet")
## The helmet he wears once the augment is picked. Static mesh, face mask toward +Z, origin at
## its bottom center.
@export var helmet_scene: PackedScene = preload("res://assets/props/helmet/tripo_convert_7c111707-8506-4e1a-9125-0bccad88106b.fbx")
## The bone the helmet rides on. On this Tripo rig the visible head is skinned to the NECK bone
## (the Head bone has no vertices), so that's the one that carries it.
@export var helmet_bone: String = "mixamorig_Neck"
## Size relative to the helmet file. Measured fit: his head is 0.14 wide and 0.14 deep (face to
## back of skull, model units); the helmet's inside is about 0.7 x 0.73, so 0.26 leaves a little room.
@export var helmet_scale: float = 0.26
## Where the helmet's bottom center sits on the bare model, in the mesh's own rest space
## (model units: x right, y up, z toward his face). His head runs from the chin at y 0.58 to the
## crown at 0.76, back of the skull at z 0.04, face at 0.18. This puts the shell's inside back
## just behind his skull, the crown over his crown, and the face cage clear of his face.
@export var helmet_offset: Vector3 = Vector3(0.0, 0.565, 0.142)
## Tips the helmet forward (+) or back (-), degrees.
@export var helmet_tilt: float = 0.0

@export_group("Timing")
## Seconds before he can charge again, counted once he's back on his feet.
@export var cooldown: float = 6.0
## Seconds of digging in before he takes off. Short: it's a reaction move.
@export var windup_time: float = 0.22
## Seconds he's rooted after a clean charge before you can walk again.
@export var recover_time: float = 0.3
## Seconds he's stuck seeing stars after a wall.
@export var dazed_time: float = 1.1

@export_group("Dash")
## How far one charge goes (meters) and how fast (m/s). 8 m at 16 m/s = half a second.
@export var distance: float = 8.0
@export var speed: float = 16.0
## How far past his body a soldier can be and still get hit (meters).
@export var hit_reach: float = 0.5
## A collision whose normal faces back at him this squarely counts as a wall (dot, -1 = head on).
@export_range(-1.0, 0.0) var wall_dot: float = -0.55

@export_group("Launch")
## Tackled soldiers fly forward, out to the side he hit them on, and up. Sideways beats
## forward on purpose: slower than his 16 m/s, a body thrown straight ahead rides his chest.
@export var launch_forward: float = 9.0
@export var launch_side: float = 10.0
@export var launch_up: float = 7.0
## A parked car he runs into is thrown at this fraction of a normal throw.
@export var car_punt_scale: float = 1.1

var phase: Phase = Phase.LOCKED
var cooldown_remaining: float = 0.0
## Flat direction of the current charge.
var direction: Vector3 = Vector3.FORWARD
var _timer: float = 0.0
var _travelled: float = 0.0
var _count: int = 0
var _last_position: Vector3
## Pillars smashed this dash. He runs through their stumps, so they're ignored until he stops.
var _plowed: Array[PhysicsBody3D] = []
## The worn helmet (null until unlocked).
var helmet: Node3D

@onready var hulk: Hulk = get_parent()


## Foolsball Helmet picked: builds the charge clips and makes Shift live.
func unlock() -> void:
	if phase != Phase.LOCKED:
		return
	hulk.animator.prepare_charge()
	wear_helmet()
	phase = Phase.READY


## Puts the helmet on his head bone. Placed from the rest pose, so it follows the head through
## every animation (punches, the pound, the charge). Safe to call twice.
func wear_helmet() -> void:
	if helmet or helmet_scene == null:
		return
	var model: Node3D = hulk.animator.model
	var sk := SoldierVariants.find_skeleton(model)
	var skin: Skin = hulk.body_mesh.skin if hulk.body_mesh else null
	if sk == null or skin == null or sk.find_bone(helmet_bone) < 0:
		return
	var bind := -1
	for j in skin.get_bind_count():
		if skin.get_bind_name(j) == helmet_bone:
			bind = j
	if bind < 0:
		return
	var mount := BoneAttachment3D.new()
	mount.name = "HelmetMount"
	mount.bone_name = helmet_bone
	sk.add_child(mount)
	helmet = helmet_scene.instantiate()
	helmet.name = "FoolsballHelmet"
	mount.add_child(helmet)
	# Placed where it should sit on the bare mesh, then carried into the bone's space by the
	# bone's bind pose: the same math that moves the head's own vertices, so it can't drift.
	var on_mesh := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-helmet_tilt)).scaled(Vector3.ONE * helmet_scale), helmet_offset)
	helmet.transform = skin.get_bind_pose(bind) * on_mesh
	if hulk.painterly_enabled:
		preload("res://scripts/vfx/character_paint.gd").apply_to(helmet, hulk.paint_style)


func is_unlocked() -> bool:
	return phase != Phase.LOCKED


## Windup or dash: other attacks wait.
func is_busy() -> bool:
	return phase == Phase.WINDUP or phase == Phase.DASH or phase == Phase.DAZED or phase == Phase.RECOVER


## True while the charge owns his movement (Hulk reads this instead of WASD).
func is_driving() -> bool:
	return phase == Phase.DASH


func drive_velocity() -> Vector3:
	return direction * speed


func _physics_process(delta: float) -> void:
	match phase:
		Phase.READY:
			if Input.is_action_just_pressed("charge"):
				start()
		Phase.WINDUP:
			_timer -= delta
			if _timer <= 0.0:
				_begin_dash()
		Phase.DASH:
			_dash_step(delta)
		Phase.RECOVER, Phase.DAZED:
			_timer -= delta
			if _timer <= 0.0:
				hulk.move_speed_multiplier = 1.0
				phase = Phase.COOLDOWN
		Phase.COOLDOWN:
			cooldown_remaining = maxf(cooldown_remaining - delta, 0.0)
			if cooldown_remaining <= 0.0:
				phase = Phase.READY


## Starts a charge toward the cursor (his current facing). Public for tests.
func start() -> void:
	if phase != Phase.READY or not hulk.can_attack():
		return
	direction = -hulk.global_basis.z
	direction.y = 0.0
	direction = direction.normalized() if direction.length_squared() > 0.001 else Vector3.FORWARD
	phase = Phase.WINDUP
	_timer = windup_time
	_count = 0
	hulk.move_speed_multiplier = 0.0
	hulk.health.invulnerable = true
	hulk.animator.cancel_victory()
	hulk.animator.play_charge_start(windup_time)
	charged.emit()


func _begin_dash() -> void:
	phase = Phase.DASH
	_travelled = 0.0
	_last_position = hulk.global_position
	_face_direction()
	hulk.animator.play_charge_loop()


## Runs after the Hulk has moved this frame (children process after their parent).
func _dash_step(delta: float) -> void:
	_face_direction()
	var moved := hulk.global_position - _last_position
	moved.y = 0.0
	_travelled += moved.length()
	_last_position = hulk.global_position
	_hit_soldiers()
	_hit_breakables(delta)
	var wall: Variant = _wall_contact()
	if wall != null:
		_end(true, wall)
	elif _travelled >= distance:
		_end(false, null)


func _face_direction() -> void:
	hulk.rotation.y = atan2(-direction.x, -direction.z)


func _hit_soldiers() -> void:
	var reach := hulk.body_radius + Human.BODY_RADIUS + hit_reach
	var right := direction.cross(Vector3.UP)
	# Copy first: kill() takes them out of the group while we loop.
	for node in get_tree().get_nodes_in_group("enemies").duplicate():
		var human := node as Human
		if human == null:
			continue
		var offset := human.global_position - hulk.global_position
		offset.y = 0.0
		if offset.length() > reach or offset.dot(direction) < -0.3:
			continue
		var side := 1.0 if offset.dot(right) >= 0.0 else -1.0
		var launch := direction * launch_forward + right * side * launch_side * randf_range(0.8, 1.2)
		launch.y = launch_up * randf_range(0.85, 1.15)
		var at := human.global_position + Vector3.UP * 1.2
		human.kill(launch, KillCause.TACKLED)
		_count += 1
		tackled.emit(at)


## Pillars and parked cars just ahead get smashed or punted before he touches them,
## so they never stop the charge.
func _hit_breakables(delta: float) -> void:
	var ahead := hulk.body_radius + speed * delta * 2.0 + 0.3
	for node in get_tree().get_nodes_in_group("breakables"):
		var pillar := node as BreakablePillar
		if pillar == null or pillar.broken:
			continue
		var to_pillar := pillar.global_position - hulk.global_position
		to_pillar.y = 0.0
		if to_pillar.dot(direction) > 0.0 and to_pillar.length() <= ahead + pillar.footprint_radius():
			pillar.take_hit(direction, 1.5, 1.2)
			hulk.add_collision_exception_with(pillar)
			_plowed.append(pillar)
	for node in get_tree().get_nodes_in_group("throwables"):
		var car := node as ThrowableCar
		if car == null or not car.can_pick_up():
			continue
		var to_car := car.global_position - hulk.global_position
		to_car.y = 0.0
		if to_car.dot(direction) > 0.0 and to_car.length() <= ahead + 1.6:
			car.throw(direction, car_punt_scale)


## The point he hit, if he ran into a wall this frame.
func _wall_contact() -> Variant:
	for i in hulk.get_slide_collision_count():
		var c := hulk.get_slide_collision(i)
		var n := c.get_normal()
		if absf(n.y) > 0.6:
			continue  # Floor or ceiling.
		if Vector3(n.x, 0.0, n.z).normalized().dot(direction) <= wall_dot:
			return c.get_position()
	return null


func _end(wall: bool, at: Variant) -> void:
	for body in _plowed:
		if is_instance_valid(body):
			hulk.remove_collision_exception_with(body)
	_plowed.clear()
	hulk.health.invulnerable = false
	hulk.velocity.x = 0.0
	hulk.velocity.z = 0.0
	cooldown_remaining = cooldown
	if wall:
		phase = Phase.DAZED
		_timer = dazed_time
		hulk.move_speed_multiplier = 0.0
		hulk.animator.play_charge_end(true)
		_spawn_comic(at, "BONK!")
		bonked.emit(at)
	else:
		phase = Phase.RECOVER
		_timer = recover_time
		hulk.move_speed_multiplier = 0.0
		hulk.animator.play_charge_end(false)
	finished.emit(_count, wall)


func _spawn_comic(at: Vector3, word: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var layer := CanvasLayer.new()
	layer.layer = 5
	hulk.get_parent().add_child(layer)
	var comic := COMIC.new()
	comic.word = word
	comic.style = 1
	comic.anchor = at + Vector3.UP * 2.5
	layer.add_child(comic)
	get_tree().create_timer(1.2).timeout.connect(layer.queue_free)
