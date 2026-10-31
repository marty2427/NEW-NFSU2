class_name ChaseCamera
extends Camera3D
## Kamera za autem. Klavesa C prepina pohledy, Q = pohled dozadu.
## Pri vysoke rychlosti a nitru se rozsiri zorne pole, pri narazu se otrese.

const VIEWS := [
	{"name": "Daleko", "dist": 7.2, "height": 2.4, "look_height": 1.0},
	{"name": "Blizko", "dist": 5.2, "height": 1.7, "look_height": 0.9},
	{"name": "Kapota", "dist": -0.6, "height": 0.95, "look_height": 0.85},
]

@export var target: Car
var view_index := 0
var base_fov := 70.0

var _yaw := 0.0
var _shake := 0.0
var _fov := 70.0
var _initialized := false


func _ready() -> void:
	add_to_group("camera_shake")
	current = true
	near = 0.05
	far = 1500.0


func add_shake(amount: float) -> void:
	_shake = clampf(_shake + amount, 0.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("kamera"):
		view_index = (view_index + 1) % VIEWS.size()


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var view: Dictionary = VIEWS[view_index]
	var view_dist: float = view.dist
	var view_height: float = view.height
	var look_height: float = view.look_height
	var car_pos := target.global_position
	var car_fwd := -target.global_basis.z
	var car_yaw := atan2(-car_fwd.x, -car_fwd.z)

	if not _initialized:
		_yaw = car_yaw
		_initialized = true

	var hood := view_index == VIEWS.size() - 1
	# Kamera se natáčí za autem s mirnym zpozdenim (v driftu je videt bok auta)
	var follow_speed := 14.0 if hood else 4.5
	_yaw = lerp_angle(_yaw, car_yaw, 1.0 - exp(-follow_speed * delta))
	var yaw := _yaw
	if Input.is_action_pressed("pohled_vzad"):
		yaw += PI

	var rot := Basis(Vector3.UP, yaw)
	var speed := target.linear_velocity.length()
	var dist: float = view_dist + (clampf(speed / 60.0, 0.0, 1.0) * 1.2 if not hood else 0.0)
	var desired := car_pos + rot * Vector3(0, view_height, dist)
	if hood:
		desired = target.global_transform * Vector3(0, view_height - 0.15, -0.2)
		global_position = desired
	else:
		global_position = global_position.lerp(desired, 1.0 - exp(-12.0 * delta)) if global_position.distance_to(desired) < 20.0 else desired

	var look_at_pos := car_pos + Vector3.UP * look_height + rot * Vector3(0, 0, -4.0)
	if hood:
		look_at_pos = target.global_transform * Vector3(0, view_height - 0.2, -20.0)
	if global_position.distance_to(look_at_pos) > 0.01:
		look_at(look_at_pos, Vector3.UP)

	# Otres
	if _shake > 0.0:
		var s := _shake * _shake
		rotate_object_local(Vector3.RIGHT, randf_range(-1, 1) * 0.04 * s)
		rotate_object_local(Vector3.UP, randf_range(-1, 1) * 0.04 * s)
		h_offset = randf_range(-1, 1) * 0.15 * s
		v_offset = randf_range(-1, 1) * 0.15 * s
		_shake = maxf(0.0, _shake - delta * 1.5)
	else:
		h_offset = 0.0
		v_offset = 0.0

	# Zorne pole podle rychlosti a nitra
	var target_fov := base_fov + clampf(speed / 70.0, 0.0, 1.0) * 14.0
	if target.nitro_active:
		target_fov += 10.0
	_fov = lerpf(_fov, target_fov, 1.0 - exp(-4.0 * delta))
	fov = _fov
