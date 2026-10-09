extends Node3D
## Level root. Owns the wiring between systems so they don't need to know about each other:
## Hulk <-> Camera, Hulk.Health -> HUD, Spawner -> HUD, hit feel (shake + hit stop).

@export_group("Rockets")
@export var rocket_launch_shake: float = 0.08
@export var rocket_boom_shake: float = 0.45
## Extra shake and a hit stop when the blast catches the Hulk.
@export var rocket_hit_shake: float = 0.35
@export var rocket_hit_stop: float = 0.06

@export_group("Ninja")
@export var ninja_hit_shake: float = 0.18
## The flip kick lands harder than a single cut: a touch more shake and a short hit stop.
@export var ninja_flip_shake: float = 0.35
@export var ninja_flip_hit_stop: float = 0.05

@export_group("Audio")
## Music volume (dB, on top of the Music bus) after the Hulk dies.
@export var music_death_duck_db: float = -14.0

@export_group("Hit feel")
## Real-time seconds the game freezes when a punch connects. The "crunch" of a hit.
@export var hit_stop_duration: float = 0.05
## Game speed during hit stop (0.05 = nearly frozen).
@export var hit_stop_time_scale: float = 0.05
## Screen shake for a punch that connects, plus a bit more per extra victim.
@export var punch_shake: float = 0.3
@export var punch_shake_per_hit: float = 0.08
## Ground pound always shakes (even on a miss: the Hulk just hit the ground hard).
@export var pound_shake: float = 0.55
@export var pound_hit_stop: float = 0.08
## Small kick for every explosion (stacks when several pop at once).
@export var explosion_shake: float = 0.15
## Smashing a pillar: a heavy shake and a hit stop, even if no soldier was near it.
@export var smash_shake: float = 0.6
@export var smash_hit_stop: float = 0.07
## Thrown car slams into a wall: base shake, plus more per soldier crushed against it.
@export var car_crush_shake: float = 0.5
@export var car_crush_shake_per_kill: float = 0.08
@export var car_crush_hit_stop: float = 0.09

@onready var hulk: Hulk = $Hulk
@onready var camera_rig: CameraRig = $CameraRig
@onready var hud: HUD = $HUD
@onready var enemies: Node3D = $Enemies
@onready var deaths: DeathDirector = $Deaths
@onready var spawner: WaveSpawner = $Spawner
@onready var music: AudioStreamPlayer = $Music
@onready var sfx: Sfx = $Sfx
@onready var run: Run = $Run

var _hit_stop_token: int = 0


func _ready() -> void:
	hulk.camera = camera_rig.camera
	hud.bind(hulk.health)
	hulk.punch.punched.connect(_on_punched)
	hulk.pound.pounded.connect(_on_pounded)
	hud.bind_pound(hulk.pound)
	hud.bind_eat(hulk.eat)
	deaths.exploded.connect(func(_pos: Vector3) -> void: camera_rig.add_shake(explosion_shake))
	hud.bind_spawner(spawner)
	# The Hulk goes down: the music sinks with him.
	hulk.health.died.connect(func() -> void:
		create_tween().tween_property(music, "volume_db", music_death_duck_db, 1.5))
	for pillar in get_tree().get_nodes_in_group("breakables"):
		pillar.smashed.connect(_on_smashed)
	for car in get_tree().get_nodes_in_group("throwables"):
		car.thrown.connect(func() -> void: camera_rig.add_shake(0.2))
		car.crushed.connect(_on_car_crushed)
		# Clang scales with speed: a 22 m/s slam is ~2 dB louder than a 14 m/s hit, a slow bump ~6 dB quieter.
		car.impacted.connect(func(pos: Vector3, speed: float) -> void:
			sfx.play("car_impact", pos, clampf((speed - 14.0) * 0.5, -6.0, 2.0)))
	# Gore and screams.
	deaths.exploded.connect(func(pos: Vector3) -> void: sfx.play("splat", pos))
	deaths.splatted.connect(func(pos: Vector3) -> void: sfx.play("splat", pos))
	spawner.special_spawned.connect(_on_special_spawned)
	# The run record: every kill (with how it happened), style moves, waves.
	spawner.human_died.connect(run.record_kill)
	spawner.wave_started.connect(func(wave: int, _size: int) -> void: run.wave = wave)
	spawner.wave_cleared.connect(run.record_wave_cleared)
	hulk.punch.juggled.connect(run.record_juggles)
	hulk.pound.juggled.connect(run.record_juggles)
	deaths.splatted.connect(func(_pos: Vector3) -> void: run.record_splat())
	hud.bind_run(run)
	spawner.human_killed.connect(func(pos: Vector3) -> void: sfx.play("yelp", pos + Vector3.UP * 1.5))
	# Victory roar after each cleared wave; the next wave cuts it if it's still going.
	spawner.wave_cleared.connect(func(_wave: int) -> void: hulk.animator.queue_victory())
	spawner.wave_started.connect(func(_wave: int, _size: int) -> void: hulk.animator.cancel_victory())


