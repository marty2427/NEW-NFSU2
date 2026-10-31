class_name GevpCar
extends Vehicle
## Varianta rizeni "Easy Vehicle Physics" (prevzate, licence MIT, viz addons/gevp).
## Pouzije nase 3D modely aut a stejne rozhrani jako Car (HUD, kamera, ovladani),
## takze se da ve hre prepnout klavesou F7 a porovnat s nasim rizenim.

signal exploded(car: Node)
signal damage_changed(car: Node, damage: float)

const KMH := 3.6

var car_id := "octavia"
var is_player := true
var t: CarTuning
var model: CarModel

# --- Vstupy (stejne jako u Car) ---
var in_throttle := 0.0
var in_brake := 0.0
var in_steer := 0.0
var in_handbrake := false
var in_nitro := false

# --- Stav pro HUD a kameru ---
var nitro := 1.0
var nitro_active := false
var damage := 0.0
var destroyed := false
var drifting := false
var drift_angle := 0.0
var speed_kmh := 0.0
var rpm := 900.0
var gear := 1
var steer_angle := 0.0
var grounded_wheels := 4

var _rays: Array[Wheel] = []
var _reset_to: Variant = null
var _prev_velocity := Vector3.ZERO
var _pending_dv := 0.0
var _pending_pos := Vector3.ZERO
var _flames: Array[GPUParticles3D] = []
var _smoke: Array[GPUParticles3D] = []


## Postavi auto pred pridanim do sceny (Vehicle se inicializuje v _ready).
static func create(id: String, player: bool) -> GevpCar:
	var c := GevpCar.new()
	c.car_id = id
	c.is_player = player
	c._build()
	return c


func _build() -> void:
	name = "AutoHrace"
	t = CarTuning.load_car(car_id)
	add_to_group("cars")
	contact_monitor = true
	max_contacts_reported = 8
	can_sleep = false
	continuous_cd = true
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0

	model = CarModel.build(t.model, is_player, t.barva)
	add_child(model)
	var body := model.body_aabb
	var bottom := maxf(body.position.y, 0.22)
	var top := body.end.y
	var belt := bottom + (top - bottom) * 0.55
	_add_box(Vector3(body.size.x * 0.96, belt - bottom, body.size.z * 0.98), Vector3(body.get_center().x, (bottom + belt) * 0.5, body.get_center().z))
	_add_box(Vector3(body.size.x * 0.8, top - belt, body.size.z * 0.5), Vector3(body.get_center().x, (belt + top) * 0.5, body.get_center().z + body.size.z * 0.04))

	# --- Nastaveni podle arkadoveho auta z ukazek Easy Vehicle Physics ---
	stability_yaw_ground_multiplier = 6.0
	center_of_gravity_height_offset = -0.25
	front_damping_ratio = 0.6
	rear_damping_ratio = 0.6
	braking_grip_multiplier = 2.0
	# Povrchy: nase objekty maji skupiny "props", "debris", "cars" - vsechny jako silnice
	var keys := ["Road", "props", "debris", "cars", "street_lights", "world_env"]
	tire_stiffnesses = _surface(keys, 10.0)
	coefficient_of_friction = _surface(keys, 3.0)
	rolling_resistance = _surface(keys, 1.0)
	lateral_grip_assist = _surface(keys, 0.05)
	longitudinal_grip_ratio = _surface(keys, 0.5)

	# --- Hodnoty skutecneho auta ---
	vehicle_mass = t.hmotnost
	front_weight_distribution = 0.6 if t.pohon == "predni" else 0.52
	front_torque_split = 1.0 if t.pohon == "predni" else (0.4 if t.pohon == "vsechna" else 0.0)
	variable_torque_split = t.pohon == "vsechna"
	max_steering_angle = deg_to_rad(t.max_natoceni_kol)
	max_rpm = t.max_otacky
	idle_rpm = t.volnobezne_otacky
	var peak_omega := t.max_otacky * 0.8 * TAU / 60.0
	max_torque = t.vykon_kw * 1000.0 / peak_omega * 1.35
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(0.62, 1.0))
	curve.add_point(Vector2(1.0, 0.7))
	torque_curve = curve
	var n := maxi(t.pocet_rychlosti, 2)
	var ratios: Array[float] = []
	for i in n:
		ratios.append(3.4 * pow(0.78 / 3.4, float(i) / float(n - 1)))
	gear_ratios = ratios
	var r := model.wheel_radius
	front_tire_radius = r
	rear_tire_radius = r
	var v_top := t.max_rychlost / KMH
	final_drive = (t.max_otacky * TAU / 60.0) * r / (ratios[-1] * v_top * 1.03)
	frontal_area = 2.2
	coefficient_of_drag = clampf(2.0 * t.vykon_kw * 1000.0 * 0.8 / (1.225 * pow(v_top, 3.0) * frontal_area), 0.2, 0.6)

	# --- Kola: paprsky Easy Vehicle Physics + nase vizualni kola ---
	var slots := ["front_left_wheel", "front_right_wheel", "rear_left_wheel", "rear_right_wheel"]
	for i in mini(4, model.wheels.size()):
		var front := i < 2
		var spring := front_spring_length if front else rear_spring_length
		var ray := Wheel.new()
		ray.name = "Paprsek%d" % i
		ray.position = model.wheel_rest[i] + Vector3.UP * spring * 0.5
		var dummy := Node3D.new()
		ray.add_child(dummy)
		ray.wheel_node = dummy
		add_child(ray)
		set(slots[i], ray)
		_rays.append(ray)

	# Efekty: plameny nitra a kour pneumatik
	var rear := model.body_aabb.end.z - 0.02
	for x in [-0.4, 0.4]:
		var flame := FX.make_nitro_flame()
		model.add_child(flame)
		flame.position = Vector3(x, 0.3, rear)
		_flames.append(flame)
	for i in [2, 3]:
		var smoke := FX.make_tire_smoke()
		model.add_child(smoke)
		smoke.position = Vector3(model.wheel_rest[i].x, 0.15, model.wheel_rest[i].z + 0.2)
		_smoke.append(smoke)


