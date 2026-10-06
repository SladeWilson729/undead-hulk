extends Node3D
## One-shot presentation, downstream of GroundPound's authoritative impact.
## Call play() after adding to the tree, from the physics impact callback.
@export_range(0.5,20.0) var radius: float = 6.0
@export_range(1.5,8.0) var lifetime: float = 3.6
@export_range(0,48) var debris_count: int = 24
@export var pattern_seed: int = 17
@export var force_color := Color(0.72,0.85,0.75)
const FORCE_SHADER = preload("res://shaders/stomp_force.gdshader")
const CRACK_SHADER = preload("res://shaders/stomp_cracks.gdshader")
const ASPHALT = preload("res://assets/materials/painterly/asphalt.tres")
var age: float = 0.0
var _playing := false
var _materials: Array[ShaderMaterial] = []
var _chips: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

func play() -> void:
	if _playing:
		return
	_playing = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_to_group("ground_stomp_effects")
	_rng.seed = pattern_seed
	_build_waves()
	_build_cracks()
	_build_debris()

func _process(delta: float) -> void:
	if not _playing:
		return
	age += delta
	for material in _materials:
		material.set_shader_parameter("age",age)
	for chip in _chips:
		var node: MeshInstance3D = chip.node
		var t := maxf(age-float(chip.delay),0.0)
		var flight: float = chip.flight
		node.visible = age >= float(chip.delay) and t < 1.5
		var travel := minf(t,flight)
		node.position = chip.origin + chip.velocity*travel
		node.position.y += maxf(0.0,4.5*travel-9.0*travel*travel)
		node.rotation = chip.spin*travel
		node.scale = Vector3.ONE*(1.0-smoothstep(0.9,1.5,t))
	if age >= lifetime:
		queue_free()

func _build_waves() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(128):
		for band in range(4):
			var a := Vector2(float(segment)/128.0,float(band)/4.0)
			var b := Vector2(float(segment+1)/128.0,float(band)/4.0)
			var c := Vector2(float(segment+1)/128.0,float(band+1)/4.0)
			var d := Vector2(float(segment)/128.0,float(band+1)/4.0)
			for uv in [a,b,c,a,c,d]:
				surface.set_uv(uv)
				surface.add_vertex(Vector3.ZERO)
	var mesh := surface.commit()
	for index in range(3):
		var material := ShaderMaterial.new()
		material.shader = FORCE_SHADER
		material.set_shader_parameter("radius",radius*(1.0-float(index)*0.12))
		material.set_shader_parameter("delay",float(index)*0.13)
		material.set_shader_parameter("force_color",force_color)
		_materials.append(material)
		var wave := _mesh_node(mesh,material)
		wave.custom_aabb = AABB(Vector3(-radius-1,-1,-radius-1),Vector3((radius+1)*2,3,(radius+1)*2))

func _build_cracks() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for spoke in range(13):
		var angle := float(spoke)*TAU/13.0+_rng.randf_range(-0.13,0.13)
		var previous := Vector3(cos(angle),0,sin(angle))*0.3
		for step_index in range(1,10):
			var distance := float(step_index)/9.0*radius*_rng.randf_range(0.88,1.0)
			var heading := angle+_rng.randf_range(-0.1,0.1)
			var point := Vector3(cos(heading),0,sin(heading))*distance
			_crack_segment(surface,previous,point,lerpf(0.095,0.025,distance/radius))
			if step_index == 4 or step_index == 7:
				var branch := point+Vector3(cos(heading+0.65),0,sin(heading+0.65))*radius*0.18
				_crack_segment(surface,point,branch,0.035)
			previous = point
	var material := ShaderMaterial.new()
	material.shader = CRACK_SHADER
	material.set_shader_parameter("lifetime",lifetime)
	_materials.append(material)
	_mesh_node(surface.commit(),material)

func _crack_segment(surface: SurfaceTool, a: Vector3, b: Vector3, width: float) -> void:
	var side := (b-a).normalized().cross(Vector3.UP)*width
	var points: Array[Vector3] = []
	for point in [a-side,a+side,b+side,b-side]:
		var hit := _ground(point)
		if hit.is_empty():
			return
		points.append(to_local(hit.position)+Vector3.UP*0.065)
	var uvs := [Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1)]
	for index in [0,1,2,0,2,3]:
		surface.set_uv(uvs[index])
		surface.set_color(Color(clampf(points[index].length()/radius,0,1),0,0))
		surface.add_vertex(points[index])

func _ground(point: Vector3) -> Dictionary:
	var world := to_global(point)
	var query := PhysicsRayQueryParameters3D.create(world+Vector3.UP*0.35,world-Vector3.UP*0.65,1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.normal.dot(Vector3.UP) < 0.85:
		return {}
	return hit

func _build_debris() -> void:
	var material := ASPHALT.duplicate() as ShaderMaterial
	material.set_shader_parameter("world_mapping",false)
	for index in range(debris_count):
		var angle := _rng.randf()*TAU
		var direction := Vector3(cos(angle),0,sin(angle))
		var origin := direction*_rng.randf_range(0.6,radius*0.65)
		var hit := _ground(origin)
		var velocity := direction*_rng.randf_range(0.5,1.6)
		if hit.is_empty() or _ground(origin+velocity*0.5).is_empty():
			continue
		origin = to_local(hit.position)+Vector3.UP*0.12
		var shard := CylinderMesh.new()
		shard.radial_segments = 5
		shard.rings = 1
		shard.top_radius = _rng.randf_range(0.09,0.23)
		shard.bottom_radius = shard.top_radius*0.72
		shard.height = _rng.randf_range(0.08,0.17)
		var node := _mesh_node(shard,material)
		node.position = origin
		_chips.append({"node":node,"origin":origin,"velocity":velocity,"flight":0.5,"delay":origin.length()/radius*0.2,"spin":Vector3(_rng.randf_range(-5,5),_rng.randf_range(-5,5),_rng.randf_range(-5,5))})

func _mesh_node(mesh: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node
