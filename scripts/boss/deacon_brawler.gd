class_name DeaconBrawler
extends Human
## Boss phase 2, STAND-IN: Deacon Mayhem on foot. Will's Deacon model with the soldiers'
## run and punch clips retargeted onto him, and Sunday Service (the bell) in his right hand.
## Swap in his own Mixamo animations (walk, combo, slam, hit, taunt, death) when they exist.
##
## A Human with a health pool instead of hits:
##   - every source does boss damage (BOSS_DAMAGE) instead of killing outright; nothing grabs
##     him (no eating, no car pin)
##   - a flinch only on big hits (charge, car, barrel, pound), so punches don't stun-lock him
##   - BELL SLAM every few seconds: a wind-up, then a ground slam around him that hurts and
##     throws the Hulk. Get out of the ring.

signal health_changed(fraction: float)
signal slam_started
signal slammed(at: Vector3, hit_hulk: bool)
signal landed_punch

const MODEL := preload("res://assets/base_models/tattooed+fighter+3d+model.fbx")
const BELL := preload("res://assets/props/medieval+bell+3d+model.glb")
const RUN_SOURCE := preload("res://assets/humans/soldier_b_run.fbx")
const PUNCH_SOURCE := preload("res://assets/humans/soldier_b_punch.fbx")
## Damage per hit by cause (KillCause -> health points).
const BOSS_DAMAGE := {
	KillCause.SMASHED: 6.0, KillCause.STOMPED: 14.0, KillCause.TACKLED: 22.0, KillCause.CRUSHED: 30.0,
	KillCause.BLOWN_UP: 25.0, KillCause.YEETED: 10.0, KillCause.GLITTER_BOMBED: 10.0, KillCause.BURIED: 8.0,
	KillCause.FRIENDLY_FIRE: 12.0,
}
const BIG_HITS := [KillCause.STOMPED, KillCause.TACKLED, KillCause.CRUSHED, KillCause.BLOWN_UP]

@export_group("Deacon")
@export var max_health: float = 240.0
## Height in meters: between a soldier (1.8) and the Hulk (3.6).
@export var height: float = 2.7
@export var slam_every: float = 7.0
@export var slam_wind_up: float = 0.9
@export var slam_radius: float = 4.5
@export var slam_damage: int = 14
@export var slam_knock: float = 15.0
## Bell + chain length (m) hanging from his fist.
@export var bell_length: float = 1.1

var health_left: float
var _slam_timer: float = 4.0
var _winding: float = -1.0
var _bell: Node3D
var _bell_mount: Node3D
## Unit direction from his fist to the bell. Swings like a pendulum: drags behind him when he
## runs, goes up over his head on the slam wind-up, and comes down hard on the slam.
var _bell_dir: Vector3 = Vector3.DOWN
var _run_anim: Animation
var _punch_anim: Animation


@export var punch_damage: int = 6
@export var deacon_speed: float = 6.0


func _ready() -> void:
	health_left = max_health
	hits_to_kill = 1000  # The pool decides, not hit counting.
	damage = punch_damage
	attack_cooldown = 1.1
	attack_reach = 0.9
	move_speed = deacon_speed
	speed_variance = 0.0
	super._ready()
	add_to_group("boss_targets")
	add_to_group("boss")  # Stays after death (boss_targets doesn't). Checked by group, not class, elsewhere.


func _build_model() -> void:
	model = MODEL.instantiate()
	model.scale = Vector3.ONE * height
	visual.add_child(model)
	model.rotation.y = PI
	if painterly_enabled:
		preload("res://scripts/vfx/character_paint.gd").apply_to(model, paint_style)
	gib_material = StandardMaterial3D.new()
	(gib_material as StandardMaterial3D).albedo_color = Color(0.7, 0.15, 0.12)
	var src: Node3D = RUN_SOURCE.instantiate()
	var run_player := SoldierVariants.find_player(src)
	_run_anim = AnimRetarget.retarget(run_player.get_animation(run_player.get_animation_list()[0]), src, model)
	_run_anim.loop_mode = Animation.LOOP_LINEAR
	var lib: AnimationLibrary = PUNCH_SOURCE
	_punch_anim = AnimRetarget.retarget(lib.get_animation(lib.get_animation_list()[0]), src, model)
	src.free()
	_ap = AnimationPlayer.new()
	model.add_child(_ap)
	var l := AnimationLibrary.new()
	l.add_animation("run", _run_anim)
	l.add_animation("punch", _punch_anim)
	_ap.add_animation_library("soldier", l)
	_ap.play("soldier/run")
	_run_speed = 3.4 * height / 1.8
	# Sunday Service, swinging from his right fist.
	var sk := SoldierVariants.find_skeleton(model)
	if sk and sk.find_bone("mixamorig_RightHand") >= 0:
		var mount := BoneAttachment3D.new()
		mount.bone_name = "mixamorig_RightHand"
		sk.add_child(mount)
		_bell_mount = mount
		# The bell isn't parented to the hand: the hand bone spins with every swing, and a bell
		# glued to it pointed its chain sideways. It hangs from the fist instead (_process).
		_bell = BELL.instantiate()
		_bell.top_level = true
		mount.add_child(_bell)


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if target and not target.health.is_dead:
		if _winding >= 0.0:
			velocity = velocity.move_toward(Vector3.ZERO, 30.0 * delta)
			move_and_slide()
			_winding -= delta
			if _winding < 0.0:
				_slam()
			return
		_slam_timer -= delta
		if _slam_timer <= 0.0 and global_position.distance_to(target.global_position) < slam_radius + 3.0:
			_start_slam()
			return
	super._physics_process(delta)