func _surface(keys: Array, value: float) -> Dictionary:
	var d := {}
	for k in keys:
		d[k] = value
	return d


func _add_box(size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size.max(Vector3.ONE * 0.1)
	cs.shape = box
	cs.position = pos
	add_child(cs)


# ---------------------------------------------------------------------
#  Rozhrani kompatibilni s Car
# ---------------------------------------------------------------------

func get_forward_speed() -> float:
	return linear_velocity.dot(-global_basis.z)


func damage_ratio() -> float:
	return damage / 100.0


func gear_label() -> String:
	if gear < 0:
		return "R"
	return "N" if gear == 0 else str(gear)


func teleport(xform: Transform3D) -> void:
	_reset_to = xform


func flip_upright() -> void:
	var fwd := -global_basis.z
	fwd.y = 0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	teleport(Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), global_position + Vector3.UP * 1.0))


func apply_damage(amount: float) -> void:
	if destroyed or amount <= 0.0:
		return
	damage = minf(100.0, damage + amount)
	var d := damage_ratio()
	model.paint.albedo_color = t.barva.lerp(t.barva.darkened(0.5), d * 0.6)
	damage_changed.emit(self, damage)
	if damage >= 100.0:
		destroyed = true
		FX.spawn_explosion(get_parent(), global_position + Vector3.UP * 0.8, 9.0, 8000.0, [get_rid()])
		apply_central_impulse(Vector3.UP * mass * 6.0)
		model.paint.albedo_color = Color(0.04, 0.035, 0.03)
		exploded.emit(self)


# ---------------------------------------------------------------------
#  Fyzika: vstupy -> Easy Vehicle Physics, plus nitro a poskozeni
# ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if destroyed:
		in_throttle = 0.0
		in_brake = 0.0
		in_steer = 0.0
		in_nitro = false
	steering_input = -in_steer
	handbrake_input = 1.0 if in_handbrake else 0.0
	clutch_input = handbrake_input
	if current_gear == -1:
		throttle_input = in_brake
		brake_input = in_throttle
	else:
		throttle_input = in_throttle * in_throttle
		brake_input = in_brake
	super(delta)

	var fwd := get_forward_speed()
	speed_kmh = absf(fwd) * KMH
	rpm = motor_rpm
	gear = current_gear
	steer_angle = true_steering_amount
	grounded_wheels = get_wheel_contact_count()
	var lateral := linear_velocity.dot(global_basis.x)
	drift_angle = rad_to_deg(atan2(absf(lateral), maxf(absf(fwd), 0.1)))
	drifting = grounded_wheels >= 2 and speed_kmh > 30.0 and drift_angle > 12.0 and fwd > 0.0

	nitro_active = in_nitro and nitro > 0.0 and in_throttle > 0.1 and not destroyed
	if nitro_active:
		nitro = maxf(0.0, nitro - t.nitro_spotreba * delta)
		if grounded_wheels > 0:
			apply_central_force(-global_basis.z * mass * 4.5)
	else:
		nitro = minf(1.0, nitro + t.nitro_dobijeni * delta)
	if drifting:
		nitro = minf(1.0, nitro + t.nitro_za_drift * delta)
	for f in _flames:
		f.emitting = nitro_active
	for s in _smoke:
		s.emitting = drifting or (in_handbrake and speed_kmh > 20.0)
	model.tail_mat.emission_energy_multiplier = 9.0 if (in_brake > 0.1 or in_handbrake) and not destroyed else 2.0

	if _pending_dv > 0.0:
		var dv := _pending_dv
		_pending_dv = 0.0
		FX.spawn_sparks(get_parent(), _pending_pos, Vector3.UP, clampi(int(dv * 6.0), 8, 80))
		if is_player:
			for cam in get_tree().get_nodes_in_group("camera_shake"):
				cam.call("add_shake", clampf(dv / 25.0, 0.03, 0.8))
		apply_damage((dv - t.prah_poskozeni) * 0.6 / maxf(t.odolnost, 0.1))


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	super(state)
	if _reset_to != null:
		state.transform = _reset_to
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_prev_velocity = Vector3.ZERO
		_reset_to = null
		return
	var v := state.linear_velocity
	var dv := (v - _prev_velocity).length()
	_prev_velocity = v
	if state.get_contact_count() > 0 and dv > t.prah_poskozeni and dv > _pending_dv:
		_pending_dv = dv
		_pending_pos = state.get_contact_local_position(0)


## Vizualni kola sleduji paprsky Easy Vehicle Physics (pruziny, natoceni, otaceni).
func _process(delta: float) -> void:
	for i in _rays.size():
		var ray := _rays[i]
		var pivot: Node3D = model.wheels[i]
		pivot.position = (ray.transform * ray.wheel_node.transform).origin
		pivot.rotation.y = ray.rotation.y
		var spin: Node3D = model.wheel_spins[i]
		spin.rotate_object_local(Vector3.RIGHT, -ray.spin * delta)
