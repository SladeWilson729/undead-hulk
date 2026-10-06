extends SceneTree
## BALANCE BOT (dev tool, not part of the game).
## A simple scripted player: pounds when 5+ humans are within 3 m and the pound is ready,
## otherwise punches the nearest human in reach. With kite=1 it also backs away from the
## crowd while the pound is on cooldown. Prints the wave it died on and a per-wave HP timeline.
##
## Run from the project folder (runs ~40x faster than real time):
##   godot --headless --fixed-fps 60 --path . -s tools/balance_bot.gd -- 4 6 1
## Args after "--": pound_cooldown kill_radius kite(0/1)

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var cooldown := float(args[0]) if args.size() > 0 else 4.0
	var radius := float(args[1]) if args.size() > 1 else 6.0
	var kite := args.size() > 2 and args[2] == "1"
	var main = load("res://scenes/level/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var hulk: Hulk = main.hulk
	hulk.camera = null
	hulk.pound.cooldown = cooldown
	hulk.pound.kill_radius = radius
	var sp: WaveSpawner = main.spawner
	var t := 0.0
	var wave_times := {}
	var pounds := 0
	while not hulk.health.is_dead and t < 900.0 and sp.wave < 25:
		await physics_frame
		t += 1.0 / 60.0
		if not wave_times.has(sp.wave): wave_times[sp.wave] = [snappedf(t, 1), hulk.health.current]
		var near := 0
		var nearest: Human = null
		var nd := 99.0
		var centroid := Vector3.ZERO
		for h in get_nodes_in_group("enemies"):
			var d: float = Vector2(h.global_position.x - hulk.global_position.x, h.global_position.z - hulk.global_position.z).length()
			if d < 3.0: near += 1
			if d < nd: nd = d; nearest = h
			centroid += h.global_position
		if kite:
			# Kiter: when the pound is down and 4+ are on him, back away from the crowd's center.
			for a in ["move_left", "move_right", "move_forward", "move_back"]: Input.action_release(a)
			var n := get_nodes_in_group("enemies").size()
			if n > 0 and near >= 4 and hulk.pound.phase == GroundPound.Phase.COOLDOWN:
				var away := hulk.global_position - centroid / n
				if absf(away.x) > 0.3: Input.action_press("move_right" if away.x > 0 else "move_left")
				if absf(away.z) > 0.3: Input.action_press("move_back" if away.z > 0 else "move_forward")
		if hulk.pound.phase == GroundPound.Phase.READY and near >= 5:
			hulk.pound.start(); pounds += 1 if hulk.pound.phase == GroundPound.Phase.RISING else 0
		elif nearest and nd < 3.2:
			var to := nearest.global_position - hulk.global_position
			hulk.rotation.y = atan2(-to.x, -to.z)
			hulk.punch.start()
	print("RESULT cooldown=%.1f radius=%.1f kite=%s -> died=%s wave=%d kills=%d time=%ds pounds=%d" % [cooldown, radius, kite, hulk.health.is_dead, sp.wave, sp.kills, int(t), pounds])
	var keys := wave_times.keys(); keys.sort()
	var line := ""
	for k in keys: line += " w%d@%ds(hp%d)" % [k, wave_times[k][0], wave_times[k][1]]
	print("TIMELINE" + line)
	quit()
