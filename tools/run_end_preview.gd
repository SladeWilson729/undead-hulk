extends SceneTree
func _init() -> void:
	check.call_deferred()

func check() -> void:
	var run := Run.new()
	run.best_path = "res://docs/run-best-test.cfg"
	root.add_child(run)
	run.best_score = 0
	run.wave = 3
	var human := Human.new()
	human.death_cause = KillCause.SMASHED
	run.record_kill(human)
	assert(run.score == 15)  # Smashed 10 x1.5 (wave 3 at +0.25 per wave).
	human.death_cause = KillCause.FRIENDLY_FIRE
	human.bounty = 50
	human.kind_name = "Rocket soldier"
	run.record_kill(human)
	run.record_juggles(2)
	run.record_splat()
	run.record_wave_cleared(2)
	run.record_wave_cleared(2)
	# + Friendly Fire 35x1.5=53, bounty 50x1.5=75, juggles 2x40x1.5=120, splat 15x1.5=23, wave 2 clear 200.
	assert(run.score == 486)
	assert(run.kills == 2)
	assert(run.kill_points_total + run.bounty_total + run.style_total + run.wave_total == run.score)
	run.finish()
	assert(run.save_ok and run.new_best)
	run.record_kill(human)
	run.record_juggles(1)
	run.record_splat()
	run.record_wave_cleared(3)
	assert(run.score == 486 and run.kills == 2)
	var restored := Run.new()
	restored.best_path = run.best_path
	root.add_child(restored)
	assert(restored.best_score == 486)
	restored.finish()
	assert(not restored.new_best)
	DirAccess.remove_absolute(run.best_path)
	human.free()
	run.queue_free()
	restored.queue_free()
	print("RUN SUMMARY PASS: wave multiplier, bounty, juggle, splat, wave bonus, duplicate clear, death freeze, best score reload.")
	if "--render" not in OS.get_cmdline_user_args():
		quit()
		return
	var popup = load("res://scripts/ui/run_end_popup.gd").new()
	root.add_child(popup)
	popup.present({"score":12870,"best":12870,"new_best":true,"wave":7,"kills":68,"waves_cleared":6,"kills_by_cause":[["Smashed",23],["Stomped",14],["Tackled",6],["Eaten",4],["Yeeted",7],["Blown Up",9],["Crushed",10],["Buried",8],["Friendly Fire",9],["Fell",2]],"augments":["Thick Skull","Long Arms","Bottomless Gut","Bobbleheads","Aftershock"],"kill_points":6870,"bounty_points":1800,"style_points":2100,"wave_points":2100,"juggles":12,"splats":8,"specials":{"Rocket soldier":4,"Ninja":2}})
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/run-end-popup.png")
	root.size = Vector2i(960,540)
	await create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/run-end-popup-small.png")
	print("POPUP PREVIEW PASS: large and small viewport renders.")
	quit()

