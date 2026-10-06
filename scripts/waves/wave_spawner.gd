class_name WaveSpawner
extends Node
## Clear-to-advance waves. Each wave pours in from both ends of the corridor; once every
## human in it is dead, there's a short break, then the next (bigger, faster) wave starts.
##
##   BREAK -> SPAWNING (trickles humans in) -> FIGHTING (all spawned, waiting for the last kill) -> BREAK ...
##
## The spawner only spawns and counts. It doesn't know about the HUD or the Hulk's attacks;
## the HUD listens to its signals.

signal wave_started(wave: int, size: int)
signal wave_cleared(wave: int)
signal kills_changed(total: int)

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

@export_group("Difficulty")
## Run speed bonus per wave (0.04 = +4% per wave).
@export var speed_growth: float = 0.04
## Cap on that bonus. 1.3 x 5.5 = 7.15 m/s, just above the Hulk's 7.0: late waves can catch you.
@export var max_speed_multiplier: float = 1.3

## Spawn zones just inside each end cap.
const SPAWN_X := 37.0
const SPAWN_Z_HALF := 3.0

var state: State = State.IDLE
var wave: int = 0
var kills: int = 0
## Seconds left in the current break (the HUD shows this).
var break_remaining: float = 0.0
var alive: int = 0
var _to_spawn: int = 0
var _timer: float = 0.0
var _next_side: float = -1.0


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
				_timer += current_interval()
			if _to_spawn == 0:
				state = State.FIGHTING
				_check_cleared()


func wave_size(n: int) -> int:
	return first_wave_size + size_growth * (n - 1)


func current_interval() -> float:
	return maxf(spawn_interval - interval_shrink_per_wave * (wave - 1), min_spawn_interval)


func speed_multiplier(n: int) -> float:
	return minf(1.0 + speed_growth * (n - 1), max_speed_multiplier)


## Spawns one human at the next end of the corridor. Public for tests and debug tools.
func spawn_one() -> Human:
	var human: Human = human_scene.instantiate()
	human.position = Vector3(
		_next_side * SPAWN_X + randf_range(-2.0, 2.0),
		0.0,
		randf_range(-SPAWN_Z_HALF, SPAWN_Z_HALF))
	_next_side = -_next_side
	human.target = target
	# Set before add_child: Human._ready() rolls its personal speed from move_speed.
	human.move_speed *= speed_multiplier(maxi(wave, 1))
	container.add_child(human)
	human.reset_physics_interpolation()
	human.died.connect(_on_human_died)
	alive += 1
	return human


func _start_wave() -> void:
	wave += 1
	_to_spawn = wave_size(wave)
	_timer = 0.0
	state = State.SPAWNING
	wave_started.emit(wave, _to_spawn)


func _begin_break(seconds: float) -> void:
	state = State.BREAK
	break_remaining = seconds


func _on_human_died(_human: Human) -> void:
	alive -= 1
	kills += 1
	kills_changed.emit(kills)
	_check_cleared()


func _check_cleared() -> void:
	if state == State.FIGHTING and alive <= 0 and _to_spawn == 0:
		wave_cleared.emit(wave)
		_begin_break(break_time)
