@tool
class_name BreakablePillar
extends StaticBody3D
## A brick pillar the Hulk can smash. Punch or ground pound it and it bursts into rubble
## that flies away from him and kills any soldier it hits hard enough.
##
## How it works (the "pre-broken" trick every game uses):
##   - The pillar is built in code out of ~24 brick chunks that sit perfectly still.
##     It looks like one solid pillar and costs one box collider.
##   - On the hit, each chunk becomes a RubbleChunk rigid body in the exact same spot,
##     gets a velocity, and flies. The bottom layer stays behind as a broken stump.
##   - No mesh cutting at runtime, so it's cheap and looks the same every time.
##
## Placement: drop this node in a level with its origin on the floor. It builds itself,
## in the editor too (@tool), so you can see and size it. Nothing it builds is saved
## into the scene; it rebuilds every time it loads.
##
## Brick texture: the painterly brick shader normally maps bricks in world space, which
## would make the bricks "swim" across a flying chunk. We build each chunk's UVs from its
## position inside the pillar instead, so the brick pattern is glued to the chunk and
## looks identical before and after the break.

signal smashed(position: Vector3)

const BRICK_MATERIAL := preload("res://assets/materials/painterly/brick.tres")
const RUBBLE_SCRIPT := preload("res://scripts/level/rubble_chunk.gd")
const COMIC := preload("res://scripts/vfx/comic_wall_impact.gd")
## Must match brick_size_meters in brick.tres so chunk seams fall on mortar lines.
const BRICK_SIZE := Vector2(0.5, 0.22)

@export_group("Shape")
## Width, height, depth in meters. 1.0 wide = two bricks; 3.96 tall = 18 brick rows.
@export var size: Vector3 = Vector3(1.0, 3.96, 1.0):
	set(value):
		size = value
		if is_inside_tree():
			_build()
## Height of one chunk layer. 0.44 = two brick rows, so breaks follow the mortar.
@export var layer_height: float = 0.44

@export_group("Burst")
## Sideways speed (m/s) of chunks at the height the hit lands. Chunks further up or down get less.
@export var burst_speed: float = 14.0
## Extra upward speed (m/s) so the spray arcs instead of skidding along the floor.
@export var burst_lift: float = 3.5
## How far chunks fan out from the hit direction (0 = laser line, 1 = wide cone).
@export_range(0.0, 1.0) var spread: float = 0.35
## Tumble speed in radians/second.
@export var spin: float = 10.0

@export_group("Rubble")
## A chunk at least this fast (m/s) kills a soldier on contact.
@export var kill_speed: float = 6.0
## Seconds before rubble sinks away. 0 = rubble stays forever.
@export var rubble_lifetime: float = 8.0
@export var chunk_mass: float = 20.0

var broken: bool = false

var _chunks: Array[MeshInstance3D] = []
var _stump: MeshInstance3D
var _collider: CollisionShape3D
var _chunk_material: ShaderMaterial


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group("breakables")
		collision_layer = 1
		collision_mask = 0
	_build()


## Half the pillar's widest side. Attacks add this to their reach so you hit the
## pillar's face, not just its center line.
func footprint_radius() -> float:
	return maxf(size.x, size.z) * 0.5


