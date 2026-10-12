class_name Finale
extends Node
## The end of a run: wave 15's fake-out victory and the Deacon Mayhem boss fight.
## Lives in main.tscn as "Finale"; Main hands it the pieces it needs.
##
##   FAKEOUT  - wave 15 cleared: full heal, "YOU WIN!", the victory roar.
##   ARRIVAL  - the music dies, the bridge shakes, "...WAIT.", the Deacon's entrance speech,
##              and his war wagon roars in from the far end.
##   TRUCK    - phase 1 (WarWagon). Soldiers trickle in the whole fight.
##   DEACON   - the truck blows, the Deacon is thrown clear and comes at you on foot.
##   WON      - he drops: defeat line, "SMASHED IT!", the win summary.
## If the Hulk dies in the fight, the Deacon gets his victory line.

signal phase_changed(phase: int)

enum Phase { IDLE, FAKEOUT, ARRIVAL, TRUCK, DEACON, WON, LOST }

const DEACON_SCENE := preload("res://scenes/boss/deacon_brawler.tscn")
const TRUCK_ARRIVE := preload("res://assets/sound/sound effects/boss-battle-sounds/a_large_armored_truc_#1-1791558536941.mp3")

@export_group("Timing")
## Seconds the fake "YOU WIN!" gets before it all goes wrong.
@export var fakeout_hold: float = 3.2
## Seconds of rumble before the truck shows up.
@export var rumble_time: float = 2.0

@export_group("Fight")
## Soldiers keep coming during the boss: this many every this many seconds, up to the cap alive.
@export var trickle_every: float = 7.0
@export var trickle_size: int = 3
@export var trickle_cap: int = 14
## Bounty for wrecking the truck (flat, on top of the score).
@export var truck_bonus: int = 1500
## Truck explosion: soldiers in this radius die, the Hulk takes damage if he's this close.
@export var wreck_radius: float = 6.0
@export var wreck_damage: int = 10

var phase: Phase = Phase.IDLE
var hulk: Hulk
var hud: HUD
var spawner: WaveSpawner
var run: Run
var music: AudioStreamPlayer
var camera_rig: CameraRig
var sfx: Sfx
var truck: WarWagon
var deacon: DeaconBrawler
var voice: DeaconVoice
var _trickle_timer: float = 0.0
var _rumble_left: float = 0.0
var _sting: AudioStreamPlayer


func _ready() -> void:
	voice = DeaconVoice.new()
	voice.name = "DeaconVoice"
	add_child(voice)
	_sting = AudioStreamPlayer.new()
	_sting.bus = &"SFX"
	add_child(_sting)


## Main connects WaveSpawner.final_wave_cleared here.
func start() -> void:
	if phase != Phase.IDLE or hulk.health.is_dead:
		return
	hulk.health.died.connect(_on_hulk_died)
	_set_phase(Phase.FAKEOUT)
	hulk.health.heal(hulk.health.max_health)
	hud.flash_banner("YOU WIN!", fakeout_hold - 0.6, Color(1.0, 0.85, 0.3))
	await get_tree().create_timer(fakeout_hold, false).timeout
	if hulk.health.is_dead:
		return
	_arrive()


func _arrive() -> void:
	_set_phase(Phase.ARRIVAL)
	if music:
		var t := create_tween()
		t.tween_property(music, "pitch_scale", 0.3, 0.6)  # The record grinds to a halt.
		t.parallel().tween_property(music, "volume_db", -60.0, 0.6)
		t.tween_callback(music.stop)
	hud.flash_banner("...WAIT.", 1.4, Color(1.0, 0.45, 0.35))
	_rumble_left = rumble_time
	_sting.stream = TRUCK_ARRIVE
	_sting.play()
	voice.say("entrance")
	await get_tree().create_timer(rumble_time, false).timeout
	if hulk.health.is_dead:
		return
	_spawn_truck()


func _spawn_truck() -> void:
	truck = WarWagon.new()
	truck.name = "WarWagon"
	truck.hulk = hulk
	# From the far end, so you see it coming.
	truck.side = -1.0 if hulk.global_position.x > 0.0 else 1.0
	get_parent().add_child(truck)
	truck.global_position = Vector3(truck.side * 46.0, 0.0, 0.0)
	truck.rotation.y = atan2(truck.side, 0.0)  # Facing back down the bridge.
	truck.reset_physics_interpolation()
	truck.health_changed.connect(func(f: float) -> void:
		hud.set_boss_health(f)
		if randf() < 0.5:
			voice.say("getting_hit"))
	truck.hit_hulk.connect(func(dmg: int) -> void:
		if dmg >= 5:
			camera_rig.add_shake(0.6)
			camera_rig.add_kick(0.6)
			voice.say("hit_hulk"))
	truck.revving.connect(func(at: Vector3) -> void:
		voice.say("big_attack")
		_play("truck_rev", at))
	truck.rammed_wall.connect(func(at: Vector3) -> void:
		camera_rig.add_shake(0.5)
		_play("truck_crash", at)
		_play("car_impact", at)
		voice.say("getting_hit"))
	truck.burst_started.connect(func(at: Vector3) -> void: _play("boss_mg", at))
	truck.destroyed.connect(_on_truck_destroyed)
	camera_rig.focus = truck
	hud.edge_watch = hulk  # Boss hits can throw him over the rail: show where that happens.
	hud.show_boss_bar("THE DEACON'S WAR WAGON", 1.0)
	hud.wave_label.text = "FINAL BOSS"
	_set_phase(Phase.TRUCK)
	voice.active = true
	_trickle_timer = 3.0


