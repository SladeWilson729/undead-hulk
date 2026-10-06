extends Node3D
## Level root. Owns the wiring between systems so they don't need to know about each other:
## Hulk <-> Camera, Hulk.Health -> HUD, Spawner -> HUD, hit feel (shake + hit stop).

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

var _hit_stop_token: int = 0


func _ready() -> void:
	hulk.camera = camera_rig.camera
	hud.bind(hulk.health)
	hulk.punch.punched.connect(_on_punched)
	hulk.pound.pounded.connect(_on_pounded)
	hud.bind_pound(hulk.pound)
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
	# Victory roar after each cleared wave; the next wave cuts it if it's still going.
	spawner.wave_cleared.connect(func(_wave: int) -> void: hulk.animator.queue_victory())
	spawner.wave_started.connect(func(_wave: int, _size: int) -> void: hulk.animator.cancel_victory())


func _exit_tree() -> void:
	# If we reload mid hit-stop, never leave the whole game stuck in slow motion.
	Engine.time_scale = 1.0


func _on_punched(hits: int) -> void:
	if hits == 0:
		return
	camera_rig.add_shake(punch_shake + punch_shake_per_hit * (hits - 1))
	hit_stop(hit_stop_duration)


func _on_smashed(_position: Vector3) -> void:
	camera_rig.add_shake(smash_shake)
	hit_stop(smash_hit_stop)


func _on_car_crushed(_position: Vector3, count: int) -> void:
	camera_rig.add_shake(car_crush_shake + car_crush_shake_per_kill * count)
	if count > 0:
		hit_stop(car_crush_hit_stop)


func _on_pounded(kills: int) -> void:
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
