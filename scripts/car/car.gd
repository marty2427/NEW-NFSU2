class_name Car
extends RigidBody3D
## Arkadove auto: odpruzeni pres paprsky (raycast), model pneumatik se smykem,
## motor s automatickou prevodovkou, drift, nitro, poskozeni a vybuch.
## Vsechny hodnoty jizdy jsou v tuning/auta.cfg, 3D modely v data/modely_aut.cfg.

signal exploded(car: Car)
signal impact(car: Car, strength: float, position: Vector3)
signal damage_changed(car: Car, damage: float)
signal gear_changed(car: Car, gear: int)

const GRAVITY := 9.8
const KMH := 3.6
const DRIVETRAIN_EFFICIENCY := 0.85
const ROLLING_RESISTANCE := 3.0  # N na (m/s) na kolo
const TRACTION := 1.5             # arkadova trakce pri zrychleni (nezavisi na mokru)

@export var car_id := "octavia"
@export var is_player := true

var t: CarTuning
var model: CarModel

# --- Vstupy (hrac nebo pozdeji AI) ---
var in_throttle := 0.0
var in_brake := 0.0
var in_steer := 0.0
var in_handbrake := false
var in_nitro := false

# --- Stav ---
var steer_angle := 0.0
var nitro := 1.0
var nitro_active := false
var damage := 0.0          # 0 - 100
var destroyed := false
var drifting := false
var drift_angle := 0.0     # stupne
var speed_kmh := 0.0
var grounded_wheels := 0
var gear := 1              # -1 = zpatecka, 1..n
var rpm := 900.0
var wheelspin := false

var _wheels: Array[Dictionary] = []
var _gear_top_speed: Array[float] = []
var _drag := 0.3
var _shift_timer := 0.0
var _prev_velocity := Vector3.ZERO
var _reset_to: Variant = null      # Transform3D, kdyz se ma auto presunout
var _damage_pull := 0.0            # poskozene auto tahne do strany
var _smoke: GPUParticles3D
var _heavy_smoke: GPUParticles3D
var _fire: GPUParticles3D
var _last_impact_time := 0.0
var _pending_impact: Dictionary = {}
var _upside_down_time := 0.0
var _tire_smoke: Array[GPUParticles3D] = []
var _nitro_flames: Array[GPUParticles3D] = []
var _steer_input := 0.0            # vyhlazeny vstup volantu
var _wheelbase := 2.7
var _yaw_inertia := 2500.0
var _drift_mode := false
var _drift_idle := 0.0
var _impact_timer := 0.0


func _ready() -> void:
	add_to_group("cars")
	contact_monitor = true
	max_contacts_reported = 8
	can_sleep = false
	continuous_cd = true
	# Vychozi utlum Godotu by auto brzdil (odpor vzduchu pocitame sami)
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.6
	setup(car_id)


