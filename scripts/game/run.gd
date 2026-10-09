class_name Run
extends Node
## Everything about the current run: how each soldier died, specials killed, style moves,
## waves cleared, augments taken, and the score. Lives in main.tscn as "Run", so a New Run
## (reloading the scene) starts it fresh. Main wires the gameplay signals into the record_*
## calls; the run summary screen reads summary().
##
## Score = kill points x wave multiplier, plus bonuses:
##   kill points  - per cause (style kills are worth more than plain punches)
##   bounty       - extra for special enemies (Human.bounty: rocket soldier, ninja)
##   style        - juggles (popping a body in midair) and wall splats
##   wave clear   - wave_clear_points x the wave number
## The wave multiplier (1 + wave_multiplier_step per wave after the first) makes late kills
## count more, so pushing deeper always pays.

signal score_changed(score: int)

@export_group("Kill points")
@export var points_smashed: int = 10
@export var points_stomped: int = 10
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
## Kill multiplier grows by this much each wave: wave 1 = x1.0, wave 11 = x2.0.
@export var wave_multiplier_step: float = 0.1

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
	kills += 1
	var cause := human.death_cause
	kills_by_cause[cause] = int(kills_by_cause.get(cause, 0)) + 1
	var points := points_for(cause)
	if human.bounty > 0:
		specials_killed[human.kind_name] = int(specials_killed.get(human.kind_name, 0)) + 1
		points += human.bounty
	_add(roundi(points * wave_multiplier()))


func record_juggles(count: int) -> void:
	if count <= 0:
		return
	juggles += count
	_add(roundi(juggle_points * count * wave_multiplier()))


func record_splat() -> void:
	splats += 1
	_add(roundi(splat_points * wave_multiplier()))


func record_wave_cleared(cleared_wave: int) -> void:
	waves_cleared = maxi(waves_cleared, cleared_wave)
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
		"won": won, "waves_cleared": waves_cleared, "kills": kills, "kills_by_cause": lines,
		"specials": specials_killed.duplicate(), "juggles": juggles, "splats": splats,
		"augments": augments.duplicate(), "score": score,
	}


func _add(points: int) -> void:
	score += points
	score_changed.emit(score)