func _process(delta: float) -> void:
	if _bell == null or _bell_mount == null:
		return
	var want := Vector3.DOWN
	var fwd := Vector3.ZERO
	if target:
		fwd = target.global_position - global_position
		fwd.y = 0.0
		fwd = fwd.normalized()
	if _winding >= 0.0 and not _dead:
		want = (Vector3.UP - fwd * 0.6).normalized()  # Hauled up over his head, behind him.
	else:
		var drag := Vector3(-velocity.x, 0.0, -velocity.z) * 0.08  # Trails him when he runs.
		want = (Vector3.DOWN + drag).normalized()
	var rate := 14.0 if _winding >= 0.0 else 6.0
	_bell_dir = _bell_dir.slerp(want, 1.0 - exp(-rate * delta)).normalized()
	# Model space: bell mouth at y 0, chain top at y 1. Chain top goes in the fist.
	var up := -_bell_dir
	var b := Basis(Quaternion(Vector3.UP, up)) if up.dot(Vector3.UP) > -0.999 else Basis(Vector3.RIGHT, PI)
	var fist := _bell_mount.global_position
	_bell.global_transform = Transform3D(b.scaled(Vector3.ONE * bell_length), fist - up * bell_length)


func _start_slam() -> void:
	_winding = slam_wind_up
	_slam_timer = slam_every
	slam_started.emit()
	# Rears back: lifts and leans.
	var t := create_tween()
	t.tween_property(visual, "position:y", 0.5, slam_wind_up * 0.8).set_trans(Tween.TRANS_SINE)
	t.tween_property(visual, "position:y", 0.0, slam_wind_up * 0.2)


func _slam() -> void:
	var at := global_position
	var hit := false
	if target:
		var fwd := target.global_position - global_position
		fwd.y = 0.0
		_bell_dir = (fwd.normalized() * 1.2 + Vector3.DOWN).normalized()  # Comes down in front of him.
	else:
		_bell_dir = Vector3.DOWN
	if target and not target.health.is_dead:
		var off := target.global_position - at
		off.y = 0.0
		if off.length() <= slam_radius + target.body_radius:
			hit = true
			target.health.take_damage(slam_damage)
			var away := off.normalized() if off.length() > 0.1 else -target.global_basis.z
			target.boss_knock(away * slam_knock + Vector3.UP * 7.0)
	# His own men too.
	for node in get_tree().get_nodes_in_group("enemies").duplicate():
		var h := node as Human
		if h == null or h == self:
			continue
		var off := h.global_position - at
		off.y = 0.0
		if off.length() <= slam_radius:
			h.kill(off.normalized() * 9.0 + Vector3.UP * 10.0, KillCause.FRIENDLY_FIRE)
	slammed.emit(at, hit)


func _try_attack() -> void:
	if _cooldown <= 0.0 and target and not target.health.is_dead:
		landed_punch.emit()
	super._try_attack()


## A boss: nothing kills him outright, every hit comes off his pool.
func absorb_hit(launch_velocity: Vector3, cause: int) -> bool:
	if _dead:
		return false
	var dmg: float = BOSS_DAMAGE.get(cause, 6.0)
	health_left = maxf(health_left - dmg, 0.0)
	health_changed.emit(health_left / max_health)
	if health_left <= 0.0:
		return false  # This one kills him.
	if cause in BIG_HITS:
		velocity = Vector3(launch_velocity.x, 0.0, launch_velocity.z) * 0.25
		stagger_left = 0.6
		_winding = -1.0
		visual.position.y = 0.0
	_flash_hit()
	hurt.emit(self, ceili(health_left))
	return true


## Boss damage from something that isn't a soldier-style kill (the truck exploding nearby, etc.).
func take_boss_hit(amount: float, _source: String = "") -> float:
	if _dead:
		return 0.0
	health_left = maxf(health_left - amount, 0.0)
	health_changed.emit(health_left / max_health)
	_flash_hit()
	if health_left <= 0.0:
		kill(Vector3(0, 6, 0), KillCause.SMASHED)
	return amount


func is_alive() -> bool:
	return not _dead


## He can't be pinned to a car (EatSoldier won't grab him either); a car still hurts.
func pin_to(_carrier: Node3D, cause: int = KillCause.UNKNOWN) -> Node3D:
	if not _dead:
		kill(Vector3(0, 4, 0), cause)
	return null


## His death is his own: no ragdoll (the rig is scaled up, ragdoll bodies can't be), he
## topples where he stands and stays down. Still counts as a kill (bounty, run record).
func kill(launch_velocity: Vector3 = Vector3.ZERO, cause: int = KillCause.UNKNOWN) -> void:
	if _dead or absorb_hit(launch_velocity, cause):
		return
	_dead = true
	death_cause = cause
	remove_from_group("enemies")
	remove_from_group("boss_targets")
	collision_layer = 0
	velocity = Vector3.ZERO
	if _ap:
		_ap.speed_scale = 0.0
	var t := create_tween()
	t.tween_property(visual, "rotation:x", -PI * 0.5, 0.7).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	died.emit(self)