## Postavi auto podle zadaneho id (sekce v auta.cfg). Lze volat znovu pro zmenu auta.
func setup(new_id: String) -> void:
	car_id = new_id
	t = CarTuning.load_car(car_id)
	for child in get_children():
		if String(child.name) in ["Vzhled", "Kolize", "KolizeKabina"]:
			remove_child(child)
			child.queue_free()
	_smoke = null
	_heavy_smoke = null
	_fire = null

	mass = t.hmotnost
	model = CarModel.build(t.model, is_player, t.barva)
	add_child(model)

	# Kolize: spodni cast karoserie + uzsi kabina
	var body := model.body_aabb
	var bottom := maxf(body.position.y, 0.22)
	var top := body.end.y
	var belt := bottom + (top - bottom) * 0.55
	_add_box("Kolize", Vector3(body.size.x * 0.96, belt - bottom, body.size.z * 0.98), Vector3(body.get_center().x, (bottom + belt) * 0.5, body.get_center().z))
	_add_box("KolizeKabina", Vector3(body.size.x * 0.8, top - belt, body.size.z * 0.5), Vector3(body.get_center().x, (belt + top) * 0.5, body.get_center().z + body.size.z * 0.04))

	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, t.vyska_teziste, body.get_center().z)

	var physics_material := PhysicsMaterial.new()
	physics_material.friction = 0.35
	physics_material.bounce = 0.15
	physics_material_override = physics_material

	_wheels.clear()
	for i in model.wheels.size():
		var front := i < 2
		var driven := (t.pohon == "vsechna") or (t.pohon == "predni" and front) or (t.pohon == "zadni" and not front)
		var rest: Vector3 = model.wheel_rest[i]
		_wheels.append({
			"mount": rest + Vector3.UP * (t.zdvih_pruziny - t.propad_podvozku),
			"rest": rest,
			"front": front,
			"driven": driven,
			"node": model.wheels[i],
			"spin": model.wheel_spins[i],
			"compression": 0.0,
			"grounded": false,
			"load": 0.0,
			"slip": 0.0,
		})
	_wheelbase = maxf(absf(model.wheel_rest[0].z - model.wheel_rest[2].z), 1.5) if model.wheel_rest.size() >= 4 else 2.7
	_yaw_inertia = mass * (body.size.z * body.size.z + body.size.x * body.size.x) / 12.0
	_drift_mode = false
	_setup_drivetrain()
	_setup_effects()
	repair()


## Kour od zadnich kol a plameny z vyfuku pri nitru.
func _setup_effects() -> void:
	_tire_smoke.clear()
	_nitro_flames.clear()
	for i in [2, 3]:
		var smoke := FX.make_tire_smoke()
		model.add_child(smoke)
		smoke.position = Vector3(model.wheel_rest[i].x, 0.15, model.wheel_rest[i].z + 0.2)
		_tire_smoke.append(smoke)
	var rear := model.body_aabb.end.z - 0.02
	for x in [-0.4, 0.4]:
		var flame := FX.make_nitro_flame()
		model.add_child(flame)
		flame.position = Vector3(x, 0.3, rear)
		_nitro_flames.append(flame)


func _add_box(node_name: String, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	cs.name = node_name
	var box := BoxShape3D.new()
	box.size = size.max(Vector3.ONE * 0.1)
	cs.shape = box
	cs.position = pos
	add_child(cs)


## Prevodovka a odpor vzduchu se dopocitaji z vykonu a maximalni rychlosti.
func _setup_drivetrain() -> void:
	var v_top := t.max_rychlost / KMH
	var n := maxi(t.pocet_rychlosti, 1)
	var top_gear_v := v_top * 1.04
	var q := pow(top_gear_v / (v_top * 0.27), 1.0 / maxf(n - 1, 1))
	_gear_top_speed.clear()
	for i in n:
		_gear_top_speed.append(top_gear_v / pow(q, n - 1 - i))
	var power := t.vykon_kw * 1000.0 * DRIVETRAIN_EFFICIENCY * _power_curve(1.0 / 1.04)
	_drag = maxf((power - ROLLING_RESISTANCE * 4.0 * v_top * v_top) / pow(v_top, 3.0), 0.05)
	gear = 1
	rpm = t.volnobezne_otacky


## Prubeh vykonu motoru podle otacek (0-1 = podil omezovace).
func _power_curve(x: float) -> float:
	return clampf(1.0 - pow((x - 0.82) / 0.7, 2.0), 0.28, 1.0)


func repair() -> void:
	damage = 0.0
	destroyed = false
	nitro = 1.0
	_damage_pull = 0.0
	if model and model.paint:
		model.paint.albedo_color = t.barva
		model.paint.metallic = 0.35
		model.paint.roughness = 0.3
		model.paint.clearcoat = 1.0
	if model:
		for beam in model.beams:
			beam.visible = true
	_update_damage_effects()
	damage_changed.emit(self, damage)


## Bezpecne presune auto (napr. respawn nebo otoceni na kola).
func teleport(xform: Transform3D) -> void:
	_reset_to = xform


## Postavi auto zpet na kola na aktualnim miste.
func flip_upright() -> void:
	var fwd := -global_basis.z
	fwd.y = 0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	teleport(Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), global_position + Vector3.UP * 1.0))