func _exit_tree() -> void:
	# If we reload mid hit-stop, never leave the whole game stuck in slow motion.
	Engine.time_scale = 1.0


func _on_punched(hits: int) -> void:
	if hits == 0:
		return
	sfx.play("punch_hit", hulk.global_position - hulk.global_basis.z * 2.0 + Vector3.UP * 1.5)
	camera_rig.add_shake(punch_shake + punch_shake_per_hit * (hits - 1))
	hit_stop(hit_stop_duration)


func _on_smashed(at: Vector3) -> void:
	sfx.play("pillar_smash", at)
	camera_rig.add_shake(smash_shake)
	hit_stop(smash_hit_stop)


func _on_car_crushed(_position: Vector3, count: int) -> void:
	camera_rig.add_shake(car_crush_shake + car_crush_shake_per_kill * count)
	if count > 0:
		hit_stop(car_crush_hit_stop)


func _on_special_spawned(human: Human) -> void:
	var rs := human as RocketSoldier
	if rs:
		rs.fired.connect(_on_rocket_fired)
	var ninja := human as NinjaSoldier
	if ninja:
		ninja.struck.connect(_on_ninja_struck)


func _on_ninja_struck(at: Vector3, damage: int) -> void:
	sfx.play("ninja_hit", at)
	var big := damage >= 4  # The flip kick.
	camera_rig.add_shake(ninja_flip_shake if big else ninja_hit_shake)
	if big:
		hit_stop(ninja_flip_hit_stop)


func _on_rocket_fired(rocket: Rocket) -> void:
	sfx.play("rocket_launch", rocket.global_position)
	camera_rig.add_shake(rocket_launch_shake)
	rocket.flew_close.connect(func(at: Vector3) -> void: sfx.play("rocket_flyby", at))
	rocket.exploded.connect(func(at: Vector3, hulk_damage: int) -> void:
		sfx.play("rocket_boom", at)
		camera_rig.add_shake(rocket_boom_shake + (rocket_hit_shake if hulk_damage > 0 else 0.0))
		if hulk_damage > 0:
			hit_stop(rocket_hit_stop))


func _on_pounded(kills: int) -> void:
	sfx.play("pound_hit", hulk.global_position)
	camera_rig.add_shake(pound_shake if kills > 0 else pound_shake * 0.5)
	if kills > 0:
		hit_stop(pound_hit_stop)


## Freezes the game for a split second. Uses a real-time timer (ignores time_scale),
## and a token so overlapping hit stops don't cut each other short.
func hit_stop(duration: float) -> void:
	_hit_stop_token += 1
	var my_token := _hit_stop_token
	Engine.time_scale = hit_stop_time_scale
	await get_tree().create_timer(duration, true, false, true).timeout
	if my_token == _hit_stop_token:
		Engine.time_scale = 1.0


## Spawns extra humans on top of the current wave (debug / tests). They count toward the wave.
func spawn_humans(count: int) -> void:
	for i in count:
		spawner.spawn_one()


func _unhandled_input(event: InputEvent) -> void:
	# DEBUG: H = take 10 damage. Only works when run from the editor, never in an exported game.
	if OS.is_debug_build() and event.is_action_pressed("debug_damage"):
		hulk.health.take_damage(10)
	elif event.is_action_pressed("restart") and hulk.health.is_dead:
		get_tree().reload_current_scene()
