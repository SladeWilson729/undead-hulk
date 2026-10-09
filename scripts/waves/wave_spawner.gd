class_name WaveSpawner
extends Node
## Clear-to-advance waves. Each wave pours in from the level's spawn points; once every
## human in it is dead, there's a short break, then the next (bigger, faster) wave starts.
##
##   BREAK -> SPAWNING (trickles humans in) -> FIGHTING (all spawned, waiting for the last kill) -> BREAK ...
##
## The spawner only spawns and counts. It doesn't know about the HUD or the Hulk's attacks;
## the HUD listens to its signals.

signal wave_started(wave: int, size: int)
signal wave_cleared(wave: int)
signal kills_changed(total: int)
## One soldier died, and where. For effects that care about position (death yelps).
signal human_killed(position: Vector3)
## Same moment, with the soldier himself (for the Run record: cause, bounty).
signal human_died(human: Human)
## A soldier just entered the field (any kind). Augments dress him (Bobbleheads).
signal human_spawned(human: Human)
## A special enemy (rocket soldier, ninja) entered the field. Main hooks up its sounds and shake.
signal special_spawned(human: Human)

enum State { IDLE, BREAK, SPAWNING, FIGHTING }

@export var human_scene: PackedScene
## Where spawned humans are parented.
@export var container: Node3D
## Who the humans chase.
@export var target: Hulk
## Off for tests that want to place humans by hand.
@export var auto_start: bool = true

@export_group("Wave size")
@export var first_wave_size: int = 12
## Extra humans added each wave. Wave n = first_wave_size + size_growth * (n - 1).
@export var size_growth: int = 8

@export_group("Pacing")
## Seconds before wave 1.
@export var first_break: float = 2.0
## Breather between waves.
@export var break_time: float = 5.0
## Seconds between spawns on wave 1 (sides alternate, so each end gets one every 2x this).
@export var spawn_interval: float = 0.3
## Each wave spawns a bit faster, down to this floor.
@export var min_spawn_interval: float = 0.1
@export var interval_shrink_per_wave: float = 0.02
## Performance ceiling: never more than this many living humans at once.
## A big wave just keeps queuing until the Hulk thins the crowd.
@export var max_alive: int = 60

@export_group("Rocket soldiers")
@export var rocket_soldier_scene: PackedScene = preload("res://scenes/enemies/rocket_soldier.tscn")
@export var rocket_soldiers_per_wave: int = 1
## He walks on once this fraction of the wave's regular soldiers has spawned, so he arrives
## behind a screen of runners instead of alone.
@export_range(0.0, 1.0) var rocket_spawn_at: float = 0.25

@export_group("Ninjas")
@export var ninja_scene: PackedScene = preload("res://scenes/enemies/ninja_soldier.tscn")
@export var ninjas_per_wave: int = 1
## She drops in once this fraction of the wave has spawned: after the rocket soldier, while
## the Hulk is busy with the crowd.
@export_range(0.0, 1.0) var ninja_spawn_at: float = 0.5

@export_group("Difficulty")
## Run speed bonus per wave (0.04 = +4% per wave).
@export var speed_growth: float = 0.04
## Cap on that bonus. 1.3 x 5.5 = 7.15 m/s, just above the Hulk's 7.0: late waves can catch you.
@export var max_speed_multiplier: float = 1.3

@export_group("Spawn points")
## Soldiers come in at Marker3D nodes in the "spawn_points" group (the level scene owns them,
## e.g. Level/SpawnPoints/West and East), taking turns in scene order. Each one lands at a
## random spot within this spread (meters, x and z) around its marker.
@export var spawn_spread: Vector2 = Vector2(2.0, 3.0)

## Used only when the level has no spawn markers (e.g. a bare test scene): just inside the
## old corridor's end caps.
const FALLBACK_SPAWNS: Array[Vector3] = [Vector3(-37.0, 0.0, 0.0), Vector3(37.0, 0.0, 0.0)]

var state: State = State.IDLE
var wave: int = 0
var kills: int = 0
## Seconds left in the current break (the HUD shows this).
var break_remaining: float = 0.0
var alive: int = 0
var _to_spawn: int = 0
var _timer: float = 0.0
var _next_spawn: int = 0
var _rockets_left: int = 0
var _ninjas_left: int = 0
var _spawned_this_wave: int = 0


