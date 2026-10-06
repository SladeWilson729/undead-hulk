class_name HUD
extends CanvasLayer
## On-screen health, pound cooldown, wave + kill counters, wave banners, and game-over screen.
## The HUD never finds the player on its own; Main calls bind() and hands it the Health node.
## WHY: keeps the HUD reusable and avoids hard-coded node paths into the level.

@onready var hp_label: Label = %HPLabel
@onready var hp_bar: ProgressBar = %HPBar
@onready var game_over: Label = %GameOverLabel
@onready var pound_label: Label = %PoundLabel
@onready var wave_label: Label = %WaveLabel
@onready var kill_label: Label = %KillLabel
@onready var banner: Label = %Banner

var _pound: GroundPound
var _spawner: WaveSpawner
var _banner_tween: Tween


func bind(health: Health) -> void:
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	_on_health_changed(health.current, health.max_health)
	game_over.visible = false


func bind_pound(pound: GroundPound) -> void:
	_pound = pound


func bind_spawner(spawner: WaveSpawner) -> void:
	_spawner = spawner
	spawner.wave_started.connect(_on_wave_started)
	spawner.kills_changed.connect(func(total: int) -> void: kill_label.text = "KILLS  %d" % total)
	wave_label.text = "GET READY"
	kill_label.text = "KILLS  0"
	banner.visible = false


func _process(_delta: float) -> void:
	_update_break_banner()
	if _pound == null:
		return
	if _pound.phase == GroundPound.Phase.COOLDOWN:
		pound_label.text = "POUND  %.1f" % _pound.cooldown_remaining
		pound_label.modulate = Color(0.6, 0.6, 0.6)
	else:
		pound_label.text = "POUND  READY"
		pound_label.modulate = Color(1.0, 0.85, 0.3)


func _on_health_changed(current: int, maximum: int) -> void:
	hp_label.text = "HP  %d / %d" % [current, maximum]
	hp_bar.max_value = maximum
	hp_bar.value = current


## Between waves, the banner counts down to the next one.
func _update_break_banner() -> void:
	if _spawner == null or _spawner.state != WaveSpawner.State.BREAK or _spawner.wave == 0:
		return
	if _banner_tween and _banner_tween.is_running():
		return
	banner.visible = true
	banner.modulate.a = 1.0
	banner.text = "WAVE %d CLEARED\nnext wave in %d" % [_spawner.wave, ceili(_spawner.break_remaining)]


func _on_wave_started(wave: int, _size: int) -> void:
	wave_label.text = "WAVE  %d" % wave
	# Big "WAVE N" slam-in, hold, fade.
	if _banner_tween:
		_banner_tween.kill()
	banner.visible = true
	banner.text = "WAVE %d" % wave
	banner.modulate.a = 1.0
	banner.pivot_offset = banner.size * 0.5  # Scale from the center, at any window size.
	banner.scale = Vector2(1.6, 1.6)
	_banner_tween = create_tween()
	_banner_tween.tween_property(banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(0.9)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.4)
	_banner_tween.tween_callback(func() -> void: banner.visible = false)


func _on_died() -> void:
	if _spawner:
		game_over.text = "THE HULK IS DOWN\nReached wave %d  ·  %d kills\nPress R to rise again" % [_spawner.wave, _spawner.kills]
	banner.visible = false
	game_over.visible = true