func get_forward_speed() -> float:
	return linear_velocity.dot(-global_basis.z)


func damage_ratio() -> float:
	return damage / 100.0


func gear_label() -> String:
	return "R" if gear < 0 else str(gear)


# ---------------------------------------------------------------------
#  Fyzika
# ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if t == null or model == null:
		return
	if not _pending_impact.is_empty():
		var imp := _pending_impact
		_pending_impact = {}
		_on_impact(imp.dv, imp.pos, imp.normal, imp.collider)
	if destroyed:
		in_throttle = 0.0
		in_brake = 0.0
		in_steer = 0.0
		in_nitro = false
		in_handbrake = true

	var bas := global_basis
	var up := bas.y
	var speed := linear_velocity.length()
	var fwd_speed := get_forward_speed()
	speed_kmh = absf(fwd_speed) * KMH
	var dmg := damage_ratio()

	# --- Zataceni ---
	# Vstup se vyhladi (klavesnice), pri pusteni se volant vraci rychleji
	var steer_rate := t.rychlost_volantu * (1.8 if absf(in_steer) < absf(_steer_input) else 1.0)
	_steer_input = move_toward(_steer_input, in_steer, steer_rate * delta)
	# Natoceni kol podle rychlosti: v kazde rychlosti auto zataci tak ostre,
	# jak to pneumatiky unesou (predni kola neprejdou do smyku = auto zataci).
	var v_abs := absf(fwd_speed)
	var grip_acc := minf(t.prilnavost_predni, t.prilnavost_zadni) * t.mokra_silnice * GRAVITY * (1.0 - dmg * 0.2)
	var k_lock := tan(deg_to_rad(t.max_natoceni_kol)) / _wheelbase
	var k_grip := grip_acc * t.pomoc_zataceni / maxf(v_abs * v_abs, 0.01)
	var k_cmd := -_steer_input * minf(k_lock, k_grip)   # zakriveni drahy (1/m), + = doleva
	var target_steer := atan(k_cmd * _wheelbase) + _damage_pull * dmg
	steer_angle = move_toward(steer_angle, target_steer, 5.0 * delta)
	_impact_timer = maxf(0.0, _impact_timer - delta)

	# --- Nitro ---
	nitro_active = in_nitro and nitro > 0.0 and in_throttle > 0.1 and not destroyed
	if nitro_active:
		nitro = maxf(0.0, nitro - t.nitro_spotreba * delta)
	else:
		nitro = minf(1.0, nitro + t.nitro_dobijeni * delta)

	# --- Motor a prevodovka ---
	var drive_force := _update_drivetrain(delta, fwd_speed, dmg)
	var braking := 0.0
	if gear > 0 and in_brake > 0.0 and fwd_speed > 0.5:
		braking = in_brake
	elif gear < 0 and in_throttle > 0.0 and fwd_speed < -0.5:
		braking = in_throttle

	# --- Kola ---
	var space := get_world_3d().direct_space_state
	var ray_len := t.zdvih_pruziny + model.wheel_radius
	var mass_per_wheel := mass / 4.0
	var spring_k := mass_per_wheel * GRAVITY / maxf(t.propad_podvozku, 0.02)
	var damper := 2.0 * sqrt(spring_k * mass_per_wheel) * t.tlumeni
	var driven_count := 0
	for w in _wheels:
		if w.driven:
			driven_count += 1
	grounded_wheels = 0
	wheelspin = false
	var rear_slip := 0.0
	var exclude: Array[RID] = [get_rid()]

	for w in _wheels:
		var mount: Vector3 = global_transform * (w.mount as Vector3)
		var query := PhysicsRayQueryParameters3D.create(mount, mount - up * ray_len)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		var wheel_node: Node3D = w.node
		var mount_y: float = (w.mount as Vector3).y
		if hit.is_empty():
			w.grounded = false
			w.compression = 0.0
			w.load = 0.0
			wheel_node.position.y = lerpf(wheel_node.position.y, mount_y - t.zdvih_pruziny, 0.3)
			continue
		w.grounded = true
		grounded_wheels += 1
		var hit_pos: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		var dist := mount.distance_to(hit_pos)
		var compression := ray_len - dist
		var comp_vel := (compression - float(w.compression)) / delta
		w.compression = compression
		wheel_node.position.y = mount_y - (dist - model.wheel_radius)

		# Pruzina + tlumic
		var spring_force := clampf(spring_k * compression + damper * comp_vel, 0.0, mass * GRAVITY * 3.0)
		w.load = spring_force
		var offset := mount - global_position
		apply_force(normal * spring_force, offset)

		# Smer kola
		var wheel_fwd := -bas.z
		if w.front:
			wheel_fwd = wheel_fwd.rotated(up, steer_angle)
		wheel_fwd = (wheel_fwd - normal * wheel_fwd.dot(normal)).normalized()
		var wheel_right := wheel_fwd.cross(normal).normalized()
		var point_vel := linear_velocity + angular_velocity.cross(offset)
		var v_fwd := point_vel.dot(wheel_fwd)
		var v_lat := point_vel.dot(wheel_right)

		# Pneumatika: prilnavost klesa plynule se smykem (zadny skok = zadne "zaseknuti" v driftu)
		var slip := rad_to_deg(atan2(absf(v_lat), maxf(absf(v_fwd), 1.0)))
		w.slip = slip
		var mu := (t.prilnavost_predni if w.front else t.prilnavost_zadni) * t.mokra_silnice * (1.0 - dmg * 0.2)
		var peak := t.uhel_max_prilnavosti
		mu *= lerpf(1.0, t.prilnavost_ve_smyku, smoothstep(peak, peak * 3.5, slip))
		if not w.front:
			rear_slip = maxf(rear_slip, slip)
			if in_handbrake:
				mu *= t.prilnavost_rucni_brzda
			elif _drift_mode:
				mu *= t.prilnavost_v_driftu
		var max_force := mu * spring_force

		# Podelne sily: motor, brzdy, valivy odpor
		var long_force := -v_fwd * ROLLING_RESISTANCE
		if w.driven and drive_force != 0.0:
			var demand := drive_force / maxi(driven_count, 1)
			var cap := spring_force * TRACTION * (1.0 - dmg * 0.2)
			if _drift_mode and not w.front:
				cap *= 0.55  # v driftu zadni kola neroztoci auto
			if absf(demand) > cap:
				wheelspin = true
			long_force += clampf(demand, -cap, cap)
		elif w.driven and in_throttle < 0.05 and gear > 0:
			long_force -= signf(v_fwd) * minf(mass * 0.5 / maxi(driven_count, 1), absf(v_fwd) * mass_per_wheel / delta)  # brzdeni motorem
		if braking > 0.0:
			var bias := 0.6 if w.front else 0.4
			long_force -= signf(v_fwd) * minf(t.sila_brzd * 0.5 * bias * braking, absf(v_fwd) * mass_per_wheel / delta)
		if in_handbrake and not w.front:
			long_force -= signf(v_fwd) * minf(t.sila_rucni_brzdy * 0.5, absf(v_fwd) * mass_per_wheel / delta)

		# Kruh prilnavosti: co pneumatika vyuzije na zrychleni, chybi v zatacce
		var lat_cap := sqrt(maxf(0.0, max_force * max_force - pow(long_force * 0.3, 2.0)))
		var lat_force := clampf(-v_lat * mass_per_wheel / delta * 0.9, -lat_cap, lat_cap)
		apply_force(wheel_right * lat_force + wheel_fwd * long_force, offset)

		# Otaceni kola (vzhled)
		var spin: Node3D = w.spin
		var spin_speed := v_fwd / model.wheel_radius
		if in_handbrake and not w.front:
			spin_speed = 0.0
		elif w.driven and wheelspin:
			spin_speed *= 1.6
		spin.rotate_object_local(Vector3.RIGHT, -spin_speed * delta)
		if w.front:
			wheel_node.rotation.y = steer_angle

	# --- Drift ---
	var lateral_speed := linear_velocity.dot(bas.x)
	drift_angle = rad_to_deg(atan2(absf(lateral_speed), maxf(absf(fwd_speed), 0.1)))
	_update_drift_mode(delta, v_abs, fwd_speed)
	drifting = _drift_mode and drift_angle > 10.0
	if drifting:
		nitro = minf(1.0, nitro + t.nitro_za_drift * delta)

	if grounded_wheels >= 2 and not destroyed:
		var v_flat := linear_velocity - up * linear_velocity.dot(up)
		var heading := (-bas.z - up * (-bas.z).dot(up)).normalized()
		var right_flat := heading.cross(up).normalized()
		var yaw_rate := angular_velocity.dot(up)
		# Po narazu se pomoc na chvili vypne, at je naraz poznat
		var assist_scale := (1.0 - dmg * 0.3) * (0.15 if _impact_timer > 0.0 else 1.0)
		var target_yaw: float
		var drift_side := signf(heading.cross(v_flat.normalized()).dot(up)) if v_flat.length() > 1.0 else 0.0
		if _drift_mode:
			# V driftu volant ovlada natoceni auta (protismyk srovnava)
			var steer_yaw := -_steer_input * t.otaceni_v_driftu * clampf(v_abs / 12.0, 0.0, 1.0)
			# Kdyz volant toci auto dal do driftu, u maximalniho uhlu se otaceni utlumi
			if signf(steer_yaw) == -drift_side:
				steer_yaw *= 1.0 - smoothstep(t.max_uhel_driftu * 0.6, t.max_uhel_driftu, drift_angle)
			target_yaw = steer_yaw
			# Smer jizdy se postupne stoci za predkem auta, rychlost se skoro neztrati
			var keep := 1.0 if in_throttle > 0.1 else 0.6
			apply_central_force((heading * v_flat.length() - v_flat) * mass * 1.4 * t.pomoc_driftu * keep)
			# Pojistka proti roztoceni
			if drift_angle > t.max_uhel_driftu * 0.85 and v_flat.length() > 1.0:
				target_yaw += drift_side * deg_to_rad(drift_angle - t.max_uhel_driftu * 0.85) * 10.0
		else:
			# Auto se otaci presne tak, jak zataci kola (zadne bezduvodne smyky)
			target_yaw = fwd_speed * k_cmd
			# Po smyku nebo narazu se auto samo srovna do smeru jizdy
			if drift_angle > 20.0 and drift_angle < 120.0 and v_flat.length() > 3.0:
				target_yaw += drift_side * deg_to_rad(drift_angle - 20.0) * 3.0
			# Auto jede tam, kam miri (arkadova prilnavost)
			var lat := v_flat.dot(right_flat)
			var align := clampf(-lat * mass * 4.0 * t.stabilita, -mass * grip_acc * 0.6, mass * grip_acc * 0.6)
			apply_central_force(right_flat * align * assist_scale)
		var yaw_torque := (target_yaw - yaw_rate) * _yaw_inertia * 7.0 * t.pomoc_zataceni
		yaw_torque = clampf(yaw_torque, -_yaw_inertia * 14.0, _yaw_inertia * 14.0)
		apply_torque(up * yaw_torque * assist_scale)
		# Pritlak
		apply_central_force(-up * speed * speed * t.pritlak * mass / 1000.0)
	elif grounded_wheels > 0:
		apply_central_force(-up * speed * speed * t.pritlak * mass / 1000.0)
	else:
		# Ve vzduchu: auto se pomalu vyrovnava
		var level_axis := up.cross(Vector3.UP)
		apply_torque(level_axis * mass * 3.0 - angular_velocity * mass * 0.3)

	# Odpor vzduchu (spocitany tak, aby auto jelo svou max. rychlost)
	apply_central_force(-linear_velocity * speed * _drag)

	# Auto na strese nebo na boku se samo postavi na kola
	if up.y < 0.35 and speed < 2.0 and not destroyed:
		_upside_down_time += delta
		if _upside_down_time > 2.5:
			_upside_down_time = 0.0
			flip_upright()
	else:
		_upside_down_time = 0.0

	_update_lights()


