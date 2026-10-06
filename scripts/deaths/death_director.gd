class_name DeathDirector
extends Node3D
## Decides HOW each human dies and owns everything left behind: bodies, gibs, stains, blood.
## Lives in main.tscn as "Deaths"; every corpse, gib and stain is parented under it.
##
## Death types:
##   RAGDOLL  - jointed body flops through the air. Used while fewer than ragdoll_cap are active.
##   CHEAP    - single spinning FlyingBody. Used once the ragdoll cap is hit, so frame rate holds.
##   EXPLODE  - instant gibs + blood. Random chance on any kill, OR hitting a body that's still airborne (juggle).
##   SPLAT    - a body that hits something hard enough bursts into a stain on impact.
## Light impacts just leave a small stain and the body keeps tumbling.

signal exploded(position: Vector3)
signal splatted(position: Vector3)

@export_group("Budget")
## Max jointed ragdolls alive at once. Above this, deaths use the cheap single-body version.
@export var ragdoll_cap: int = 15
## Max stains on the floor. The oldest is recycled when a new one appears.
@export var stain_cap: int = 60
## Max gibs alive at once.
@export var gib_cap: int = 160

@export_group("Rules")
## Chance (0-1) that any kill explodes immediately instead of flying.
@export_range(0.0, 1.0) var explode_chance: float = 0.1
## Impact strength (m/s of sudden velocity change) that leaves a small stain.
## Tuned from measured impacts (see DEVLOG): normal punch landings 10-17, wall slams 17-25,
## falls from a ground pound 15-16, pound edge landings 9-13.
@export var stain_speed: float = 7.0
## Impact strength that SPLATS the body: it bursts on contact and leaves a big stain.
## 15 = wall slams and big falls splat; most ordinary punch landings tumble and leave a smear.
@export var splat_speed: float = 15.0
## Impacts above this height are ignored (stains only go on the floor).
@export var max_impact_height: float = 4.5
@export var gibs_per_explosion: int = 10

@export_group("Look")
## Cartoony red, agreed in the design decisions. Applied to stains, blood, and gibs.
@export var blood_color: Color = Color(0.85, 0.04, 0.08)

const RAGDOLL_SCENE := preload("res://scenes/enemies/ragdoll.tscn")
const FLYING_BODY_SCENE := preload("res://scenes/enemies/flying_body.tscn")
const WALL_COMIC := preload("res://scripts/vfx/comic_wall_impact.gd")

@export_group("Comic wall impacts")
@export var comic_impacts_enabled: bool = true
@export var comic_min_speed: float = 6.5
@export var comic_max_visible: int = 6
var _comic_layer: CanvasLayer
var _comic_index: int = 0

# Splat textures are generated once per game run and shared (see _make_splat_texture).
static var _splat_textures: Array[ImageTexture] = []

var active_ragdolls: int = 0
var active_gibs: int = 0
var _stains: Array[Decal] = []
var _blood_mat: StandardMaterial3D
var _skin_mat: StandardMaterial3D
var _pants_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("death_director")
	_comic_layer = CanvasLayer.new()
	_comic_layer.layer = 3
	add_child(_comic_layer)
	_blood_mat = _flat_mat(blood_color, 0.3)
	_skin_mat = _flat_mat(Color(0.92, 0.72, 0.55), 0.8)
	_pants_mat = _flat_mat(Color(0.18, 0.2, 0.28), 0.9)
	if _splat_textures.is_empty():
		for i in 4:
			_splat_textures.append(_make_splat_texture(i))


