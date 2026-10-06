extends SceneTree
## Integration checks using actual living, ragdoll and cheap-body wall collisions.
func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(23)
	var main = load("res://scenes/level/main.tscn").instantiate()
	main.get_node("Spawner").auto_start = false
	root.add_child(main)
	current_scene = main
	main.hulk.camera = null
	main.deaths.explode_chance = 0.0
	for frame in range(15):
		await physics_frame
	var human_scene := load("res://scenes/enemies/human.tscn") as PackedScene
	# All three routes hit the north wall, safely away from the Hulk.
	for index in range(3):
		var human := human_scene.instantiate() as Human
		main.enemies.add_child(human)
		human.global_position = Vector3(float(index-1)*3.0,0,-2.8)
		if index < 2:
			main.deaths.ragdoll_cap = 15 if index == 0 else 0
			human.kill(Vector3(0,1,-22))
		else:
			human.shove(Vector3(0,0,-22))
	for frame in range(22):
		await physics_frame
	assert(main.deaths._comic_index == 3,"Each human wall hit must emit once across all three body types")
	assert(get_nodes_in_group("comic_wall_impacts").size() == 3,"All three words should be visible")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/comic-wall-impact.png")
	# Floor impacts and low-speed wall contacts must not create bursts.
	main.deaths.show_wall_comic(main.hulk,Vector3.ZERO,Vector3.UP,25)
	main.deaths.show_wall_comic(main.hulk,Vector3.ZERO,Vector3.FORWARD,2)
	assert(main.deaths._comic_index == 3,"Floor and gentle contacts must be ignored")
	for frame in range(80):
		await physics_frame
	assert(get_nodes_in_group("comic_wall_impacts").is_empty(),"Comic effects must free themselves")
	print("COMIC PASS: ragdoll, cheap body, living shove wall impacts; duplicate suppression; floor/low-speed rejection; cleanup.")
	quit()