## Drift zacina rucni brzdou v zatacce, trva dokud auto jede bokem a hrac drzi plyn.
func _update_drift_mode(delta: float, v_abs: float, fwd_speed: float) -> void:
	var v_flat := Vector2(linear_velocity.x, linear_velocity.z).length()
	if not _drift_mode:
		if in_handbrake and v_abs > 8.0 and absf(_steer_input) > 0.2 and fwd_speed > 0.0 and grounded_wheels >= 2:
			_drift_mode = true
			_drift_idle = 0.0
		return
	var active := in_throttle > 0.1 or in_handbrake
	_drift_idle = 0.0 if active else _drift_idle + delta
	if drift_angle < 5.0 or v_flat < 4.0 or drift_angle > 110.0 or _drift_idle > 0.5 or grounded_wheels == 0:
		_drift_mode = false


## Vrati hnaci silu motoru (N) a aktualizuje otacky a rychlostni stupen.
func _update_drivetrain(delta: float, fwd_speed: float, dmg: float) -> float:
	var n := _gear_top_speed.size()
	_shift_timer = maxf(0.0, _shift_timer - delta)
	# Zpatecka
	if gear > 0 and in_brake > 0.1 and fwd_speed < 0.8 and in_throttle < 0.1:
		gear = -1
		gear_changed.emit(self, gear)
	elif gear < 0 and in_throttle > 0.1 and fwd_speed > -0.8:
		gear = 1
		gear_changed.emit(self, gear)

	var redline := t.max_otacky
	var idle := t.volnobezne_otacky
	var throttle := in_throttle if gear > 0 else in_brake
	var target_rpm: float
	var drive := 0.0
	if gear > 0:
		var gear_v := _gear_top_speed[gear - 1]
		var wheel_rpm := maxf(fwd_speed, 0.0) / gear_v * redline
		# Spojka prokluzuje pri rozjezdu
		var clutch_rpm := idle + (redline * 0.5 - idle) * throttle if gear == 1 else 0.0
		target_rpm = maxf(maxf(wheel_rpm, clutch_rpm), idle)
		# Automaticke radeni
		if _shift_timer <= 0.0:
			if wheel_rpm > redline * 0.95 and gear < n and throttle > 0.2:
				gear += 1
				_shift_timer = 0.2
				gear_changed.emit(self, gear)
			elif gear > 1 and wheel_rpm < redline * 0.42:
				gear -= 1
				_shift_timer = 0.1
				gear_changed.emit(self, gear)
	else:
		var rev_v := t.rychlost_couvani / KMH
		target_rpm = maxf(idle + (redline * 0.5 - idle) * throttle, absf(minf(fwd_speed, 0.0)) / rev_v * redline * 0.9)

	if wheelspin and throttle > 0.3:
		target_rpm = lerpf(target_rpm, redline * 0.97, 0.6)
	rpm = lerpf(rpm, minf(target_rpm, redline * 1.01), 1.0 - exp(-14.0 * delta))

	if throttle <= 0.0 or destroyed or _shift_timer > 0.12:
		return 0.0
	var power := t.vykon_kw * 1000.0 * DRIVETRAIN_EFFICIENCY * _power_curve(rpm / redline) * (1.0 - dmg * 0.4)
	if nitro_active:
		power *= t.nitro_vykon
	if gear > 0:
		if rpm >= redline and gear == n:
			return 0.0  # omezovac
		drive = throttle * power / maxf(absf(fwd_speed), 2.5)
	else:
		var rev_v := t.rychlost_couvani / KMH
		drive = -throttle * power / maxf(absf(fwd_speed), 2.5) * clampf(1.0 - absf(minf(fwd_speed, 0.0)) / rev_v, 0.0, 1.0)
	return drive


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _reset_to != null:
		state.transform = _reset_to
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_prev_velocity = Vector3.ZERO
		_reset_to = null
		return

	# Detekce narazu podle prudke zmeny rychlosti
	var v := state.linear_velocity
	var dv := (v - _prev_velocity).length()
	_prev_velocity = v
	var count := state.get_contact_count()
	if count == 0 or dv < 2.0:
		return
	var best := 0
	var best_impulse := -1.0
	for i in count:
		var imp := state.get_contact_impulse(i).length()
		if imp > best_impulse:
			best_impulse = imp
			best = i
	# Zpracuje se az v _physics_process (behem fyzikalniho kroku se nesmi pridavat uzly)
	if _pending_impact.is_empty() or dv > float(_pending_impact.dv):
		_pending_impact = {
			"dv": dv,
			"pos": state.get_contact_local_position(best),
			"normal": state.get_contact_local_normal(best),
			"collider": state.get_contact_collider_object(best),
		}


