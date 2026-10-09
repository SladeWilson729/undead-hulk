class_name Sfx
extends Node3D
## World sound effects: impacts, crashes, splats, yelps. Lives in main.tscn as "Sfx";
## Main wires gameplay signals to play(). One pool of 3D players on the SFX bus, so sounds
## pan with where they happen (the listener is the gameplay camera).
##
## Each group has:
##   files        - the clips (one is picked at random, never the same twice in a row)
##   rms          - each file's measured loudness (dB RMS), so every clip in a group plays
##                  at `target` regardless of how loud it was generated
##   target       - loudness (dB RMS) the group plays at, before volume_offset
##   max_voices   - at most this many of the group playing at once (a pound kills 20)
##   min_interval - seconds between two starts of the group, so a burst staggers instead
##                  of stacking into one loud phasey blob
##   chance       - 0-1 chance a request actually plays
##   pitch        - random pitch spread (+/-)
##   pitch_base   - (optional) center pitch, default 1.0
##   start / end  - (optional) play only this slice of the file, in seconds. For a file that
##                  holds more than one sound (the sword file has a chop, then a whoosh).
##                  rms is then measured on the slice, not the whole file.
## Re-measure `rms` if a file is regenerated (ffmpeg volumedetect "mean_volume").

const DIR := "res://assets/sound/sound effects/"

## Pool size. Plenty for the worst frame (pound + explosions + yelps).
@export var voices: int = 24
## Distance (m) at which a sound plays at full volume. The camera is ~19 m from the action,
## so 20 keeps everything near the Hulk full and the far end of the bridge ~6 dB down.
@export var unit_size: float = 20.0
@export_range(0.0, 1.0) var panning: float = 0.5

var groups := {
	"punch_hit": {
		"files": ["Heavy_squishy_punch__#1-1791320302351.mp3", "Heavy_thudding_punch_#4-1791320271989.mp3"],
		"rms": [-14.3, -9.1], "target": -11.0, "max_voices": 3, "min_interval": 0.03, "chance": 1.0, "pitch": 0.08,
	},
	"pound_hit": {
		"files": ["cannon_ball_hitting__#4-1791320349115.mp3"],
		"rms": [-22.9], "target": -10.0, "max_voices": 2, "min_interval": 0.1, "chance": 1.0, "pitch": 0.06,
	},
	"pillar_smash": {
		"files": ["a_brick_wall_explodi_#1-1791320635827.mp3"],
		"rms": [-12.6], "target": -11.0, "max_voices": 2, "min_interval": 0.1, "chance": 1.0, "pitch": 0.06,
	},
	"car_impact": {
		"files": ["a_heavy_metal_box_hi_#1-1791320606405.mp3", "a_heavy_metal_box_hi_#4-1791320612238.mp3"],
		# Turned down 8 dB after playtesting: a 4 s crash tail re-triggered by every bounce was too much.
		"rms": [-13.8, -10.7], "target": -20.0, "max_voices": 1, "min_interval": 0.4, "chance": 1.0, "pitch": 0.08,
	},
	"rocket_launch": {
		"files": ["Heavy_rocket_launch__#4-1791513024031.mp3"],
		"rms": [-10.0], "target": -15.0, "max_voices": 2, "min_interval": 0.1, "chance": 1.0, "pitch": 0.05,
	},
	# Whoosh when a rocket comes close to the Hulk: the "incoming!" cue, and the near-miss sound.
	"rocket_flyby": {
		"files": ["Rocket_flying_past_t_#2-1791513065937.mp3"],
		"rms": [-11.7], "target": -14.0, "max_voices": 2, "min_interval": 0.2, "chance": 1.0, "pitch": 0.06,
	},
	"rocket_boom": {
		"files": ["violent_explosion_#3-1791513419677.mp3"],
		"rms": [-6.8], "target": -8.0, "max_voices": 3, "min_interval": 0.05, "chance": 1.0, "pitch": 0.05,
	},
	"splat": {
		"files": ["a_overripe_orange_hi_#1-1791320405861.mp3", "a_rotten_melon_impac_#4-1791320514594.mp3", "Ripe_watermelon_spla_#4-1791320742459.mp3"],
		"rms": [-22.6, -30.5, -25.6], "target": -15.0, "max_voices": 4, "min_interval": 0.04, "chance": 1.0, "pitch": 0.12,
	},
	"yelp": {
		"files": ["a_man_yelping_#1-1791320659837.mp3", "a_man_yelping_#4-1791320668270.mp3", "a_woman_yelping_#1-1791320682536.mp3", "a_woman_yelping_#2-1791320687537.mp3"],
		"rms": [-10.4, -17.2, -8.9, -11.1], "target": -20.0, "max_voices": 2, "min_interval": 0.12, "chance": 0.4, "pitch": 0.1,
	},
	# The ninja's blade landing. The file is a sharp chop (0-0.42 s) then a slow swelling
	# whoosh (0.9-1.65 s); a hit only wants the chop.
	"ninja_hit": {
		"files": ["Heavy_sword_chopping_#2-1791513136725.mp3"],
		"rms": [-13.7], "target": -12.0, "max_voices": 2, "min_interval": 0.08, "chance": 1.0, "pitch": 0.08,
		"start": 0.0, "end": 0.42,
	},
	# Foolsball charge running a soldier over. The file's crunch is done by ~1.1 s.
	"tackle_hit": {
		"files": ["hulk_charge/an_enormous_football_#1-1791564005298.mp3"],
		"rms": [-10.7], "target": -11.0, "max_voices": 2, "min_interval": 0.06, "chance": 1.0, "pitch": 0.08,
		"start": 0.0, "end": 1.1,
	},
	# A tough enemy (ninja, rocket soldier) taking a hit and living: a short grunt.
	"special_hurt": {
		"files": ["a_man_yelping_#1-1791320659837.mp3", "a_man_yelping_#4-1791320668270.mp3", "a_woman_yelping_#1-1791320682536.mp3", "a_woman_yelping_#2-1791320687537.mp3"],
		"rms": [-10.4, -17.2, -8.9, -11.1], "target": -16.0, "max_voices": 2, "min_interval": 0.1, "chance": 1.0, "pitch": 0.1,
	},
}

