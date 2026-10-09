class_name AugmentSystem
extends Node
## The roguelike layer. After each cleared wave it rolls `offer_count` augments (weighted by
## rarity, never one you've maxed out), pauses the game for the pick screen, and applies the
## one you choose. Lives in main.tscn as "Augments"; Main wires it to the spawner and HUD.
##
## Stacks are counted per id. Effects that change a number (HP, punch targets, eat) are
## applied once when picked. Effects that change how soldiers look or die (Bobbleheads,
## Glitter Bomb) hook in through:
##   - human_spawned: dress each new soldier (big heads)
##   - on_kill(): called by Human.kill() for every death, before the body is spawned
##   - _physics_process: watches flying bodies for Glitter Bomb hits

signal picked(augment: Augment, stacks: int)

## Every augment in the game. Add new .tres files here.
const CATALOG: Array[Augment] = [
	preload("res://data/augments/bobbleheads.tres"),
	preload("res://data/augments/glitter_bomb.tres"),
	preload("res://data/augments/man_mosas.tres"),
	preload("res://data/augments/armor_up.tres"),
	preload("res://data/augments/me_strong.tres"),
	preload("res://data/augments/little_man.tres"),
	preload("res://data/augments/so_hungry.tres"),
	preload("res://data/augments/foolsball.tres"),
]

## Off = no pick screen between waves (older tests that clear waves turn it off).
@export var enabled: bool = true
@export var offer_count: int = 3
## Chance of rolling each rarity (Common, Rare, Legendary). A rarity with nothing left to
## offer is skipped and the roll goes to the others.
@export var rarity_weights: PackedFloat32Array = PackedFloat32Array([60.0, 30.0, 10.0])
## Seconds after a wave clears before the pick screen (the victory roar gets to start).
@export var pick_delay: float = 1.6

@export_group("Augment numbers")
@export var little_man_first_hp: int = 30
@export var little_man_extra_hp: int = 20
@export var armor_per_stack: int = 15
@export var me_strong_targets: int = 2
@export var so_hungry_heal: int = 5
@export var man_mosas_cooldown_cut: float = 2.0
@export var bobblehead_scale: float = 3.0
@export_range(0.0, 1.0) var head_pop_chance: float = 0.25
@export var head_pop_bonus: float = 0.5
@export var glitter_bonus_per_stack: float = 0.25
## A launched body has to be moving at least this fast (m/s) to glitter-bomb someone.
@export var glitter_min_speed: float = 5.0
## How close (m, center to center, flat) a flying body must pass to hit a soldier.
@export var glitter_hit_radius: float = 0.9

var hulk: Hulk
var run: Run
var deaths: DeathDirector
var stacks: Dictionary = {}  # id -> count
var picker: AugmentPicker  # The open pick screen, if any.


func _ready() -> void:
	add_to_group("kill_modifiers")


func count(id: StringName) -> int:
	return int(stacks.get(id, 0))


## Up to offer_count distinct augments that can still be taken, rarity-weighted.
func roll_offers() -> Array[Augment]:
	var pool: Array[Augment] = CATALOG.filter(func(a: Augment) -> bool: return not a.is_maxed(count(a.id)))
	var offers: Array[Augment] = []
	while offers.size() < offer_count and not pool.is_empty():
		var by_rarity: Dictionary = {}
		for a in pool:
			by_rarity[a.rarity] = by_rarity.get(a.rarity, []) + [a]
		var total := 0.0
		for r in by_rarity:
			total += rarity_weights[r]
		var roll := randf() * total
		var chosen_rarity: int = by_rarity.keys()[0]
		for r in by_rarity:
			roll -= rarity_weights[r]
			if roll <= 0.0:
				chosen_rarity = r
				break
		var pick: Augment = (by_rarity[chosen_rarity] as Array).pick_random()
		offers.append(pick)
		pool.erase(pick)
	return offers


## Opens the pick screen and pauses the game until a card is chosen.
func open_picker(parent: Node) -> AugmentPicker:
	if not enabled or picker or hulk == null or hulk.health.is_dead:
		return null
	var offers := roll_offers()
	if offers.is_empty():
		return null
	picker = AugmentPicker.new()
	parent.add_child(picker)
	picker.present(offers, self)
	picker.chosen.connect(func(a: Augment) -> void:
		take(a)
		picker = null
		get_tree().paused = false)
	get_tree().paused = true
	return picker