func _on_impact(dv: float, pos: Vector3, normal: Vector3, collider: Object) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if dv > 4.0:
		_impact_timer = clampf(dv / 20.0, 0.2, 0.8)
	impact.emit(self, dv, pos)
	if now - _last_impact_time > 0.08:
		FX.spawn_sparks(get_parent(), pos, normal, clampi(int(dv * 6.0), 8, 80))
		_last_impact_time = now
		if is_player:
			for cam in get_tree().get_nodes_in_group("camera_shake"):
				cam.call("add_shake", clampf(dv / 25.0, 0.03, 0.8))
	var strength := dv - t.prah_poskozeni
	if strength <= 0.0:
		return
	# Kdyz do nas narazi jine auto, poskozeni se deli podle hmotnosti
	if collider is Car:
		strength *= clampf((collider as Car).mass / mass, 0.5, 1.5)
	apply_damage(strength * 0.6 / maxf(t.odolnost, 0.1))


func apply_damage(amount: float) -> void:
	if destroyed or amount <= 0.0:
		return
	damage = minf(100.0, damage + amount)
	if damage > 40.0 and _damage_pull == 0.0:
		_damage_pull = deg_to_rad(randf_range(3.0, 6.0)) * (1.0 if randf() > 0.5 else -1.0)
	# Lak postupne matni a tmavne
	var d := damage_ratio()
	model.paint.albedo_color = t.barva.lerp(t.barva.darkened(0.5), d * 0.6)
	model.paint.roughness = lerpf(0.3, 0.65, d)
	model.paint.clearcoat = 1.0 - d * 0.8
	_update_damage_effects()
	damage_changed.emit(self, damage)
	if damage >= 100.0:
		explode()


