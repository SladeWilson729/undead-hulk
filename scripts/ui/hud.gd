class_name HUD
extends CanvasLayer
## On-screen health, pound cooldown, wave + kill counters, wave banners, and game-over screen.
## The HUD never finds the player on its own; Main calls bind() and hands it the Health node.
## WHY: keeps the HUD reusable and avoids hard-coded node paths into the level.

@onready var hp_label: Label = %HPLabel
@onready var hp_bar: ProgressBar = %HPBar
@onready var game_over: Label = %GameOverLabel
@onready var pound_label: Label = %PoundLabel
@onready var eat_label: Label = %EatLabel
@onready var wave_label: Label = %WaveLabel
@onready var kill_label: Label = %KillLabel
@onready var banner: Label = %Banner

## Seconds between the Hulk dying and the game-over text appearing, so the death fall
## (about 1.5 s to hit the ground) plays before the screen gets covered.
@export var game_over_delay: float = 1.2

var _pound: GroundPound
var _eat: EatSoldier
var _charge: FoolsballCharge
## Made on demand: only shows once Foolsball Helmet is picked.
var _charge_label: Label
var _spawner: WaveSpawner
var _run: Run
var _banner_tween: Tween
var _ended: bool = false
## The run summary once it's up (null before that).
var end_popup: RunEndPopup
## The Esc menu while it's open (null otherwise).
var pause_menu: PauseMenu
var _health: Health
## Boss fights: the Hulk whose distance to the open edge drives the red edge warning (null = off).
var edge_watch: Hulk
var _edge_glow: TextureRect
var _edge_label: Label
var _edge_t: float = 0.0


func bind(health: Health) -> void:
	_health = health
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	_on_health_changed(health.current, health.max_health)
	game_over.visible = false


func bind_pound(pound: GroundPound) -> void:
	_pound = pound


func bind_eat(eat: EatSoldier) -> void:
	_eat = eat


func bind_charge(charge: FoolsballCharge) -> void:
	_charge = charge
	# Same look as the EAT line, right under it.
	_charge_label = eat_label.duplicate() as Label
	_charge_label.name = "ChargeLabel"
	_charge_label.unique_name_in_owner = false
	_charge_label.visible = false
	eat_label.add_sibling(_charge_label)


## Score sits next to the kill count.
func bind_run(run: Run) -> void:
	_run = run
	run.score_changed.connect(func(_score: int) -> void: _update_kills())
	_update_kills()


func _update_kills() -> void:
	var k := _spawner.kills if _spawner else 0
	kill_label.text = "KILLS  %d    SCORE  %d" % [k, _run.score] if _run else "KILLS  %d" % k


func bind_spawner(spawner: WaveSpawner) -> void:
	_spawner = spawner
	spawner.wave_started.connect(_on_wave_started)
	spawner.kills_changed.connect(func(_total: int) -> void: _update_kills())
	wave_label.text = "GET READY"
	kill_label.text = "KILLS  0"
	banner.visible = false


func _process(_delta: float) -> void:
	_update_edge_warning(_delta)
	if _ended:
		return
	_update_break_banner()
	_update_eat_label()
	_update_charge_label()
	if _pound == null:
		return
	if _pound.phase == GroundPound.Phase.COOLDOWN:
		pound_label.text = "POUND  %.1f" % _pound.cooldown_remaining
		pound_label.modulate = Color(0.6, 0.6, 0.6)
	else:
		pound_label.text = "POUND  READY"
		pound_label.modulate = Color(1.0, 0.85, 0.3)


func _update_eat_label() -> void:
	if _eat == null:
		return
	if _eat.phase == EatSoldier.Phase.COOLDOWN:
		eat_label.text = "EAT  %.1f" % _eat.cooldown_remaining
		eat_label.modulate = Color(0.6, 0.6, 0.6)
	elif _eat.is_busy():
		eat_label.text = "EAT  NOM"
		eat_label.modulate = Color(0.85, 0.25, 0.2)
	else:
		eat_label.text = "EAT  READY"
		eat_label.modulate = Color(0.5, 1.0, 0.45)


func _update_charge_label() -> void:
	if _charge == null or _charge_label == null:
		return
	_charge_label.visible = _charge.is_unlocked()
	if not _charge_label.visible:
		return
	match _charge.phase:
		FoolsballCharge.Phase.READY:
			_charge_label.text = "CHARGE  READY"
			_charge_label.modulate = Color(0.45, 0.8, 1.0)
		FoolsballCharge.Phase.COOLDOWN:
			_charge_label.text = "CHARGE  %.1f" % _charge.cooldown_remaining
			_charge_label.modulate = Color(0.6, 0.6, 0.6)
		FoolsballCharge.Phase.DAZED:
			_charge_label.text = "CHARGE  BONK"
			_charge_label.modulate = Color(1.0, 0.85, 0.3)
		_:
			_charge_label.text = "CHARGE  HUT HUT!"
			_charge_label.modulate = Color(1.0, 0.55, 0.2)


func _on_health_changed(current: int, maximum: int) -> void:
	var shield := _health.shield if _health else 0
	hp_label.text = "HP  %d / %d" % [current, maximum] + ("    SHIELD  %d" % shield if shield > 0 else "")
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


## Esc / P mid-run opens the pause menu. Not over the pick screen (already paused) or the
## run summary; the menu itself handles Esc to close.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if pause_menu or end_popup or _ended or get_tree().paused:
		return
	get_viewport().set_input_as_handled()
	open_pause_menu()


