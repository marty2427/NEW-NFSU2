class_name PlayerController
extends Node
## Predava vstupy z klavesnice / gamepadu autu (rodic tohoto uzlu).
## Soupere v dalsich fazich ovlada misto toho AI.

@onready var car: Car = get_parent()


func _physics_process(_delta: float) -> void:
	if car == null:
		return
	car.in_throttle = Input.get_action_strength("plyn")
	car.in_brake = Input.get_action_strength("brzda")
	car.in_steer = Input.get_axis("vlevo", "vpravo")
	car.in_handbrake = Input.is_action_pressed("rucni_brzda")
	car.in_nitro = Input.is_action_pressed("nitro")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("reset_auta") and car and not car.destroyed:
		car.flip_upright()
