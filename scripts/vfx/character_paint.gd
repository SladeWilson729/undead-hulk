extends RefCounted
## Preserve imported surface textures; share converted materials across identical units.
static var _cache: Dictionary = {}

static func apply_to(root: Node, preset: ShaderMaterial) -> void:
	if preset == null:
		return
	if root is MeshInstance3D:
		var mesh_instance := root as MeshInstance3D
		if mesh_instance.mesh:
			for surface in range(mesh_instance.mesh.get_surface_count()):
				var source := mesh_instance.get_active_material(surface) as BaseMaterial3D
				if source == null:
					continue
				# Current character imports are opaque/backface-culled. Leave unsupported
				# future glass/hair materials intact rather than silently losing transparency.
				if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					continue
				var key := "%s:%s" % [source.get_instance_id(),preset.get_instance_id()]
				if not _cache.has(key):
					var painted := preset.duplicate() as ShaderMaterial
					painted.set_shader_parameter("albedo_tint",source.albedo_color)
					if source.albedo_texture:
						painted.set_shader_parameter("albedo_texture",source.albedo_texture)
					painted.set_shader_parameter("uv_scale",Vector2(source.uv1_scale.x,source.uv1_scale.y))
					painted.set_shader_parameter("uv_offset",Vector2(source.uv1_offset.x,source.uv1_offset.y))
					painted.set_shader_parameter("use_normal_map",source.normal_enabled and source.normal_texture != null)
					if source.normal_texture:
						painted.set_shader_parameter("normal_texture",source.normal_texture)
					painted.set_shader_parameter("source_normal_scale",source.normal_scale)
					_cache[key] = painted
				mesh_instance.set_surface_override_material(surface,_cache[key])
	for child in root.get_children():
		apply_to(child,preset)
