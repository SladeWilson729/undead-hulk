class_name DeaconVoice
extends AudioStreamPlayer
## Deacon Mayhem's mouth. Will's lines, one channel (Voice bus), so he never talks over himself.
## The Finale, the truck and the Deacon on foot call say(kind).
##
## Priority: STORY lines (entrance, phase change, defeat, victory) cut anything and can't be
## cut. ATTACK (big attack) cuts chatter. CHATTER (taunts, getting hit, hitting the Hulk) only
## plays when he's quiet, and each kind has its own cooldown so he doesn't yap every hit.

enum Priority { CHATTER, ATTACK, STORY }

const DIR := "res://assets/sound/sound effects/deacon_mayhem_VO/"
## Every line, by kind. Loudness measured (ffmpeg mean_volume, dB) so each plays at `target_db`.
const LINES := {
	"entrance": [["deacon_enterance_1.mp3", -19.6], ["deacon_enterance_2.mp3", -19.5]],
	"taunt": [["deacon_taunt_1.mp3", -20.7], ["deacon_taunt_2.mp3", -19.7], ["deacon_taunt_3.mp3", -19.5],
		["deacon_taunt_4.mp3", -20.1], ["deacon_taunt_5.mp3", -17.8]],
	"getting_hit": [["deacon_getting_hit_1.mp3", -16.5], ["deacon_getting_hit_2.mp3", -19.7],
		["deacon_getting_hit_3.mp3", -17.1], ["deacon_getting_hit_4.mp3", -20.7]],
	"hit_hulk": [["deacon_hit_hulk_1.mp3", -20.6], ["deacon_hit_hulk_2.mp3", -20.2], ["deacon_hit_hulk_3.mp3", -19.8]],
	"big_attack": [["deacon_big_attack_1.mp3", -16.2], ["deacon_big_attack_2.mp3", -16.8], ["deacon_big_attack_3.mp3", -18.5]],
	"phase_change": [["deacon_phase_change_1.mp3", -21.3], ["deacon_phase_change_2.mp3", -21.4]],
	"defeat": [["deacon_defeat_1.mp3", -26.2], ["deacon_defeat_2.mp3", -21.2]],
	"victory": [["deacon_victory_1.mp3", -22.9], ["deacon_victory_2.mp3", -21.0]],
}
const PRIORITY := {
	"entrance": Priority.STORY, "phase_change": Priority.STORY, "defeat": Priority.STORY, "victory": Priority.STORY,
	"big_attack": Priority.ATTACK,
	"taunt": Priority.CHATTER, "getting_hit": Priority.CHATTER, "hit_hulk": Priority.CHATTER,
}

## Loudness every line is brought to (dB mean). The Hulk's grunts sit around here.
@export var target_db: float = -16.0
## Seconds before the same chatter kind can play again.
@export var chatter_cooldown: float = 5.0
## A taunt every this many seconds while he's quiet (0 = never on his own).
@export var taunt_every: float = 14.0

var _streams: Dictionary = {}  # kind -> Array[[AudioStream, gain_db]]
var _priority: int = -1
var _last_kind_ms: Dictionary = {}
var _last_pick: Dictionary = {}
var _taunt_timer: float = 0.0
## Off between fights (no taunts on his own).
var active: bool = false


func _ready() -> void:
	bus = &"Voice"
	process_mode = Node.PROCESS_MODE_ALWAYS
	finished.connect(func() -> void: _priority = -1)
	for kind in LINES:
		var list: Array = []
		for entry in LINES[kind]:
			var stream: AudioStream = load(DIR + entry[0])
			list.append([stream, target_db - float(entry[1])])
		_streams[kind] = list


func _process(delta: float) -> void:
	if not active or taunt_every <= 0.0 or get_tree().paused:
		return
	_taunt_timer += delta
	if _taunt_timer >= taunt_every:
		if say("taunt"):
			_taunt_timer = 0.0


## Plays a line of `kind` unless something more important is talking. Returns true if it did.
func say(kind: String) -> bool:
	if not _streams.has(kind):
		return false
	var p: int = PRIORITY[kind]
	if playing and p <= _priority and p != Priority.STORY:
		return false
	if playing and _priority == Priority.STORY:
		return false
	var now := Time.get_ticks_msec()
	if p == Priority.CHATTER and now - int(_last_kind_ms.get(kind, -100000)) < chatter_cooldown * 1000.0:
		return false
	var list: Array = _streams[kind]
	var i := randi() % list.size()
	if list.size() > 1 and i == int(_last_pick.get(kind, -1)):
		i = (i + 1) % list.size()
	_last_pick[kind] = i
	stream = list[i][0]
	volume_db = clampf(list[i][1], -6.0, 12.0)
	play()
	_priority = p
	_last_kind_ms[kind] = now
	if kind == "taunt":
		_taunt_timer = 0.0
	return true


## Seconds the current line has left (0 if quiet). The Finale waits on the entrance speech.
func time_left() -> float:
	if not playing or stream == null:
		return 0.0
	return maxf(stream.get_length() - get_playback_position(), 0.0)
