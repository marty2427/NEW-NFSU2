class_name Car
extends RigidBody3D
## Arkadove auto: vlastni odpruzeni pres paprsky (raycast), smyk, drift, nitro,
## poskozeni a vybuch. Vsechny hodnoty jizdy jsou v tuning/auta.cfg.

signal exploded(car: Car)
signal impact(car: Car, strength: float, position: Vector3)
signal damage_changed(car: Car, damage: float)

const GRAVITY := 9.8
const KMH := 3.6

@export var car_id := "ulicni"
@export var is_player := true

var t: CarTuning
var model: Dictionary

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

var _wheels: Array[Dictionary] = []
var _prev_velocity := Vector3.ZERO
var _reset_to: Variant = null      # Transform3D, kdyz se ma auto presunout
var _damage_pull := 0.0            # poskozene auto tahne do strany
var _smoke: GPUParticles3D
var _heavy_smoke: GPUParticles3D
var _fire: GPUParticles3D
var _last_impact_time := 0.0
var _collision: CollisionShape3D
var _pending_impact: Dictionary = {}
var _upside_down_time := 0.0


func _ready() -> void:
	add_to_group("cars")
	contact_monitor = true
	max_contacts_reported = 8
	can_sleep = false
	continuous_cd = true
	angular_damp = 0.8
	setup(car_id)


## Postavi auto podle zadaneho id (sekce v auta.cfg). Lze volat znovu pro zmenu auta.
func setup(new_id: String) -> void:
	car_id = new_id
	t = CarTuning.load_car(car_id)
	# Smazat stary vzhled a kolizi
	for child in get_children():
		if String(child.name) in ["Vzhled", "Kolize"]:
			remove_child(child)
			child.queue_free()
	_smoke = null
	_heavy_smoke = null
	_fire = null

	mass = t.hmotnost
	model = CarBuilder.build(self, t, is_player)

	_collision = CollisionShape3D.new()
	_collision.name = "Kolize"
	var box := BoxShape3D.new()
	var size: Vector3 = model.body_size
	box.size = Vector3(size.x, size.y * 0.92, size.z + 0.2)
	_collision.shape = box
	_collision.position = Vector3(0, model.body_center_y, 0)
	add_child(_collision)

	# Nizko polozene teziste = stabilnejsi auto
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.3, 0)

	var physics_material := PhysicsMaterial.new()
	physics_material.friction = 0.4
	physics_material.bounce = 0.1
	physics_material_override = physics_material

	_wheels.clear()
	var positions: Array = model.wheel_positions
	for i in positions.size():
		var front := i < 2
		var driven := (t.pohon == "vsechna") or (t.pohon == "predni" and front) or (t.pohon == "zadni" and not front)
		_wheels.append({
			"pos": positions[i],
			"front": front,
			"driven": driven,
			"node": model.wheels[i],
			"spin": (model.wheels[i] as Node3D).get_node("Rotace"),
			"compression": 0.0,
			"grounded": false,
			"load": 0.0,
			"slip": 0.0,
		})
	repair()


func repair() -> void:
	damage = 0.0
	destroyed = false
	nitro = 1.0
	_damage_pull = 0.0
	if model.has("paint"):
		var paint: StandardMaterial3D = model.paint
		paint.albedo_color = t.barva
		paint.metallic = 0.35
		paint.roughness = 0.3
		paint.clearcoat = 1.0
	for beam in model.get("beams", []):
		beam.visible = true
	if model.has("underglow"):
		model.underglow.visible = true
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
	var xf := Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), global_position + Vector3.UP * 1.2)
	teleport(xf)


func get_forward_speed() -> float:
	return linear_velocity.dot(-global_basis.z)


func damage_ratio() -> float:
	return damage / 100.0


