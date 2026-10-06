extends SceneTree
## Rendered integration check: actual Hulk landing, repeated stomp, cleanup.
## godot --path . --fixed-fps 60 -s tools/stomp_preview.gd
var impacts := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(17)
	var main = load("res://scenes/level/main.tscn").instantiate()
	main.get_node("Spawner").auto_start = false
	root.add_child(main)
	current_scene = main
	main.hulk.camera = null
	main.hulk.pound.pounded.connect(func(_kills: int) -> void: impacts += 1)
	for frame in range(20):
		await physics_frame
	main.hulk.pound.start()
	while impacts < 1:
		await physics_frame
	assert(get_nodes_in_group("ground_stomp_effects").size() == 1,"Landing must create one effect")
	for frame in range(12):
		await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/stomp-impact.png")
	for frame in range(50):
		await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/stomp-cracks.png")
	for frame in range(220):
		await physics_frame
	assert(get_nodes_in_group("ground_stomp_effects").is_empty(),"Effect must clean itself up")
	assert(main.hulk.pound.phase == GroundPound.Phase.READY,"Cooldown must still finish")
	main.hulk.position.z = 2.9
	main.hulk.pound.kill_radius = 3.0
	main.hulk.pound.start()
	while impacts < 2:
		await physics_frame
	assert(get_nodes_in_group("ground_stomp_effects").size() == 1,"Repeated stomp creates a fresh effect")
	var effect = get_nodes_in_group("ground_stomp_effects")[0]
	assert(is_equal_approx(effect.radius,3.0),"Visual range must follow gameplay radius")
	var crack_mesh: MeshInstance3D = effect.get_child(3)
	var vertices: PackedVector3Array = crack_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex in vertices:
		assert(absf(crack_mesh.to_global(vertex).z) <= 4.001,"Cracks must stay on the bridge")
	for frame in range(240):
		await physics_frame
	assert(get_nodes_in_group("ground_stomp_effects").is_empty(),"Repeated effect must clean up")
	print("STOMP PASS: two actual landings, effect count, cooldown, cleanup, changed radius and bridge-edge crack clipping; rendered captures saved.")
	quit()
