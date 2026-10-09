class_name AfterimageTrail
extends Node
## Leaves smoke copies of a character behind her while she moves fast: frozen snapshots of her
## exact pose (skinned body and anything she's holding) that glow at the edges, then break up
## into rising smoke and fade. Made for the ninja, so the player can track her through a blur.
## Works on any rigged character: add it as a child and call setup(model).
##
## Each snapshot bakes the skinned mesh in its current pose into a plain mesh
## (MeshInstance3D.bake_mesh_from_current_skeleton_pose). The ghost doesn't follow the skeleton
## afterwards, so it stays exactly where she was.

const SHADER := preload("res://shaders/afterimage.gdshader")

## Seconds between ghosts while she's moving fast enough.
@export var interval: float = 0.07
## How long each ghost lasts.
@export var lifetime: float = 0.4
## Ground speed (m/s) below which no ghosts are left. 0 = always.
@export var min_speed: float = 4.0
## Ghost tint. Pale and slightly violet so it stands out on the blue-grey floor.
@export var smoke_color: Color = Color(0.82, 0.78, 0.95)
@export var rim_color: Color = Color(0.95, 0.92, 1.0)
@export_range(0.0, 1.0) var base_alpha: float = 0.45
## Ghosts grow a touch as they fade, like smoke spreading.
@export var grow: float = 0.08
## Off = no ghosts no matter what (the owner can also force them on with `burst`).
@export var enabled: bool = true

## Set true by the owner for moves that should always trail (the ninja's flip), regardless
## of ground speed.
var burst: bool = false

var _body: CharacterBody3D
var _skinned: Array[MeshInstance3D] = []
var _props: Array[MeshInstance3D] = []  # Rigid things she carries (katanas): copied as-is.
var _timer: float = 0.0
var _material: ShaderMaterial


## model: the character's visual root. Every skinned mesh under it gets baked; every other
## mesh (weapons on bone attachments) gets copied at its current transform.
func setup(model: Node3D) -> void:
	_body = get_parent() as CharacterBody3D
	# Headless runs (automated tests, servers) have no renderer, so skinned meshes can't be
	# baked into poses. Nothing to see there anyway.
	if DisplayServer.get_name() == "headless":
		enabled = false
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.skin != null:
			_skinned.append(m)
		else:
			_props.append(m)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("smoke_color", smoke_color)
	_material.set_shader_parameter("rim_color", rim_color)
	_material.set_shader_parameter("base_alpha", base_alpha)


func _physics_process(delta: float) -> void:
	if not enabled or _body == null or _skinned.is_empty():
		return
	var speed := Vector2(_body.velocity.x, _body.velocity.z).length()
	if not burst and speed < min_speed:
		_timer = 0.0  # Start a fresh trail the moment she speeds up.
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = interval
	_snapshot()


## One ghost of her current pose, parented to the level so it stays put.
func _snapshot() -> void:
	var level := _body.get_parent()
	if level == null:
		return
	var ghost := Node3D.new()
	ghost.name = "Afterimage"
	ghost.add_to_group("afterimages")
	ghost.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	level.add_child(ghost)
	var parts: Array[GeometryInstance3D] = []
	for m in _skinned:
		if not m.is_visible_in_tree():
			continue
		var baked := m.bake_mesh_from_current_skeleton_pose()
		if baked == null:
			continue
		parts.append(_part(ghost, baked, m.global_transform))
	for m in _props:
		if m.is_visible_in_tree() and m.mesh:
			parts.append(_part(ghost, m.mesh, m.global_transform))
	# Fade and grow, then free. The tween belongs to the ghost, so it finishes even if the
	# ninja dies mid-trail.
	var tween := ghost.create_tween()
	tween.tween_method(func(f: float) -> void:
		for p in parts:
			p.set_instance_shader_parameter("fade", f)
		, 0.0, 1.0, lifetime)
	var center := _body.global_position + Vector3.UP * 0.9
	tween.parallel().tween_method(func(s: float) -> void:
		# Grow around her middle, not around the floor.
		ghost.transform = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), center - center * s)
		, 1.0, 1.0 + grow, lifetime)
	tween.tween_callback(ghost.queue_free)


func _part(ghost: Node3D, mesh: Mesh, xf: Transform3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	ghost.add_child(mi)
	mi.global_transform = xf
	return mi