## Smash it. direction = which way the rubble flies (flattened). impact_height = meters
## above the pillar's base where the hit lands; chunks near it fly fastest.
## power scales the whole burst (the pound uses less sideways, more lift).
func take_hit(direction: Vector3, impact_height: float = 1.5, power: float = 1.0) -> void:
	if broken:
		return
	broken = true
	direction.y = 0.0
	direction = direction.normalized() if direction.length() > 0.01 else -global_basis.z
	var impact := global_position + Vector3.UP * impact_height - direction * footprint_radius()
	var container := get_parent()
	for mesh in _chunks:
		var local_center := mesh.position
		var chunk: RubbleChunk = RUBBLE_SCRIPT.new()
		chunk.kill_speed = kill_speed
		chunk.lifetime = rubble_lifetime
		chunk.mass = chunk_mass
		var bounce := PhysicsMaterial.new()
		bounce.bounce = 0.15
		bounce.friction = 0.8
		chunk.physics_material_override = bounce
		container.add_child(chunk)
		chunk.global_transform = global_transform * Transform3D(Basis.IDENTITY, local_center)
		mesh.reparent(chunk, false)
		mesh.position = Vector3.ZERO
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		# Slightly smaller than the visual, so neighbors don't start overlapping and
		# shove each other apart with a physics "pop".
		box.size = (mesh.mesh as ArrayMesh).get_aabb().size * 0.9
		shape.shape = box
		chunk.add_child(shape)
		chunk.reset_physics_interpolation()
		chunk.linear_velocity = _chunk_velocity(local_center, direction, impact_height, power)
		chunk.angular_velocity = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spin
	_chunks.clear()
	# What's left standing: the bottom layer, as a broken stump with its own collider.
	var stump_box := BoxShape3D.new()
	stump_box.size = Vector3(size.x, layer_height, size.z)
	_collider.shape = stump_box
	_collider.position = Vector3(0.0, layer_height * 0.5, 0.0)
	_spawn_dust(impact, direction)
	_spawn_comic(impact)
	smashed.emit(impact)


## Hit height matters: chunks at the fist fly hardest, the top of the pillar mostly
## topples and rains down (which is what crushes soldiers standing behind it).
func _chunk_velocity(local_center: Vector3, direction: Vector3, impact_height: float, power: float) -> Vector3:
	var weight := clampf(1.0 - absf(local_center.y - impact_height) / (size.y * 0.8), 0.15, 1.0)
	var outward := global_basis * Vector3(local_center.x, 0.0, local_center.z)
	outward = outward.normalized() if outward.length() > 0.01 else Vector3.ZERO
	var jitter := Vector3(randf_range(-1, 1), 0.0, randf_range(-1, 1)) * spread
	var dir := (direction + outward * spread + jitter).normalized()
	var v := dir * burst_speed * weight * power * randf_range(0.8, 1.2)
	v.y = burst_lift * weight * randf_range(0.5, 1.2)
	return v


## Rebuilds the stump, the chunks, and the solid collider from `size`.
func _build() -> void:
	for child in get_children():
		if child.has_meta("pillar_part"):
			remove_child(child)
			child.queue_free()
	_chunks.clear()
	broken = false
	_chunk_material = BRICK_MATERIAL.duplicate() as ShaderMaterial
	_chunk_material.set_shader_parameter("world_mapping", false)
	# UVs are already in brick units (see _box_mesh), so 1 UV = 1 brick.
	_chunk_material.set_shader_parameter("bricks_per_uv", Vector2.ONE)

	_collider = CollisionShape3D.new()
	_collider.set_meta("pillar_part", true)
	var solid := BoxShape3D.new()
	solid.size = size
	_collider.shape = solid
	_collider.position = Vector3(0.0, size.y * 0.5, 0.0)
	add_child(_collider)

	var layers := maxi(2, roundi(size.y / layer_height))
	var lh := size.y / layers
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	_stump = _add_piece(Vector3(-hx, 0.0, -hz), Vector3(hx, lh, hz), false)
	for layer in range(1, layers):
		var y0 := layer * lh
		var y1 := y0 + lh
		match layer % 4:
			0, 2:  # Quarters.
				for sx in [-1, 1]:
					for sz in [-1, 1]:
						var a := Vector3(minf(0.0, sx * hx), y0, minf(0.0, sz * hz))
						var b := Vector3(maxf(0.0, sx * hx), y1, maxf(0.0, sz * hz))
						_add_piece(a, b, true)
			1:  # Two slabs split across X: bricks overlap the quarter seams like real brickwork.
				_add_piece(Vector3(-hx, y0, -hz), Vector3(0.0, y1, hz), true)
				_add_piece(Vector3(0.0, y0, -hz), Vector3(hx, y1, hz), true)
			3:  # Two slabs split across Z.
				_add_piece(Vector3(-hx, y0, -hz), Vector3(hx, y1, 0.0), true)
				_add_piece(Vector3(-hx, y0, 0.0), Vector3(hx, y1, hz), true)