func _ready() -> void:
	if auto_start:
		_begin_break(first_break)


func _physics_process(delta: float) -> void:
	if target and target.health.is_dead:
		state = State.IDLE
		return
	match state:
		State.BREAK:
			break_remaining = maxf(break_remaining - delta, 0.0)
			if break_remaining <= 0.0:
				_start_wave()
		State.SPAWNING:
			_timer -= delta
			while _timer <= 0.0 and _to_spawn > 0:
				if alive >= max_alive:
					_timer = 0.1  # Crowd is maxed out. Check again shortly.
					break
				spawn_one()
				_to_spawn -= 1
				_spawned_this_wave += 1
				_timer += current_interval()
				if _rockets_left > 0 and _spawned_this_wave >= ceili(wave_size(wave) * rocket_spawn_at):
					spawn_rocket_soldier()
				if _ninjas_left > 0 and _spawned_this_wave >= ceili(wave_size(wave) * ninja_spawn_at):
					spawn_ninja()
			if _to_spawn == 0:
				while _rockets_left > 0:
					spawn_rocket_soldier()
				while _ninjas_left > 0:
					spawn_ninja()
				state = State.FIGHTING
				_check_cleared()


func wave_size(n: int) -> int:
	return first_wave_size + size_growth * (n - 1)


func current_interval() -> float:
	return maxf(spawn_interval - interval_shrink_per_wave * (wave - 1), min_spawn_interval)


func speed_multiplier(n: int) -> float:
	return minf(1.0 + speed_growth * (n - 1), max_speed_multiplier)


## Spawns one human at the next spawn point. Public for tests and debug tools.
func spawn_one(scene: PackedScene = null) -> Human:
	var human: Human = (scene if scene else human_scene).instantiate()
	human.position = next_spawn_position()
	human.target = target
	# Set before add_child: Human._ready() rolls its personal speed from move_speed.
	human.move_speed *= speed_multiplier(maxi(wave, 1))
	container.add_child(human)
	human.reset_physics_interpolation()
	human.died.connect(_on_human_died)
	alive += 1
	human_spawned.emit(human)
	return human


## Where the next soldier comes in: the next spawn marker in turn, plus a random spread.
func next_spawn_position() -> Vector3:
	var points := spawn_points()
	var base: Vector3 = points[_next_spawn % points.size()]
	_next_spawn += 1
	return base + Vector3(randf_range(-spawn_spread.x, spawn_spread.x), 0.0, randf_range(-spawn_spread.y, spawn_spread.y))


## World positions of the level's spawn markers, in scene order (fallback if it has none).
func spawn_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for node in get_tree().get_nodes_in_group("spawn_points"):
		if node is Node3D:
			points.append((node as Node3D).global_position)
	return points if not points.is_empty() else FALLBACK_SPAWNS


## One rocket soldier, at the next spawn point. Counts toward the wave like anyone.
func spawn_rocket_soldier() -> Human:
	_rockets_left = maxi(_rockets_left - 1, 0)
	var soldier := spawn_one(rocket_soldier_scene)
	special_spawned.emit(soldier)
	return soldier


## One ninja, at the next spawn point. Counts toward the wave like anyone.
func spawn_ninja() -> Human:
	_ninjas_left = maxi(_ninjas_left - 1, 0)
	var ninja := spawn_one(ninja_scene)
	special_spawned.emit(ninja)
	return ninja


func _start_wave() -> void:
	wave += 1
	_rockets_left = rocket_soldiers_per_wave
	_ninjas_left = ninjas_per_wave
	_spawned_this_wave = 0
	_to_spawn = wave_size(wave)
	_timer = 0.0
	state = State.SPAWNING
	wave_started.emit(wave, _to_spawn)


func _begin_break(seconds: float) -> void:
	state = State.BREAK
	break_remaining = seconds


func _on_human_died(human: Human) -> void:
	alive -= 1
	kills += 1
	kills_changed.emit(kills)
	human_died.emit(human)
	human_killed.emit(human.global_position)
	_check_cleared()


func _check_cleared() -> void:
	if state == State.FIGHTING and alive <= 0 and _to_spawn == 0:
		wave_cleared.emit(wave)
		_begin_break(break_time)
