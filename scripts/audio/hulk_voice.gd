class_name HulkVoice
extends AudioStreamPlayer
## The Hulk's voice. One channel, so lines never stack into a choir of Hulks.
## Child of the Hulk; listens to the attack nodes' signals and picks a line.
##
## Priority: a line can cut off a line of LOWER priority.
##   punch (0) < pound, lift, throw, eat (1) < victory (2)
## Action lines can also cut off an earlier ACTION line: the newest move wins, so a throw
## right after the lift says the throw line instead of finishing the lift line.
## Punch lines are also rationed (punch_chance) and never interrupt anything, so holding
## the punch button gives an occasional grunt instead of a machine gun of "Hup!"s.
##
## Every file has 35-255 ms of silence before the voice starts (measured, see LEAD_TRIM).
## We start playback past it, so a grunt lands on the click instead of a beat late.

enum Priority { PUNCH, ACTION, VICTORY }

const SFX := "res://assets/sound/sound effects/"
## Seconds of lead-in silence per file, measured: first 10 ms window within 30 dB of the
## clip's peak, minus a 15 ms safety margin. Re-measure if a file is regenerated.
const LEAD_TRIM := {
	"ground-pound-1.mp3": 0.105, "ground-pound-2.mp3": 0.075, "ground-pound-3.mp3": 0.195,
	"lift-car-1.mp3": 0.105, "lift-car-2.mp3": 0.195, "lift-car-3.mp3": 0.055,
	"punch-1.mp3": 0.095, "punch-2.mp3": 0.065, "punch-3.mp3": 0.045, "punch-4.mp3": 0.145,
	"punch-5.mp3": 0.155, "punch-6.mp3": 0.175, "punch-7.mp3": 0.035, "punch-8.mp3": 0.125,
	"victory-1.mp3": 0.145, "victory-2.mp3": 0.175, "victory-3.mp3": 0.255,
	"throw_1.mp3": 0.125, "throw_2.mp3": 0.115, "throw_3.mp3": 0.115,
	"eat_1.mp3": 0.055, "eat_2.mp3": 0.105, "eat_3.mp3": 0.095,
}
## Used for any file not in LEAD_TRIM (a new line you add in the Inspector).
const DEFAULT_LEAD_TRIM := 0.08

@export_group("Lines")
@export var punch_lines: Array[AudioStream] = [
	load(SFX + "punch-1.mp3"), load(SFX + "punch-2.mp3"), load(SFX + "punch-3.mp3"), load(SFX + "punch-4.mp3"),
	load(SFX + "punch-5.mp3"), load(SFX + "punch-6.mp3"), load(SFX + "punch-7.mp3"), load(SFX + "punch-8.mp3"),
]
@export var pound_lines: Array[AudioStream] = [
	load(SFX + "ground-pound-1.mp3"), load(SFX + "ground-pound-2.mp3"), load(SFX + "ground-pound-3.mp3"),
]
@export var lift_lines: Array[AudioStream] = [
	load(SFX + "lift-car-1.mp3"), load(SFX + "lift-car-2.mp3"), load(SFX + "lift-car-3.mp3"),
]
## Play on the throw click.
@export var throw_lines: Array[AudioStream] = [
	load(SFX + "throw_1.mp3"), load(SFX + "throw_2.mp3"), load(SFX + "throw_3.mp3"),
]
## Play when he grabs a soldier to eat.
@export var eat_lines: Array[AudioStream] = [
	load(SFX + "eat_1.mp3"), load(SFX + "eat_2.mp3"), load(SFX + "eat_3.mp3"),
]
@export var victory_lines: Array[AudioStream] = [
	load(SFX + "victory-1.mp3"), load(SFX + "victory-2.mp3"), load(SFX + "victory-3.mp3"),
]

@export_group("Feel")
## Chance (0-1) that a punch gets a voice line. Only when he isn't already talking.
@export_range(0.0, 1.0) var punch_chance: float = 0.35
## Random pitch spread per line (0.05 = +/-5%). Keeps repeats from sounding canned.
@export_range(0.0, 0.2) var pitch_variance: float = 0.05

var _priority: int = -1
var _last: Dictionary = {}  # Array id -> last stream played from it, so no back-to-back repeats.

@onready var hulk: Hulk = get_parent()


func _ready() -> void:
	bus = &"Voice"
	finished.connect(func() -> void: _priority = -1)
	hulk.get_node("PunchAttack").swung.connect(_on_swung)
	hulk.get_node("GroundPound").leaped.connect(func() -> void: say(pound_lines, Priority.ACTION))
	hulk.get_node("CarryThrow").lifted.connect(func() -> void: say(lift_lines, Priority.ACTION))
	hulk.get_node("CarryThrow").throw_started.connect(func() -> void: say(throw_lines, Priority.ACTION))
	hulk.get_node("EatSoldier").grabbed.connect(func() -> void: say(eat_lines, Priority.ACTION))
	hulk.get_node("Animator").victory_started.connect(func() -> void: say(victory_lines, Priority.VICTORY))
	# Dead men tell no jokes.
	hulk.get_node("Health").died.connect(func() -> void:
		stop()
		_priority = -1)


func _on_swung() -> void:
	if playing or randf() > punch_chance:
		return
	say(punch_lines, Priority.PUNCH)


## Plays a random line from `lines` unless something more important is talking.
## Returns true if it played.
func say(lines: Array[AudioStream], priority: int) -> bool:
	if lines.is_empty():
		return false
	if playing and (priority < _priority or (priority == _priority and priority != Priority.ACTION)):
		return false
	var line := _pick(lines)
	stream = line
	pitch_scale = 1.0 + randf_range(-pitch_variance, pitch_variance)
	play(LEAD_TRIM.get(line.resource_path.get_file(), DEFAULT_LEAD_TRIM))
	_priority = priority
	return true


## Random line, never the same one twice in a row from the same list.
func _pick(lines: Array[AudioStream]) -> AudioStream:
	var key := hash(lines)
	var previous: AudioStream = _last.get(key)
	var choice: AudioStream = lines.pick_random()
	if lines.size() > 1:
		while choice == previous:
			choice = lines.pick_random()
	_last[key] = choice
	return choice