func open_pause_menu() -> PauseMenu:
	if pause_menu:
		return pause_menu
	pause_menu = PauseMenu.new()
	add_child(pause_menu)
	pause_menu.closed.connect(func() -> void: pause_menu = null)
	return pause_menu


## Big centered banner (the wave banner's look) for the finale: "YOU WIN!", "...WAIT."
## hold = seconds before it fades.
func flash_banner(text: String, hold: float = 1.6, color: Color = Color(1, 1, 1)) -> void:
	if _banner_tween:
		_banner_tween.kill()
	banner.visible = true
	banner.text = text
	banner.modulate = Color(color.r, color.g, color.b, 1.0)
	banner.pivot_offset = banner.size * 0.5
	banner.scale = Vector2(1.8, 1.8)
	_banner_tween = create_tween()
	_banner_tween.tween_property(banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_interval(hold)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.4)
	_banner_tween.tween_callback(func() -> void:
		banner.visible = false
		banner.modulate = Color(1, 1, 1, 1))


## The boss health bar across the top. Made on first use; show_boss_bar("") hides it.
var _boss_box: Control
var _boss_name: Label
var _boss_bar: ProgressBar


## Red glow up from the bottom of the screen (the open rail is the screen's bottom edge) and
## "EDGE!" when a boss hit would throw him over. It fades in over the meter before the zone.
func _update_edge_warning(delta: float) -> void:
	var danger := 0.0
	if is_instance_valid(edge_watch) and not edge_watch.health.is_dead and not _ended:
		danger = edge_watch.edge_danger()
	if danger <= 0.0 and _edge_glow == null:
		return
	if _edge_glow == null:
		_edge_glow = TextureRect.new()
		var g := Gradient.new()
		g.set_color(0, Color(0.85, 0.05, 0.02, 0.0))
		g.set_color(1, Color(0.85, 0.05, 0.02, 0.75))
		var tex := GradientTexture2D.new()
		tex.gradient = g
		tex.fill_from = Vector2(0, 0)
		tex.fill_to = Vector2(0, 1)
		tex.width = 4
		tex.height = 64
		_edge_glow.texture = tex
		_edge_glow.stretch_mode = TextureRect.STRETCH_SCALE
		_edge_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_edge_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_edge_glow.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_edge_glow.offset_top = -220
		add_child(_edge_glow)
		move_child(_edge_glow, 0)  # Behind the rest of the HUD.
		_edge_label = Label.new()
		_edge_label.text = "EDGE!"
		_edge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_edge_label.add_theme_font_size_override("font_size", 44)
		_edge_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
		_edge_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_edge_label.add_theme_constant_override("outline_size", 10)
		_edge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_edge_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_edge_label.offset_left = -150
		_edge_label.offset_right = 150
		_edge_label.offset_top = -90
		_edge_label.offset_bottom = -30
		add_child(_edge_label)
	_edge_t += delta
	var pulse := 0.75 + 0.25 * sin(_edge_t * 10.0)
	_edge_glow.modulate.a = danger * pulse
	_edge_label.visible = danger >= 1.0
	_edge_label.modulate.a = pulse


func edge_warning_strength() -> float:
	return _edge_glow.modulate.a if _edge_glow else 0.0


func show_boss_bar(title: String, value: float = 1.0) -> void:
	if _boss_box == null:
		_boss_box = Control.new()
		_boss_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_boss_box.position = Vector2(-300, 70)
		_boss_box.size = Vector2(600, 64)
		_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_boss_box)
		_boss_name = Label.new()
		_boss_name.size = Vector2(600, 30)
		_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_boss_name.add_theme_font_size_override("font_size", 22)
		_boss_name.add_theme_color_override("font_outline_color", Color.BLACK)
		_boss_name.add_theme_constant_override("outline_size", 6)
		_boss_box.add_child(_boss_name)
		_boss_bar = ProgressBar.new()
		_boss_bar.position = Vector2(0, 32)
		_boss_bar.size = Vector2(600, 22)
		_boss_bar.show_percentage = false
		_boss_bar.max_value = 1.0
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0.1, 0.1, 0.12, 0.85)
		bg.border_color = Color.BLACK
		bg.set_border_width_all(3)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color("d4553f")
		fill.border_color = Color.BLACK
		fill.set_border_width_all(3)
		_boss_bar.add_theme_stylebox_override("background", bg)
		_boss_bar.add_theme_stylebox_override("fill", fill)
		_boss_box.add_child(_boss_bar)
	_boss_box.visible = title != ""
	_boss_name.text = title
	_boss_bar.value = value


func set_boss_health(value: float) -> void:
	if _boss_bar:
		_boss_bar.value = value


func boss_bar_visible() -> bool:
	return _boss_box != null and _boss_box.visible


## The boss is dead: the run is won. Same summary as a death, with the win layout.
func show_victory() -> void:
	if _ended:
		return
	_ended = true
	if _run:
		_run.won = true
		_run.finish()
	await get_tree().create_timer(2.5).timeout
	$Margin.hide()
	wave_label.hide()
	if _boss_box:
		_boss_box.hide()
	var popup := RunEndPopup.new()
	end_popup = popup
	add_child(popup)
	popup.present(_run.summary() if _run else {"won": true})


func _on_died() -> void:
	_ended = true
	if _run:
		_run.finish()
	if _banner_tween:
		_banner_tween.kill()
	banner.visible = false
	await get_tree().create_timer(game_over_delay).timeout
	$Margin.hide()
	wave_label.hide()
	var popup := RunEndPopup.new()
	end_popup = popup
	add_child(popup)
	popup.present(_run.summary() if _run else {})
