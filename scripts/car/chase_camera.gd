class_name ChaseCamera
extends Camera3D
## Kamera za autem ve stylu poulicnich zavodu. Klavesa C prepina pohledy, Q = pohled dozadu.
## V rychlosti se kamera mirne vzdali a snizi, roste zorne pole, pri nitru se trese.

const VIEWS := [
	{"name": "Za autem", "dist": 5.6, "height": 1.75, "look_height": 1.05},
	{"name": "Daleko", "dist": 7.8, "height": 2.6, "look_height": 1.2},
	{"name": "Kapota", "dist": -0.4, "height": 1.25, "look_height": 1.15},
]

@export var target: RigidBody3D  # Car nebo GevpCar
var view_index := 0
var base_fov := 66.0

var _yaw := 0.0
var _shake := 0.0
var _fov := 66.0
var _lag := 0.0
var _initialized := false
var _noise := FastNoiseLite.new()
var _time := 0.0


func _ready() -> void:
	add_to_group("camera_shake")
	current = true
	near = 0.05
	far = 2500.0
	_noise.frequency = 2.5


func add_shake(amount: float) -> void:
	_shake = clampf(_shake + amount, 0.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("kamera"):
		view_index = (view_index + 1) % VIEWS.size()


func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	_time += delta
	var view: Dictionary = VIEWS[view_index]
	var view_dist: float = view.dist
	var view_height: float = view.height
	var look_height: float = view.look_height
	var car_pos := target.global_position
	var car_fwd := -target.global_basis.z
	var car_yaw := atan2(-car_fwd.x, -car_fwd.z)
	var speed := target.linear_velocity.length()
	var speed_f := clampf(speed / 70.0, 0.0, 1.0)

	if not _initialized:
		_yaw = car_yaw
		_initialized = true

	var hood := view_index == VIEWS.size() - 1
	if hood:
		global_transform = target.global_transform * Transform3D(Basis(), Vector3(0, view_height, view_dist))
		look_at(target.global_transform * Vector3(0, look_height, -25.0), target.global_basis.y.lerp(Vector3.UP, 0.7))
	else:
		# Kamera se natáci za autem s mirnym zpozdenim (v driftu je videt bok auta)
		_yaw = lerp_angle(_yaw, car_yaw, 1.0 - exp(-4.0 * delta))
		var yaw := _yaw
		if Input.is_action_pressed("pohled_vzad"):
			yaw += PI
		# Pri zrychleni kamera trochu zaostane
		var accel := target.linear_velocity.dot(car_fwd)
		_lag = lerpf(_lag, clampf(accel * 0.012, 0.0, 0.9), 1.0 - exp(-2.0 * delta))
		var rot := Basis(Vector3.UP, yaw)
		var dist := view_dist + speed_f * 1.3 + _lag * 0.6
		var height := view_height - speed_f * 0.25
		var desired := car_pos + rot * Vector3(0, height, dist)
		if global_position.distance_to(desired) > 25.0:
			global_position = desired
		else:
			global_position = global_position.lerp(desired, 1.0 - exp(-14.0 * delta))
		var look_at_pos := car_pos + Vector3.UP * look_height + rot * Vector3(0, 0, -5.0)
		look_at(look_at_pos, Vector3.UP)

	# Otres: pri narazu + jemne chveni v rychlosti a pri nitru
	var shake := _shake * _shake + smoothstep(0.55, 1.0, speed_f) * 0.035
	if target.get("nitro_active"):
		shake += 0.06
	if shake > 0.001:
		var n1 := _noise.get_noise_2d(_time * 40.0, 0.0)
		var n2 := _noise.get_noise_2d(0.0, _time * 40.0)
		rotate_object_local(Vector3.RIGHT, n1 * 0.05 * shake)
		rotate_object_local(Vector3.UP, n2 * 0.05 * shake)
		h_offset = n2 * 0.25 * shake
		v_offset = n1 * 0.25 * shake
	else:
		h_offset = 0.0
		v_offset = 0.0
	_shake = maxf(0.0, _shake - delta * 1.5)

	# Zorne pole podle rychlosti a nitra
	var target_fov := base_fov + speed_f * 18.0
	if target.get("nitro_active"):
		target_fov += 9.0
	_fov = lerpf(_fov, target_fov, 1.0 - exp(-3.5 * delta))
	fov = _fov
