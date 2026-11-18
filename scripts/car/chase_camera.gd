class_name ChaseCamera
extends Camera3D
## Kamera za autem ve stylu poulicnich zavodu. Klavesa C prepina pohledy, Q = pohled dozadu.
## V rychlosti se kamera mirne vzdali a snizi, roste zorne pole, pri nitru se trese.

## Ve svahu se kamera naklani s autem (vyhlazene), takze z kopce je videt cesta pred autem.
const VIEWS := [
	{"name": "Blizko", "dist": 4.6, "height": 1.75, "look_height": 1.0, "ahead": 6.0},
	{"name": "Za autem", "dist": 5.6, "height": 2.3, "look_height": 1.0, "ahead": 7.0},
	{"name": "Vys", "dist": 6.2, "height": 3.3, "look_height": 0.9, "ahead": 8.0},
	{"name": "Zhora", "dist": 7.0, "height": 4.6, "look_height": 0.8, "ahead": 10.0},
	{"name": "Ptaci", "dist": 8.5, "height": 6.6, "look_height": 0.6, "ahead": 12.0},
	{"name": "Kapota", "dist": -0.4, "height": 1.25, "look_height": 1.15, "ahead": 25.0},
]

@export var target: RigidBody3D
var view_index := 2
var base_fov := 66.0

var _yaw := 0.0
var _shake := 0.0
var _fov := 66.0
var _lag := 0.0
var _prev_fwd_speed := 0.0
var _initialized := false
var _noise := FastNoiseLite.new()
var _time := 0.0
var _pitch := 0.0


func _ready() -> void:
	add_to_group("camera_shake")
	current = true
	near = 0.05
	far = 9000.0
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
		# Kamera se diva ve smeru jizdy (ne presne za zadkem auta): pri zataceni a ve smyku
		# je videt, jak se auto natoci - jizda pak pusobi zive.
		var flat_v := Vector3(target.linear_velocity.x, 0, target.linear_velocity.z)
		var aim_yaw := car_yaw
		if flat_v.length() > 6.0 and flat_v.dot(car_fwd) > 0.0:
			var vel_yaw := atan2(-flat_v.x, -flat_v.z)
			aim_yaw = lerp_angle(car_yaw, vel_yaw, 0.6)
		_yaw = lerp_angle(_yaw, aim_yaw, 1.0 - exp(-5.5 * delta))
		# Sklon silnice: z nakloneni auta (jen kdyz stoji na kolech), vyhlazene a omezene
		var slope := 0.0
		if absf(target.global_basis.y.y) > 0.7:
			var hf := Vector3(car_fwd.x, 0, car_fwd.z).length()
			slope = clampf(atan2(car_fwd.y, maxf(hf, 0.01)), -0.42, 0.42)
			# kamera se diva ve smeru auta; jede-li auto pozpatku, sklon se otoci
			if flat_v.length() > 3.0 and flat_v.dot(car_fwd) < 0.0:
				slope = -slope
		_pitch = lerpf(_pitch, slope, 1.0 - exp(-3.0 * delta))
		var yaw := _yaw
		if Input.is_action_pressed("pohled_vzad"):
			yaw += PI
		# Pri zrychleni kamera trochu zaostane, pri brzdeni se priblizi
		var fwd_speed := target.linear_velocity.dot(car_fwd)
		var accel := (fwd_speed - _prev_fwd_speed) / maxf(delta, 0.001)
		_prev_fwd_speed = fwd_speed
		_lag = lerpf(_lag, clampf(accel * 0.06, -0.45, 0.6), 1.0 - exp(-3.0 * delta))
		var rot := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, _pitch * (-1.0 if Input.is_action_pressed("pohled_vzad") else 1.0))
		var dist := view_dist + speed_f * 1.2 + _lag + (0.5 if target.get("nitro_active") else 0.0)
		var height := view_height - speed_f * 0.2 * view_height / 2.0
		var ahead: float = view.ahead
		var desired := car_pos + rot * Vector3(0, height, dist)
		# Kamera nesmi vlezt do budovy: paprsek od auta ke kamere
		var from := car_pos + Vector3.UP * 1.2
		var query := PhysicsRayQueryParameters3D.create(from, desired)
		query.exclude = [target.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and not (hit.collider is RigidBody3D):
			desired = (hit.position as Vector3) + (from - desired).normalized() * 0.35
		if global_position.distance_to(desired) > 25.0:
			global_position = desired
		else:
			global_position = global_position.lerp(desired, 1.0 - exp(-16.0 * delta))
		var look_at_pos := car_pos + rot * Vector3(0, look_height, -ahead)
		look_at(look_at_pos, rot.y.lerp(Vector3.UP, 0.5).normalized())

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