# ---------------------------------------------------------------------
#  Fyzika
# ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if t == null:
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
	var speed_factor := clampf(speed_kmh / t.max_rychlost, 0.0, 1.0)
	var max_steer := deg_to_rad(t.max_natoceni_kol) * lerpf(1.0, t.natoceni_ve_vysoke_rychlosti, speed_factor)
	max_steer *= 1.0 - dmg * 0.3
	var target_steer := -in_steer * max_steer + _damage_pull * dmg
	steer_angle = move_toward(steer_angle, target_steer, t.rychlost_volantu * delta)

	# --- Nitro ---
	nitro_active = in_nitro and nitro > 0.0 and in_throttle > 0.1 and not destroyed
	if nitro_active:
		nitro = maxf(0.0, nitro - t.nitro_spotreba * delta)
	else:
		nitro = minf(1.0, nitro + t.nitro_dobijeni * delta)

	var top_speed := t.max_rychlost / KMH
	var engine_force := t.sila_motoru * (1.0 - dmg * 0.45)
	if nitro_active:
		top_speed *= t.nitro_max_rychlost
		engine_force *= t.nitro_sila

	# --- Plyn / brzda / couvani ---
	var drive := 0.0
	var braking := 0.0
	if in_throttle > 0.0:
		if fwd_speed < -1.0:
			braking = in_throttle
		else:
			drive = in_throttle
	if in_brake > 0.0:
		if fwd_speed > 1.0:
			braking = maxf(braking, in_brake)
		else:
			drive = -in_brake
	var power_curve := 0.0
	if drive > 0.0:
		power_curve = clampf(1.0 - pow(maxf(fwd_speed, 0.0) / top_speed, 3.0), 0.0, 1.0)
	elif drive < 0.0:
		power_curve = clampf(1.0 - absf(minf(fwd_speed, 0.0)) / (t.rychlost_couvani / KMH), 0.0, 1.0) * 0.6

	# --- Kola ---
	var space := get_world_3d().direct_space_state
	var ray_len := t.zdvih_pruziny + t.polomer_kola
	var mass_per_wheel := mass / 4.0
	var spring_k := mass_per_wheel * GRAVITY / maxf(t.propad_podvozku, 0.02)
	var damper := 2.0 * sqrt(spring_k * mass_per_wheel) * t.tlumeni
	var driven_count := 0
	for w in _wheels:
		if w.driven:
			driven_count += 1
	grounded_wheels = 0
	var rear_slip := 0.0
	var exclude: Array[RID] = [get_rid()]

	for w in _wheels:
		var mount: Vector3 = global_transform * (w.pos as Vector3)
		var query := PhysicsRayQueryParameters3D.create(mount, mount - up * ray_len)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		var wheel_node: Node3D = w.node
		if hit.is_empty():
			w.grounded = false
			w.compression = 0.0
			w.load = 0.0
			wheel_node.position.y = CarBuilder.MOUNT_Y - t.zdvih_pruziny
			continue
		w.grounded = true
		grounded_wheels += 1
		var hit_pos: Vector3 = hit.position
		var normal: Vector3 = hit.normal
		var dist := mount.distance_to(hit_pos)
		var compression := ray_len - dist
		var comp_vel := (compression - float(w.compression)) / delta
		w.compression = compression
		wheel_node.position.y = CarBuilder.MOUNT_Y - (dist - t.polomer_kola)

		# Pruzina + tlumic
		var spring_force := maxf(0.0, spring_k * compression + damper * comp_vel)
		spring_force = minf(spring_force, mass * GRAVITY * 3.0)
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

		# Bocni prilnavost
		var grip := t.prilnavost_predni if w.front else t.prilnavost_zadni
		var slip_angle := rad_to_deg(atan2(absf(v_lat), maxf(absf(v_fwd), 0.5)))
		w.slip = slip_angle
		if not w.front:
			rear_slip = maxf(rear_slip, slip_angle)
			if in_handbrake:
				grip *= t.prilnavost_rucni_brzda
			elif slip_angle > t.uhel_zacatku_driftu and speed > 6.0:
				grip *= t.prilnavost_v_driftu
		elif drifting:
			grip *= 0.7  # predek v driftu klouze vic
		grip *= 1.0 - dmg * 0.25
		var lat_needed := -v_lat * mass_per_wheel / delta
		var lat_max := grip * spring_force
		var lat_force := clampf(lat_needed * 0.9, -lat_max, lat_max)

		# Podelne sily: motor, brzdy, valivy odpor
		var long_force := 0.0
		if w.driven and drive != 0.0:
			long_force += drive * engine_force * power_curve / maxi(driven_count, 1)
		if braking > 0.0:
			long_force -= signf(v_fwd) * minf(t.sila_brzd * 0.25 * braking, absf(v_fwd) * mass_per_wheel / delta)
		if in_handbrake and not w.front:
			long_force -= signf(v_fwd) * minf(t.sila_rucni_brzdy * 0.5, absf(v_fwd) * mass_per_wheel / delta)
		long_force -= v_fwd * 3.0  # valivy odpor

		apply_force(wheel_right * lat_force + wheel_fwd * long_force, offset)

		# Otaceni kola (vzhled)
		var spin: Node3D = w.spin
		var spin_speed := v_fwd / t.polomer_kola
		if in_handbrake and not w.front:
			spin_speed = 0.0
		spin.rotate_x(-spin_speed * delta)
		if w.front:
			wheel_node.rotation.y = steer_angle

	# --- Drift ---
	var lateral_speed := linear_velocity.dot(bas.x)
	drift_angle = rad_to_deg(atan2(absf(lateral_speed), maxf(absf(fwd_speed), 0.1)))
	drifting = grounded_wheels >= 2 and speed > 8.0 and drift_angle > t.uhel_zacatku_driftu and fwd_speed > 0.0
	if drifting:
		nitro = minf(1.0, nitro + t.nitro_za_drift * delta)

	if grounded_wheels > 0:
		# Arkadova pomoc pri zataceni - auto lepe reaguje na volant
		var yaw_rate := angular_velocity.dot(up)
		var yaw_max := 1.1 if drifting else 1.6
		var desired_yaw := -in_steer * clampf(speed / 12.0, 0.0, 1.0) * yaw_max * signf(fwd_speed + 0.01)
		var assist := t.pomoc_zataceni
		if drifting or in_handbrake:
			assist += t.pomoc_driftu
		apply_torque(up * (desired_yaw - yaw_rate) * mass * 0.6 * assist * (1.0 - dmg * 0.4))
		if drifting:
			# Pomoc v driftu: smer jizdy se postupne stoci za predkem auta,
			# ale rychlost se skoro neztrati (arkadovy drift jako v NFS).
			var v_flat := linear_velocity - up * linear_velocity.dot(up)
			var heading := (-bas.z - up * (-bas.z).dot(up)).normalized()
			var keep := 1.0 if in_throttle > 0.1 else 0.5
			apply_central_force((heading * v_flat.length() - v_flat) * mass * 2.2 * t.pomoc_driftu * keep)
			# Pojistka proti roztoceni: kdyz je uhel prilis velky, auto se samo srovna
			if drift_angle > t.max_uhel_driftu and v_flat.length() > 1.0:
				var side := signf(heading.cross(v_flat.normalized()).dot(up))
				apply_torque(up * side * (drift_angle - t.max_uhel_driftu) * mass * 0.12 * t.pomoc_driftu)
		# Pritlak
		apply_central_force(-up * speed * speed * t.pritlak * mass / 1000.0)
	else:
		# Ve vzduchu: auto se pomalu vyrovnava
		var level_axis := up.cross(Vector3.UP)
		apply_torque(level_axis * mass * 3.0 - angular_velocity * mass * 0.3)

	# Odpor vzduchu
	apply_central_force(-linear_velocity * speed * 0.25)

	# Auto na strese nebo na boku se samo postavi na kola
	if up.y < 0.35 and speed < 2.0 and not destroyed:
		_upside_down_time += delta
		if _upside_down_time > 2.5:
			_upside_down_time = 0.0
			flip_upright()
	else:
		_upside_down_time = 0.0

	_update_lights()


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
	if count == 0 or dv < t.prah_poskozeni:
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
	var strength := dv - t.prah_poskozeni
	impact.emit(self, strength, pos)
	if now - _last_impact_time > 0.08:
		FX.spawn_sparks(get_parent(), pos, normal, clampi(int(strength * 10.0), 10, 80))
		_last_impact_time = now
		if is_player:
			for cam in get_tree().get_nodes_in_group("camera_shake"):
				cam.call("add_shake", clampf(strength / 15.0, 0.05, 0.8))
	# Kdyz do nas narazi jine auto, poskozeni se deli podle hmotnosti
	if collider is Car:
		var other := collider as Car
		strength *= clampf(other.mass / mass, 0.5, 1.5)
	apply_damage(strength * 2.2 / maxf(t.odolnost, 0.1))