## Shared by living knockback and both corpse representations. Never changes damage.
func show_wall_comic(source: Node, contact: Vector3, normal: Vector3, speed: float) -> void:
	if not comic_impacts_enabled or speed < comic_min_speed or absf(normal.y) > 0.35:
		return
	var now := Time.get_ticks_msec()
	if now-int(source.get_meta("comic_wall_last_ms",-10000)) < 900:
		return
	if _comic_layer.get_child_count() >= comic_max_visible:
		return
	source.set_meta("comic_wall_last_ms",now)
	var comic := WALL_COMIC.new()
	comic.word = ["POW!","OOF!","BIFF!"][_comic_index % 3]
	comic.style = _comic_index % 3
	comic.anchor = contact+normal*0.2+Vector3.UP*0.25
	# Stagger nearby simultaneous hits so one burst doesn't cover another's word.
	var camera := get_viewport().get_camera_3d()
	if camera:
		var screen_scale := clampf(get_viewport().get_visible_rect().size.y/1080.0,0.55,1.5)
		for attempt in range(comic_max_visible):
			var crowded := false
			var candidate := camera.unproject_position(comic.anchor)+comic.screen_offset*screen_scale
			for other in _comic_layer.get_children():
				var other_position: Vector2 = camera.unproject_position(other.anchor)+other.screen_offset*screen_scale
				var difference: Vector2 = (candidate-other_position)/screen_scale
				if absf(difference.x) < 265.0 and absf(difference.y) < 140.0:
					crowded = true
					break
			if not crowded:
				break
			comic.screen_offset.y -= 145.0
	_comic_index += 1
	_comic_layer.add_child(comic)


## Entry point. Human.kill() calls this; the human frees itself right after.
## Ragdolls and cheap bodies take over the soldier's own model, so the corpse is the same
## soldier, in the same pose, as the one that just got hit.
func spawn_death(human: Human, launch_velocity: Vector3) -> void:
	if randf() < explode_chance:
		explode_at(human.global_position + Vector3.UP * 0.9, launch_velocity, human.gib_material)
	elif active_ragdolls < ragdoll_cap:
		_spawn_ragdoll(human, launch_velocity)
	else:
		_spawn_cheap_body(human, launch_velocity)


func _spawn_ragdoll(human: Human, launch_velocity: Vector3) -> void:
	var ragdoll: Ragdoll = RAGDOLL_SCENE.instantiate()
	add_child(ragdoll)
	ragdoll.global_transform = human.global_transform
	human.visual.reparent(ragdoll, true)
	ragdoll.setup(human.visual, human.gib_material, self)
	ragdoll.launch(launch_velocity)
	active_ragdolls += 1
	ragdoll.tree_exiting.connect(func() -> void: active_ragdolls -= 1)


func _spawn_cheap_body(human: Human, launch_velocity: Vector3) -> void:
	var body: FlyingBody = FLYING_BODY_SCENE.instantiate()
	add_child(body)
	# The rigid body spins around its center, so place it at mid-height, not at the feet.
	body.global_transform = Transform3D(human.global_basis, human.global_position + Vector3.UP * 0.9)
	human.visual.reparent(body, true)
	# Freeze the soldier mid-pose; the whole body tumbles as one stiff piece.
	var player := SoldierVariants.find_player(human.visual)
	if player:
		player.pause()
	body.director = self
	body.gib_material = human.gib_material
	body.reset_physics_interpolation()
	body.launch(launch_velocity)


## Called every physics frame by any corpse that registers an impact.
func on_corpse_impact(corpse: Node, position: Vector3, strength: float) -> void:
	if position.y > max_impact_height:
		return
	if strength >= splat_speed:
		splat_at(position)
		corpse.remove_now()
	elif strength >= stain_speed and corpse.small_stains_left > 0:
		corpse.small_stains_left -= 1
		add_stain(position, randf_range(0.8, 1.2))


func splat_at(position: Vector3) -> void:
	add_stain(position, randf_range(2.0, 2.6))
	blood_burst(position + Vector3.UP * 0.3, 28)
	splatted.emit(position)


