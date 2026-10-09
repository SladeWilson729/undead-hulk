extends SceneTree
func _init() -> void:
	check.call_deferred()
func check() -> void:
	var main = load("res://scenes/level/main.tscn").instantiate()
	main.get_node("Spawner").auto_start = false
	root.add_child(main)
	current_scene = main
	main.run.best_path = "res://docs/integration-best-test.cfg"
	main.run.best_score = 0
	main.run.wave = 3
	main.run.record_juggles(2)
	await create_timer(0.2).timeout
	main.hulk.health.take_damage(10000)
	assert(main.run.ended)
	await create_timer(1.7).timeout
	var popup = main.hud.get_child(main.hud.get_child_count()-1)
	assert(popup.data.score == 120)  # 2 juggles x 40 x1.5 (wave 3).
	assert(popup.sheet.get_node("NewRun").has_focus())
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/run-end-in-game.png")
	popup.sheet.get_node("NewRun").pressed.emit()
	await process_frame
	await process_frame
	assert(current_scene != main)
	assert(current_scene.run.score == 0 and not current_scene.run.ended)
	DirAccess.remove_absolute("res://docs/integration-best-test.cfg")
	print("INTEGRATION PASS: actual health death, delayed popup, focus, retry and fresh score.")
	quit()
