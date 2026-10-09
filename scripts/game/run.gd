class_name Run
extends Node
## Everything about the current run: how each soldier died, specials killed, style moves,
## waves cleared, augments taken, and the score. Lives in main.tscn as "Run", so a New Run
## (reloading the scene) starts it fresh. Main wires the gameplay signals into the record_*
## calls; the run summary screen reads summary().
##
## Score:
##   kill points  - per cause (style kills are worth more than plain punches), x wave multiplier
##   bounty       - extra for special enemies (Human.bounty: rocket soldier, ninja), x wave multiplier
##   style        - juggles (popping a body in midair) and wall splats, x wave multiplier
##   wave clear   - wave_clear_points x the wave number
## The wave multiplier (1 + wave_multiplier_step per wave after the first) makes late kills
## count more, so pushing deeper always pays.

signal score_changed(score: int)

@export_group("Kill points")
@export var points_smashed: int = 10
@export var points_stomped: int = 15
@export var points_eaten: int = 30
@export var points_crushed: int = 20
@export var points_buried: int = 25
@export var points_friendly_fire: int = 35
@export var points_fell: int = 15
@export var points_other: int = 10

@export_group("Bonuses")
## Popping a dead body in midair (punch or pound it while it's still flying).
@export var juggle_points: int = 40
## A launched body slamming into a wall hard enough to splat.
@export var splat_points: int = 15
## Paid per cleared wave, times the wave number (wave 5 = 5 x this).
@export var wave_clear_points: int = 100
## Kill (and bounty and style) multiplier grows by this much each wave:
## wave 1 = x1.0, wave 5 = x2.0, wave 14 = x4.25.
@export var wave_multiplier_step: float = 0.25

var score: int = 0
var kills: int = 0
var kills_by_cause: Dictionary = {}  # KillCause -> count
var specials_killed: Dictionary = {}  # Human.kind_name -> count (bounty enemies only)
var juggles: int = 0
var splats: int = 0
var waves_cleared: int = 0
## Augment ids taken this run, in order (filled in by the augment system).
var augments: Array[String] = []
## Current wave, for the multiplier. Main keeps it updated.
var wave: int = 1
var won: bool = false
var ended: bool = false
var best_score: int = 0
var new_best: bool = false
var save_ok: bool = true
var kill_points_total: int = 0
var bounty_total: int = 0
var style_total: int = 0
var wave_total: int = 0
var best_path: String = "user://run_best_v1.cfg"


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(best_path) == OK:
		best_score = maxi(0, int(config.get_value("run", "best", 0)))


func finish() -> void:
	if ended:
		return
	ended = true
	new_best = score > best_score
	if new_best:
		best_score = score
		var config := ConfigFile.new()
		config.set_value("run", "best", best_score)
		save_ok = config.save(best_path) == OK


func wave_multiplier() -> float:
	return 1.0 + wave_multiplier_step * maxi(wave - 1, 0)


func points_for(cause: int) -> int:
	match cause:
		KillCause.SMASHED: return points_smashed
		KillCause.STOMPED: return points_stomped
		KillCause.EATEN: return points_eaten
		KillCause.CRUSHED: return points_crushed
		KillCause.BURIED: return points_buried
		KillCause.FRIENDLY_FIRE: return points_friendly_fire
		KillCause.FELL: return points_fell
	return points_other


func record_kill(human: Human) -> void:
	if ended:
		return
	kills += 1
	var cause := human.death_cause
	kills_by_cause[cause] = int(kills_by_cause.get(cause, 0)) + 1
	var points := roundi(points_for(cause) * wave_multiplier())
	kill_points_total += points
	if human.bounty > 0:
		specials_killed[human.kind_name] = int(specials_killed.get(human.kind_name, 0)) + 1
		var bounty := roundi(human.bounty * wave_multiplier())
		bounty_total += bounty
		points += bounty
	_add(points)


func record_juggles(count: int) -> void:
	if ended or count <= 0:
		return
	juggles += count
	var points := roundi(juggle_points * count * wave_multiplier())
	style_total += points
	_add(points)


func record_splat() -> void:
	if ended:
		return
	splats += 1
	var points := roundi(splat_points * wave_multiplier())
	style_total += points
	_add(points)


func record_wave_cleared(cleared_wave: int) -> void:
	if ended or cleared_wave <= waves_cleared:
		return
	waves_cleared = cleared_wave
	wave_total += wave_clear_points * cleared_wave
	_add(wave_clear_points * cleared_wave)


func record_augment(id: String) -> void:
	augments.append(id)


## Everything the summary screen shows. kills_by_cause is a list of [label, count] in
## KillCause.LABELS order, skipping causes with no kills.
func summary() -> Dictionary:
	var lines: Array = []
	for cause in KillCause.LABELS:
		var n := int(kills_by_cause.get(cause, 0))
		if n > 0:
			lines.append([KillCause.label(cause), n])
	return {
		"wave": wave, "best": best_score, "new_best": new_best, "save_ok": save_ok,
		"kill_points": kill_points_total, "bounty_points": bounty_total,
		"style_points": style_total, "wave_points": wave_total,
		"won": won, "waves_cleared": waves_cleared, "kills": kills, "kills_by_cause": lines,
		"specials": specials_killed.duplicate(), "juggles": juggles, "splats": splats,
		"augments": augments.duplicate(), "score": score,
	}


func _add(points: int) -> void:
	score += points
	score_changed.emit(score)