## One box chunk between corners a and b (pillar-local). Mesh is centered on the chunk
## so it spins around its own middle once it becomes a rigid body.
func _add_piece(a: Vector3, b: Vector3, is_chunk: bool) -> MeshInstance3D:
	var center := (a + b) * 0.5
	var mi := MeshInstance3D.new()
	mi.set_meta("pillar_part", true)
	mi.mesh = _box_mesh(b - a, center)
	mi.material_override = _chunk_material
	mi.position = center
	add_child(mi)
	if is_chunk:
		_chunks.append(mi)
	return mi


## Box mesh whose UVs come from the chunk's position in the pillar, using the same planar
## projection as the brick shader's world mapping. Neighboring chunks line up into one
## continuous brick wall, and the pattern travels with the chunk when it flies.
func _box_mesh(extent: Vector3, center: Vector3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := extent * 0.5
	# (normal, tangent axis u, axis v) per face; corners built from them.
	var faces := [
		[Vector3.RIGHT, Vector3.FORWARD, Vector3.UP],
		[Vector3.LEFT, Vector3.BACK, Vector3.UP],
		[Vector3.UP, Vector3.RIGHT, Vector3.FORWARD],
		[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK],
		[Vector3.BACK, Vector3.RIGHT, Vector3.UP],
		[Vector3.FORWARD, Vector3.LEFT, Vector3.UP],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var corners := [
			n * h - u * h - v * h,
			n * h + u * h - v * h,
			n * h + u * h + v * h,
			n * h - u * h + v * h,
		]
		var uvs: Array[Vector2] = []
		for c in corners:
			uvs.append(_planar_uv(c + center, n))
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_normal(n)
			st.set_uv(uvs[i])
			st.add_vertex(corners[i])
	return st.commit()


## Same projection the brick shader uses: top faces map XZ, side faces map their
## horizontal axis and -Y, divided by the brick size.
static func _planar_uv(p: Vector3, n: Vector3) -> Vector2:
	var a := n.abs()
	var planar: Vector2
	if a.y > maxf(a.x, a.z):
		planar = Vector2(p.x, p.z)
	elif a.x > a.z:
		planar = Vector2(p.z, -p.y)
	else:
		planar = Vector2(p.x, -p.y)
	return planar / BRICK_SIZE


func _spawn_dust(at: Vector3, direction: Vector3) -> void:
	var dust := CPUParticles3D.new()
	dust.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	dust.one_shot = true
	dust.emitting = false
	dust.amount = 40
	dust.lifetime = 1.0
	dust.explosiveness = 0.95
	dust.direction = (direction + Vector3.UP * 0.6).normalized()
	dust.spread = 55.0
	dust.initial_velocity_min = 2.0
	dust.initial_velocity_max = 7.0
	dust.gravity = Vector3(0.0, -2.0, 0.0)
	dust.damping_min = 3.0
	dust.damping_max = 5.0
	dust.scale_amount_min = 0.6
	dust.scale_amount_max = 1.6
	var puff := SphereMesh.new()
	puff.radius = 0.18
	puff.height = 0.36
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.62, 0.52)
	mat.roughness = 1.0
	puff.material = mat
	dust.mesh = puff
	get_parent().add_child(dust)
	dust.global_position = at
	dust.emitting = true
	get_tree().create_timer(1.4).timeout.connect(dust.queue_free)


## Big "KRAK!" in the same comic style as the wall impacts.
func _spawn_comic(at: Vector3) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var comic := COMIC.new()
	comic.word = "KRAK!"
	comic.style = 1
	comic.anchor = at + Vector3.UP * 0.6
	layer.add_child(comic)
	get_tree().create_timer(1.2).timeout.connect(layer.queue_free)