var _pool: Array[AudioStreamPlayer3D] = []
var _streams: Dictionary = {}  # group -> Array[AudioStream]
var _gains: Dictionary = {}  # group -> Array[float]
var _owner_group: Dictionary = {}  # player -> group it's playing
var _last_start: Dictionary = {}  # group -> msec
var _last_pick: Dictionary = {}  # group -> index
var _play_id: Dictionary = {}  # player -> count of plays, so a slice's stop timer never cuts a newer sound


func _ready() -> void:
	for group in groups:
		var g: Dictionary = groups[group]
		var streams: Array[AudioStream] = []
		var gains: Array[float] = []
		for i in g.files.size():
			streams.append(load(DIR + g.files[i]))
			# Level every clip to the group's target. Clamped: a near-silent file shouldn't get +30 dB.
			gains.append(clampf(g.target - g.rms[i], -18.0, 14.0))
		_streams[group] = streams
		_gains[group] = gains
	for i in voices:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.unit_size = unit_size
		p.panning_strength = panning
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.max_db = 6.0
		add_child(p)
		_pool.append(p)


## Plays one clip from `group` at `at`. volume_offset (dB) on top of the group's level,
## e.g. louder for a faster car. Returns false if a limit or the chance roll skipped it.
func play(group: String, at: Vector3, volume_offset: float = 0.0) -> bool:
	var g: Dictionary = groups.get(group, {})
	if g.is_empty():
		push_warning("Sfx: no group '%s'" % group)
		return false
	if randf() > g.chance:
		return false
	var now := Time.get_ticks_msec()
	if now - int(_last_start.get(group, -100000)) < int(g.min_interval * 1000.0):
		return false
	if _active(group) >= g.max_voices:
		return false
	var player := _free_player()
	var i := _pick(group)
	player.stream = _streams[group][i]
	player.volume_db = _gains[group][i] + volume_offset
	player.pitch_scale = g.get("pitch_base", 1.0) + randf_range(-g.pitch, g.pitch)
	player.global_position = at
	var start: float = g.get("start", 0.0)
	player.play(start)
	_owner_group[player] = group
	_last_start[group] = now
	var id: int = _play_id.get(player, 0) + 1
	_play_id[player] = id
	if g.has("end"):
		# Stop at the end of the slice (in real seconds: pitch changes playback speed).
		var real_length: float = (float(g.end) - start) / player.pitch_scale
		get_tree().create_timer(real_length, true, false, true).timeout.connect(func() -> void:
			if _play_id.get(player) == id:
				player.stop())
	return true


func _active(group: String) -> int:
	var n := 0
	for p in _pool:
		if p.playing and _owner_group.get(p) == group:
			n += 1
	return n


## A silent player, or the one that has been playing longest (its sound is mostly over).
func _free_player() -> AudioStreamPlayer3D:
	var oldest: AudioStreamPlayer3D = _pool[0]
	for p in _pool:
		if not p.playing:
			return p
		if p.get_playback_position() > oldest.get_playback_position():
			oldest = p
	return oldest


func _pick(group: String) -> int:
	var n: int = _streams[group].size()
	var i := randi() % n
	if n > 1 and i == _last_pick.get(group, -1):
		i = (i + 1 + randi() % (n - 1)) % n
	_last_pick[group] = i
	return i
