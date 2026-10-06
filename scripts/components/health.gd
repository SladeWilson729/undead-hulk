class_name Health
extends Node
## Reusable health component. Attach as a child of anything that can take damage.
## The owner never edits HP directly; it calls take_damage() and listens to signals.
## WHY a separate node: the HUD, the enemies (step 3), and later pickups all talk
## to this one API instead of reaching into the Hulk script.

signal health_changed(current: int, maximum: int)
signal died

@export var max_health: int = 100

var current: int
## While true, take_damage() is ignored. Used for the ground pound's airborne window.
var invulnerable: bool = false
var is_dead: bool:
	get:
		return current <= 0


func _ready() -> void:
	current = max_health


func take_damage(amount: int) -> void:
	# Ignore hits after death so a swarm can't spam the died signal.
	if is_dead or invulnerable or amount <= 0:
		return
	current = maxi(current - amount, 0)
	health_changed.emit(current, max_health)
	if current == 0:
		died.emit()


func heal(amount: int) -> void:
	if is_dead or amount <= 0:
		return
	current = mini(current + amount, max_health)
	health_changed.emit(current, max_health)