func _process(delta: float) -> void:
	if _rumble_left > 0.0:
		_rumble_left -= delta
		camera_rig.add_shake(0.9 * delta * 3.0)
	if phase == Phase.TRUCK or phase == Phase.DEACON:
		_trickle_timer -= delta
		if _trickle_timer <= 0.0:
			_trickle_timer = trickle_every
			spawner.spawn_trickle(trickle_size, trickle_cap)


func _on_truck_destroyed(at: Vector3) -> void:
	run.record_boss_bonus(truck_bonus)
	camera_rig.add_shake(1.0)
	camera_rig.add_kick(1.0)
	Explosion.spawn(get_parent(), at, wreck_radius * 0.8)
	Explosion.spawn(get_parent(), at + truck.forward() * 2.5, wreck_radius * 0.6)
	for node in get_tree().get_nodes_in_group("enemies").duplicate():
		var h := node as Human
		if h == null:
			continue
		var off := h.global_position - at
		off.y = 0.0
		if off.length() <= wreck_radius:
			h.kill(off.normalized() * 12.0 + Vector3.UP * 10.0, KillCause.BLOWN_UP)
	if (hulk.global_position - at).length() <= wreck_radius:
		hulk.health.take_damage(wreck_damage)
	voice.say("phase_change")
	_spawn_deacon(truck.gunner_position())


func _spawn_deacon(from: Vector3) -> void:
	# Thrown clear of the wreck, toward the Hulk.
	var to_hulk := hulk.global_position - from
	to_hulk.y = 0.0
	var land := from + to_hulk.normalized() * minf(5.0, to_hulk.length() * 0.5)
	land.y = 0.0
	deacon = spawner.spawn_one(DEACON_SCENE, land) as DeaconBrawler
	deacon.target = hulk
	deacon.set_physics_process(false)
	deacon.global_position = from
	deacon.reset_physics_interpolation()
	var t := deacon.create_tween()
	t.tween_property(deacon, "global_position", land + Vector3.UP * 2.0, 0.35).set_ease(Tween.EASE_OUT)
	t.tween_property(deacon, "global_position", land, 0.3).set_ease(Tween.EASE_IN)
	t.tween_callback(func() -> void:
		camera_rig.add_shake(0.5)
		deacon.set_physics_process(true))
	deacon.health_changed.connect(func(f: float) -> void:
		hud.set_boss_health(f)
		if randf() < 0.35:
			voice.say("getting_hit"))
	deacon.slam_started.connect(func() -> void:
		voice.say("big_attack")
		_play("chain_whip", deacon.global_position))
	deacon.slammed.connect(func(at: Vector3, hit: bool) -> void:
		_play("bell_slam", at)
		_play("pound_hit", at)
		camera_rig.add_shake(0.7 if hit else 0.4)
		camera_rig.add_kick(0.5)
		if hit:
			voice.say("hit_hulk"))
	deacon.landed_punch.connect(func() -> void: voice.say("hit_hulk"))
	deacon.died.connect(func(_h: Human) -> void: _on_deacon_defeated())
	camera_rig.focus = deacon
	hud.show_boss_bar("DEACON MAYHEM", 1.0)
	_set_phase(Phase.DEACON)


func _on_deacon_defeated() -> void:
	_set_phase(Phase.WON)
	voice.active = false
	voice.say("defeat")
	hulk.health.invulnerable = true
	camera_rig.focus = null
	hud.edge_watch = null
	hud.show_boss_bar("")
	hud.flash_banner("SMASHED IT!", 2.0, Color(0.77, 0.94, 0.4))
	camera_rig.add_shake(0.6)
	hulk.animator.queue_victory()
	# Whoever's left standing loses the will to fight: they freeze where they are.
	for node in get_tree().get_nodes_in_group("enemies"):
		(node as Human).state = Human.State.IDLE
		(node as Node).set_physics_process(false)
	await get_tree().create_timer(maxf(voice.time_left(), 2.5) + 0.5, false).timeout
	hud.show_victory()


func _on_hulk_died() -> void:
	if phase == Phase.TRUCK or phase == Phase.DEACON or phase == Phase.ARRIVAL:
		_set_phase(Phase.LOST)
		voice.active = false
		voice.say("victory")
		camera_rig.focus = null
		hud.edge_watch = null
		hud.show_boss_bar("")


func _play(group: String, at: Vector3) -> void:
	if sfx:
		sfx.play(group, at)


func _set_phase(p: Phase) -> void:
	phase = p
	phase_changed.emit(p)
