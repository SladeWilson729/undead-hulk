class_name Gib
extends RigidBody3D
## One chunk from an exploded human. Built in code (no scene file) because it's just
## a tiny body with a mesh. Bounces off the world, never touches the Hulk or living humans.

## Seconds before the gib shrinks away.
var lifetime: float = 3.0
var _shrinking: bool = false

static var _shapes: Dictionary = {}


## Makes a gib. size = edge length in meters, mat = what it looks like (shirt, skin, or blood).
static func create(size: float, mat: Material) -> Gib:
	var gib := Gib.new()
	gib.collision_layer = 8   # ragdolls layer
	gib.collision_mask = 1    # world only
	gib.mass = 2.0
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	box.material = mat
	mesh_instance.mesh = box
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gib.add_child(mesh_instance)
	var shape := CollisionShape3D.new()
	shape.shape = _shape_for(size)
	gib.add_child(shape)
	return gib


# Reuse one collision shape per size so 100 gibs don't create 100 shape resources.
static func _shape_for(size: float) -> SphereShape3D:
	var key := snappedf(size, 0.05)
	if not _shapes.has(key):
		var s := SphereShape3D.new()
		s.radius = key * 0.5
		_shapes[key] = s
	return _shapes[key]


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if global_position.y < -30.0:
		queue_free()
	elif lifetime <= 0.4 and not _shrinking:
		_shrinking = true
		var tween := create_tween()
		tween.tween_property(get_child(0), "scale", Vector3.ONE * 0.01, 0.4)
		tween.tween_callback(queue_free)