func apply_damage(amount: float) -> void:
	if destroyed or amount <= 0.0:
		return
	damage = minf(100.0, damage + amount)
	if damage > 30.0 and _damage_pull == 0.0:
		_damage_pull = deg_to_rad(randf_range(4.0, 8.0)) * (1.0 if randf() > 0.5 else -1.0)
	# Lak postupne tmavne a matni
	var paint: StandardMaterial3D = model.paint
	var d := damage_ratio()
	paint.albedo_color = t.barva.lerp(t.barva.darkened(0.6), d * 0.7)
	paint.roughness = lerpf(0.3, 0.7, d)
	paint.clearcoat = 1.0 - d
	_update_damage_effects()
	damage_changed.emit(self, damage)
	if damage >= 100.0:
		explode()


func _update_damage_effects() -> void:
	var visual: Node3D = model.get("visual")
	if visual == null:
		return
	var engine_pos := Vector3(0, CarBuilder.BODY_BOTTOM + t.rozmery.y * 0.5, -t.rozmery.z * 0.33)
	var want_smoke := damage >= 35.0 and damage < 70.0
	var want_heavy := damage >= 70.0
	var want_fire := damage >= 85.0
	_smoke = _toggle_effect(_smoke, want_smoke, func(): return FX.make_smoke(false), visual, engine_pos)
	_heavy_smoke = _toggle_effect(_heavy_smoke, want_heavy, func(): return FX.make_smoke(true), visual, engine_pos)
	_fire = _toggle_effect(_fire, want_fire, func(): return FX.make_fire(), visual, engine_pos)