func _engine_position() -> Vector3:
	var b := model.body_aabb
	return Vector3(0, b.position.y + b.size.y * 0.55, b.position.z + 0.9)


func _update_damage_effects() -> void:
	if model == null:
		return
	var pos := _engine_position()
	_smoke = _toggle_effect(_smoke, damage >= 50.0 and damage < 75.0, func(): return FX.make_smoke(false), pos)
	_heavy_smoke = _toggle_effect(_heavy_smoke, damage >= 75.0, func(): return FX.make_smoke(true), pos)
	_fire = _toggle_effect(_fire, damage >= 90.0, func(): return FX.make_fire(), pos)


func _toggle_effect(effect: GPUParticles3D, want: bool, factory: Callable, pos: Vector3) -> GPUParticles3D:
	if want and effect == null:
		effect = factory.call()
		model.add_child(effect)
		effect.position = pos
		effect.emitting = true
	elif not want and effect != null:
		effect.queue_free()
		effect = null
	return effect


## Vybuch auta: plameny, odhozene dily, auto vyrazeno.
func explode() -> void:
	if destroyed:
		return
	destroyed = true
	damage = 100.0
	FX.spawn_explosion(get_parent(), global_position + global_basis.y * 0.8, 9.0, 8000.0, [get_rid()])
	apply_central_impulse(Vector3.UP * mass * 6.5 + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * mass * 1.5)
	apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * mass * 2.5)
	# Ohorely vrak
	model.paint.albedo_color = Color(0.04, 0.035, 0.03)
	model.paint.metallic = 0.1
	model.paint.roughness = 0.95
	model.paint.clearcoat = 0.0
	model.tail_mat.emission_energy_multiplier = 0.0
	model.head_mat.emission_energy_multiplier = 0.0
	for beam in model.beams:
		beam.visible = false
	for part_name in ["kapota", "kufr", "dvere_lp", "dvere_pp", "naraznik_predni", "naraznik_zadni"]:
		var part: Node3D = model.parts.get(part_name)
		if part and is_instance_valid(part) and model.is_ancestor_of(part):
			detach_part(part, 7.0)
	_update_damage_effects()
	damage_changed.emit(self, damage)
	exploded.emit(self)


