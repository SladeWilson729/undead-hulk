extends SceneTree
## Run with -- --original for the imported-material comparison.
func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(42)
	var original := "--original" in OS.get_cmdline_user_args()
	var main = load("res://scenes/level/main.tscn").instantiate()
	main.get_node("Spawner").auto_start = false
	main.get_node("Hulk").painterly_enabled = not original
	root.add_child(main)
	current_scene = main
	main.hulk.camera = null
	main.hulk.set_physics_process(false)
	main.hulk.rotation.y = PI
	main.camera_rig.set_process(false)
	main.camera_rig.set_physics_process(false)
	var camera := Camera3D.new()
	main.add_child(camera)
	camera.global_position = Vector3(6,5.2,12)
	camera.look_at(Vector3(0,1.6,0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 11.5
	camera.current = true
	main.get_node("HUD").visible = false
	var soldiers: Array[Human] = []
	for index in range(4):
		var human := load("res://scenes/enemies/human.tscn").instantiate() as Human
		human.variant = SoldierVariants.VARIANTS[index]
		human.painterly_enabled = not original
		main.enemies.add_child(human)
		human.position = Vector3([-4.0,-2.2,2.2,4.0][index],0,0)
		human.rotation.y = PI
		human.set_physics_process(false)
		SoldierVariants.find_player(human.model).pause()
		soldiers.append(human)
	for frame in range(30):
		await process_frame
	await RenderingServer.frame_post_draw
	var suffix := "original" if original else "painted"
	root.get_texture().get_image().save_png("res://docs/characters-"+suffix+".png")
	if not original:
		for character in [main.hulk] + soldiers:
			var mesh := Hulk._find_mesh(character)
			assert(mesh.get_active_material(0) is ShaderMaterial,"Every character must receive the shader")
			assert(mesh.get_active_material(0).get_shader_parameter("albedo_texture") != null,"Keep original albedo")
		assert(main.hulk.body_mesh.get_active_material(0).get_shader_parameter("use_normal_map"),"Keep Hulk normal map")
		main.hulk.health.take_damage(1)
		assert(main.hulk.body_mesh.material_overlay.albedo_color.a > 0.0,"Keep hurt flash")
		var duplicate := load("res://scenes/enemies/human.tscn").instantiate() as Human
		duplicate.variant = SoldierVariants.VARIANTS[0]
		main.enemies.add_child(duplicate)
		assert(Hulk._find_mesh(duplicate).get_active_material(0) == Hulk._find_mesh(soldiers[0]).get_active_material(0),"Reuse materials across soldier instances")
		main.deaths.explode_chance = 0.0
		var mesh := Hulk._find_mesh(soldiers[0])
		var painted := mesh.get_active_material(0)
		soldiers[0].kill(Vector3.UP*3)
		assert(mesh.get_active_material(0) == painted,"Ragdolls retain paint after reparenting")
	print("CHARACTER PASS: ",suffix," rendered; styled checks cover all variants, textures, normal map, hurt overlay, sharing and ragdoll transfer.")
	quit()