func _toggle_effect(effect: GPUParticles3D, want: bool, factory: Callable, parent: Node3D, pos: Vector3) -> GPUParticles3D:
	if want and effect == null:
		effect = factory.call()
		parent.add_child(effect)
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
	FX.spawn_explosion(get_parent(), global_position + global_basis.y * 0.5, 9.0, 8000.0, [get_rid()])
	# Auto vyleti do vzduchu
	apply_central_impulse(Vector3.UP * mass * 6.5 + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * mass * 1.5)
	apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1)) * mass * 2.5)
	# Ohorely vrak
	var paint: StandardMaterial3D = model.paint
	paint.albedo_color = Color(0.04, 0.035, 0.03)
	paint.metallic = 0.1
	paint.roughness = 0.95
	paint.clearcoat = 0.0
	for beam in model.get("beams", []):
		beam.visible = false
	model.underglow.visible = false
	# Odhodit dily
	for part_name in ["kapota", "kufr", "dvere_leve", "dvere_prave", "naraznik_predni"]:
		var part: Node3D = model.parts.get(part_name)
		if part and is_instance_valid(part) and part.get_parent() == model.visual:
			detach_part(part, 7.0)
	_update_damage_effects()
	damage_changed.emit(self, damage)
	exploded.emit(self)


## Odtrhne dil z auta a udela z nej samostatny fyzicky objekt, ktery zustane lezet.
func detach_part(part: Node3D, launch_speed := 3.0) -> RigidBody3D:
	var mi := part as MeshInstance3D
	var aabb := AABB(Vector3.ZERO, Vector3.ONE * 0.3)
	if mi and mi.mesh:
		aabb = mi.mesh.get_aabb()
	var xform := part.global_transform
	var body := RigidBody3D.new()
	body.name = "Dil_" + part.name
	body.mass = clampf(aabb.size.x * aabb.size.y * aabb.size.z * 400.0, 4.0, 40.0)
	body.add_to_group("debris")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size.max(Vector3.ONE * 0.06)
	shape.shape = box
	shape.position = aabb.get_center()
	body.add_child(shape)
	get_parent().add_child(body)
	body.global_transform = xform
	part.get_parent().remove_child(part)
	body.add_child(part)
	part.transform = Transform3D.IDENTITY
	var out := (xform.origin - global_position).normalized()
	body.linear_velocity = linear_velocity + (out + Vector3.UP).normalized() * launch_speed * randf_range(0.7, 1.3)
	body.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	return body


func _update_lights() -> void:
	var tail: StandardMaterial3D = model.tail_mat
	tail.emission_energy_multiplier = 8.0 if (in_brake > 0.1 and get_forward_speed() > 1.0) or in_handbrake else 2.5
	if destroyed:
		tail.emission_energy_multiplier = 0.0
