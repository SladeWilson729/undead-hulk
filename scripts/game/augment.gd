class_name Augment
extends Resource
## One augment card: what the player sees on the pick screen. The effect itself lives in
## AugmentSystem, keyed by `id` (data here, behaviour there, so the cards can be retuned in
## the Inspector without touching code).
##
## Each augment is a .tres file in res://data/augments/. To add one: duplicate a file, give it
## a new id, then add its effect to AugmentSystem._apply() and its file to AugmentSystem.CATALOG.

enum Rarity { COMMON, RARE, LEGENDARY }

## Stable key the code uses. Never shown to the player.
@export var id: StringName
@export var display_name: String
@export var rarity: Rarity = Rarity.COMMON
## Shown under the name: Stat, Attack, Sustain, Quirky, Helper.
@export var category: String = "Stat"
@export_multiline var description: String
## How many times it can be taken. 1 = once. 0 = unlimited.
@export var max_stacks: int = 1


func rarity_name() -> String:
	return ["COMMON", "RARE", "LEGENDARY"][rarity]


func is_maxed(stacks: int) -> bool:
	return max_stacks > 0 and stacks >= max_stacks
