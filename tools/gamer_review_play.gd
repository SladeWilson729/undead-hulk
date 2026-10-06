extends SceneTree
var main
var elapsed := 0.0
var shots := {}
var punches := 0
var punch_hits := 0
var stomps := 0
var stomp_hits := 0
var capture_due := -1.0
func _init():
	_run.call_deferred()
func snap(label: String):
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/review/" + label + ".png")
func _run():
	seed(20261006)
	main = load("res://scenes/level/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	main.hulk.punch.punched.connect(func(hits): punches += 1; punch_hits += hits)
	main.hulk.pound.pounded.connect(func(hits): stomps += 1; stomp_hits += hits; capture_due = elapsed + 0.12)
	var last_wave := -1
	var prior_pound := false
	while elapsed < 90.0 and not main.hulk.health.is_dead:
		await physics_frame
		var dt: float = main.hulk.get_physics_process_delta_time()
		elapsed += dt
		var h = main.hulk
		if main.spawner.wave != last_wave:
			last_wave = main.spawner.wave
			print("REVIEW wave=%d time=%.1f hp=%d kills=%d" % [last_wave, elapsed,h.health.current,main.spawner.kills])
		var nearest = null
		var dist := 999.0
		var near := 0
		for e in get_nodes_in_group("enemies"):
			var d: float = h.global_position.distance_to(e.global_position)
			if d < dist: dist = d; nearest = e
			if d < 5.0: near += 1
		if nearest:
			var ev := InputEventMouseMotion.new()
			ev.position = h.camera.unproject_position(nearest.global_position)
			Input.parse_input_event(ev)
			h.face_point(nearest.global_position, 0.2)
		for a in ["move_left","move_right","move_forward","move_back","punch","ground_pound"]: Input.action_release(a)
		# Opening deliberately tests movement toward the first left spawn; thereafter crowd control.
		if elapsed < 3.0: Input.action_press("move_left")
		elif elapsed > 50.0 and nearest and dist > 4.0:
			var off: Vector2 = h.camera.unproject_position(nearest.global_position) - h.camera.unproject_position(h.global_position)
			if absf(off.x)>40: Input.action_press("move_right" if off.x>0 else "move_left")
		if near >= 4 and h.pound.phase == GroundPound.Phase.READY:
			h.pound.start()
		elif dist < 3.4:
			h.punch.start()
		if capture_due > 0.0 and elapsed >= capture_due and stomps <= 3:
			capture_due = -1
			snap("stomp-%d" % stomps)
		for mark in [3,10,30,60,120,170]:
			if elapsed >= mark and not shots.has(mark): shots[mark] = true; snap("play-%03d" % mark)
	print("REVIEW ACTIVE time=%.1f wave=%d hp=%d kills=%d punches=%d punch_hits=%d stomps=%d stomp_hits=%d" % [elapsed,main.spawner.wave, main.hulk.health.current,main.spawner.kills,punches,punch_hits,stomps,stomp_hits])
	for a in ["move_left","move_right","move_forward","move_back","punch","ground_pound"]: Input.action_release(a)
	var idle := 0.0
	while not main.hulk.health.is_dead and idle < 65.0:
		await physics_frame
		idle += main.hulk.get_physics_process_delta_time()
	await create_timer(1.5).timeout
	await snap("death")
	print("REVIEW IDLE time=%.1f dead=%s wave=%d kills=%d" % [idle,main.hulk.health.is_dead,main.spawner.wave,main.spawner.kills])
	var ev := InputEventAction.new()
	ev.action = "restart"
	ev.pressed = true
	Input.parse_input_event(ev)
	await create_timer(0.5).timeout
	await snap("restart")
	print("REVIEW RESTART hp=%d kills=%d wave=%d" % [current_scene.hulk.health.current,current_scene.spawner.kills,current_scene.spawner.wave])
	quit()