## Odtrhne dil z auta a udela z nej samostatny fyzicky objekt, ktery zustane lezet.
func detach_part(part: Node3D, launch_speed := 3.0) -> RigidBody3D:
	var xform := part.global_transform
	# Obrys dilu v jeho vlastnich souradnicich
	var aabb := AABB()
	var first := true
	for mi in ([part] + part.find_children("*", "MeshInstance3D", true, false)):
		if mi is MeshInstance3D and (mi as MeshInstance3D).mesh:
			var a: AABB = CarModel.xform_to(mi, part) * (mi as MeshInstance3D).mesh.get_aabb()
			aabb = a if first else aabb.merge(a)
			first = false
	if first:
		aabb = AABB(Vector3(-0.2, -0.2, -0.2), Vector3(0.4, 0.4, 0.4))
	var scale_f := xform.basis.get_scale()
	var body := RigidBody3D.new()
	body.name = "Dil_" + part.name
	body.mass = clampf(aabb.size.x * aabb.size.y * aabb.size.z * scale_f.x * scale_f.y * scale_f.z * 120.0, 6.0, 45.0)
	body.add_to_group("debris")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = (aabb.size * scale_f).max(Vector3.ONE * 0.05)
	shape.shape = box
	shape.position = xform.basis.orthonormalized().inverse() * (xform.basis * aabb.get_center())
	body.add_child(shape)
	get_parent().add_child(body)
	body.global_transform = Transform3D(xform.basis.orthonormalized(), xform.origin)
	part.get_parent().remove_child(part)
	body.add_child(part)
	part.transform = Transform3D(Basis().scaled(scale_f), Vector3.ZERO)
	var out := (body.global_transform * shape.position - global_position).normalized()
	body.linear_velocity = linear_velocity + (out + Vector3.UP).normalized() * launch_speed * randf_range(0.7, 1.3)
	body.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	return body


func _update_lights() -> void:
	var smoking := not destroyed and grounded_wheels >= 2 and (drifting or (wheelspin and speed_kmh < 60.0) or (in_handbrake and speed_kmh > 20.0))
	for smoke in _tire_smoke:
		smoke.emitting = smoking
	for flame in _nitro_flames:
		flame.emitting = nitro_active
	if destroyed:
		return
	var braking := (in_brake > 0.1 and get_forward_speed() > 1.0) or in_handbrake
	model.tail_mat.emission_energy_multiplier = 9.0 if braking else 2.0