## Applies one stack of `augment`. Public so tests (and a future debug menu) can call it.
func take(augment: Augment) -> void:
	var before := count(augment.id)
	stacks[augment.id] = before + 1
	_apply(augment.id, before)
	if run:
		run.record_augment(augment.display_name if before == 0 else "%s x%d" % [augment.display_name, before + 1])
	picked.emit(augment, before + 1)


func _apply(id: StringName, before: int) -> void:
	match id:
		&"little_man":
			var hp := little_man_first_hp if before == 0 else little_man_extra_hp
			hulk.health.max_health += hp
			hulk.health.heal(hp)
			hulk.health.health_changed.emit(hulk.health.current, hulk.health.max_health)
		&"armor_up":
			# Takes effect right away, then refills at the start of every wave.
			hulk.health.shield = armor_per_stack * count(&"armor_up")
			hulk.health.health_changed.emit(hulk.health.current, hulk.health.max_health)
		&"me_strong":
			hulk.punch.max_targets += me_strong_targets
		&"so_hungry":
			hulk.eat.heal_amount += so_hungry_heal
		&"man_mosas":
			hulk.eat.cooldown = maxf(hulk.eat.cooldown - man_mosas_cooldown_cut, 0.5)
		&"foolsball":
			hulk.charge.unlock()
		&"bobbleheads":
			for node in get_tree().get_nodes_in_group("enemies"):
				dress(node as Human)


## New wave: Armor Up refills.
func on_wave_started() -> void:
	if count(&"armor_up") > 0:
		hulk.health.shield = armor_per_stack * count(&"armor_up")
		hulk.health.health_changed.emit(hulk.health.current, hulk.health.max_health)


## Every new soldier: Bobbleheads gives him the big head.
func dress(human: Human) -> void:
	if human == null or count(&"bobbleheads") == 0 or human.model == null:
		return
	HeadScale.attach(human.model, bobblehead_scale)


## Called by Human.kill() for every death, before the corpse is made.
func on_kill(human: Human, launch_velocity: Vector3) -> void:
	if count(&"bobbleheads") > 0 and human.death_cause == KillCause.SMASHED and randf() < head_pop_chance:
		_pop_head(human, launch_velocity)


func _pop_head(human: Human, launch_velocity: Vector3) -> void:
	var hs := HeadScale.attach(human.model, bobblehead_scale)
	if hs == null:
		return
	human.score_bonus += head_pop_bonus
	var at := hs.head_position()
	hs.factor = 0.001  # Gone.
	if deaths:
		deaths.pop_head(at, launch_velocity, human.gib_material)


## Glitter Bomb: a flying body that slams into a living soldier bursts into confetti and
## takes him with it.
func _physics_process(_delta: float) -> void:
	if count(&"glitter_bomb") == 0 or deaths == null:
		return
	var soldiers := get_tree().get_nodes_in_group("enemies")
	if soldiers.is_empty():
		return
	for corpse in deaths.airborne_corpses():
		var v: Vector3 = corpse.get_velocity()
		if v.length() < glitter_min_speed:
			continue
		var c: Vector3 = corpse.get_center()
		for node in soldiers:
			var human := node as Human
			if human == null or not human.is_in_group("enemies"):
				continue
			var p := human.global_position
			if c.y < p.y + 0.2 or c.y > p.y + 2.4:
				continue
			if Vector2(c.x - p.x, c.z - p.z).length() > glitter_hit_radius:
				continue
			glitter_bomb(corpse, human)
			break


## Public for tests. Bursts the corpse and the soldier it hit into confetti.
func glitter_bomb(corpse: Node, human: Human) -> void:
	var v: Vector3 = corpse.get_velocity()
	corpse.confetti()
	human.score_bonus += glitter_bonus_per_stack * count(&"glitter_bomb")
	human.force_confetti = true
	human.kill(v * 0.5 + Vector3.UP * 4.0, KillCause.GLITTER_BOMBED)