## Blows a body (or a living soldier, on the random roll) into gibs.
func explode_at(center: Vector3, inherit_velocity: Vector3, uniform: Material) -> void:
	# Chunks in the soldier's uniform color, skin, and plenty of cartoon red.
	var mats: Array[Material] = [uniform, _skin_mat, _blood_mat, _pants_mat, _blood_mat]
	var count := mini(gibs_per_explosion, gib_cap - active_gibs)
	for i in count:
		var gib := Gib.create(randf_range(0.14, 0.3), mats[i % mats.size()])
		add_child(gib)
		var dir := Vector3(randf_range(-1, 1), randf_range(-0.2, 1), randf_range(-1, 1)).normalized()
		gib.global_position = center + dir * 0.3
		gib.reset_physics_interpolation()
		gib.linear_velocity = inherit_velocity * 0.3 + dir * randf_range(6.0, 12.0) + Vector3.UP * 3.0
		gib.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 15.0
		active_gibs += 1
		gib.tree_exiting.connect(func() -> void: active_gibs -= 1)
	blood_burst(center, 45)
	add_stain(center, randf_range(2.6, 3.2))
	exploded.emit(center)


## Bodies still in the air: these are the ones a juggle hit can explode.
func airborne_corpses() -> Array[Node]:
	var result: Array[Node] = []
	for corpse in get_tree().get_nodes_in_group("corpses"):
		if corpse.is_airborne():
			result.append(corpse)
	return result


## Paints a red stain on the floor directly below position.
## Recycles the oldest stain once stain_cap is reached, so the floor never costs more than stain_cap decals.
func add_stain(position: Vector3, size: float) -> void:
	var decal: Decal
	if _stains.size() >= stain_cap:
		decal = _stains.pop_front()
	else:
		decal = Decal.new()
		decal.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		decal.modulate = blood_color
		decal.upper_fade = 0.05
		decal.lower_fade = 0.05
		add_child(decal)
	_stains.append(decal)
	decal.texture_albedo = _splat_textures.pick_random()
	# Thin projection box (0.6 m tall) so it paints the floor and feet, not whole bodies walking through.
	decal.size = Vector3(size, 0.6, size * randf_range(0.8, 1.2))
	decal.global_position = Vector3(position.x, 0.0, position.z)
	decal.rotation = Vector3(0.0, randf() * TAU, 0.0)
	# Pop in: starts small and slaps out to full size. Cartoon timing.
	decal.scale = Vector3(0.3, 1.0, 0.3)
	var tween := decal.create_tween()
	tween.tween_property(decal, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## One-shot spray of red droplets. CPUParticles3D because it works in every renderer
## (including the Mobile/Compatibility ones we'll need for Android later).
func blood_burst(position: Vector3, amount: int) -> void:
	var p := CPUParticles3D.new()
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = 0.8
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 9.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.4
	var drop := SphereMesh.new()
	drop.radius = 0.07
	drop.height = 0.14
	drop.material = _blood_mat
	p.mesh = drop
	add_child(p)
	p.global_position = position
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func _flat_mat(color: Color, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


## Draws a white cartoon splat (a fat center blob plus satellite drops) into an image.
## The decal's modulate color turns it red. Generated in code so there's no art dependency yet.
static func _make_splat_texture(seed_value: int) -> ImageTexture:
	const SIZE := 128
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + seed_value
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var c := SIZE * 0.5
	_fill_circle(img, Vector2(c, c), SIZE * 0.24)
	for i in rng.randi_range(6, 9):
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(SIZE * 0.12, SIZE * 0.3)
		_fill_circle(img, Vector2(c, c) + Vector2.from_angle(ang) * dist, rng.randf_range(SIZE * 0.06, SIZE * 0.13))
	for i in rng.randi_range(8, 12):
		var ang := rng.randf() * TAU
		var dist := rng.randf_range(SIZE * 0.32, SIZE * 0.46)
		_fill_circle(img, Vector2(c, c) + Vector2.from_angle(ang) * dist, rng.randf_range(SIZE * 0.015, SIZE * 0.04))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _fill_circle(img: Image, center: Vector2, radius: float) -> void:
	var x0 := maxi(int(center.x - radius), 0)
	var x1 := mini(int(center.x + radius) + 1, img.get_width() - 1)
	var y0 := maxi(int(center.y - radius), 0)
	var y1 := mini(int(center.y + radius) + 1, img.get_height() - 1)
	var r2 := radius * radius
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if Vector2(x, y).distance_squared_to(center) <= r2:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
