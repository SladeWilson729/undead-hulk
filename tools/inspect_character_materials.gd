extends SceneTree
func _init() -> void:
	for path in ["res://assets/hulk/hulk_idle.fbx","res://assets/humans/soldier_a_run.fbx","res://assets/humans/soldier_b_run.fbx","res://assets/humans/soldier_c_run.fbx","res://assets/humans/soldier_d_run.fbx"]:
		var model = load(path).instantiate()
		print(path)
		inspect(model)
		model.free()
	quit()
func inspect(node: Node) -> void:
	if node is MeshInstance3D:
		for i in range(node.mesh.get_surface_count()):
			var mat = node.get_active_material(i)
			if mat is BaseMaterial3D:
				print(node.name," / ",i," color=",mat.albedo_color," texture=",mat.albedo_texture," normal=",mat.normal_enabled," alpha=",mat.transparency," cull=",mat.cull_mode," uv=",mat.uv1_scale)
	for child in node.get_children(): inspect(child)
