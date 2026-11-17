extends Node
## Automaticky test (jen pro vyvoj). Spusti se parametrem:  -- --autotest [--shots=SLOZKA]
## Projede sekvenci jizdy, poskozeni a vybuchu, vypisuje stav a dela snimky obrazovky.

var _time := 0.0
var _next_log := 0.0
var _shots_dir := ""
var _shot_times := [2.5, 5.5, 8.0, 10.0, 15.4]
var _events := {}
var arena: Node


func _ready() -> void:
	arena = get_parent()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--speedtest="):
			_speed_car = arg.substr(12)
		if arg.begins_with("--handlingtest="):
			_handling_car = arg.substr(15)
		if arg.begins_with("--walltest="):
			_wall_angle = float(arg.substr(11))
		if arg.begins_with("--lap="):
			_lap_car = arg.substr(6)
		if arg.begins_with("--kol="):
			_lap_count = int(arg.substr(6))
		if arg.begins_with("--limit="):
			_lap_limit = float(arg.substr(8))
		if arg.begins_with("--r="):
			_lap_margin = float(arg.substr(4))
		if arg.begins_with("--g="):
			_lap_g = float(arg.substr(4))
		if arg == "--analog":
			_lap_keyboard = false
		if arg.begins_with("--shots="):
			_shots_dir = arg.substr(8)
			DirAccess.make_dir_recursive_absolute(_shots_dir)
	print("[AUTOTEST] start")


func _press(action: String, on: bool, strength := 1.0) -> void:
	if on:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _once(key: String) -> bool:
	if _events.has(key):
		return false
	_events[key] = true
	return true


var _lap_car := ""
var _lap_g := 1.4
var _lap_margin := 2.0
var _lap_count := 2
var _lap_limit := 330.0
var _lap_keyboard := true
var _ai: AIDriver
var _lap_start := 0.0
var _impacts := 0
var _hard_impacts := 0
var _min_v := 999.0
var _max_v := 0.0
var _max_slip := 0.0


## Test okruhu: pocitacovy jezdec (ovlada jako klavesnice) jede 2 kola, meri se cas a chyby.
func _lap_test(t: float, car) -> void:
	if t > 0.2 and _once("lapset"):
		arena.spawn_car(_lap_car, arena.circuit.grid_transform())
		car = arena.car
		for ch in car.get_children():
			if ch is PlayerController:
				ch.set_physics_process(false)
				ch.queue_free()
		_ai = AIDriver.new()
		_ai.keyboard = _lap_keyboard
		_ai.lat_g = _lap_g
		car.add_child(_ai)
		var rl: Dictionary = arena.circuit.racing_line(_lap_margin)
		_ai.set_route(rl.corners, 24.0, rl.radii)
		if car.has_signal("impact"):
			car.impact.connect(func(_c, dv, pos):
				_impacts += 1
				if OS.get_environment("LAPDEBUG") != "":
					print("[IMPACT] dv=%.1f pos=(%.1f, %.2f, %.1f) i=%d v=%.0f" % [dv, pos.x, pos.y, pos.z, _ai.index, car.linear_velocity.length() * 3.6])
				if dv > 6.0:
					_hard_impacts += 1)
		_lap_start = t
		return
	if _ai == null:
		return
	var v: float = car.linear_velocity.length() * 3.6
	if t - _lap_start > 4.0:
		_min_v = minf(_min_v, v)
	_max_v = maxf(_max_v, v)
	if car.get("drift_angle") != null and v > 30.0:
		_max_slip = maxf(_max_slip, car.drift_angle)
	if OS.get_environment("LAPDEBUG") != "" and t >= _phase_log:
		_phase_log = t + 0.25
		print("[LAPDBG] t=%.1f i=%d pos=(%.0f,%.0f) v=%.0f lim=%.0f slip=%.0f steer=%.1f thr=%.0f brk=%.0f" % [t, _ai.index, car.global_position.x, car.global_position.z, v, _ai.speed_limit[_ai.index] * 3.6, car.drift_angle, car.in_steer, car.in_throttle, car.in_brake])
	if _ai.laps >= 1 and _once("lap1"):
		print("[LAP] %s g=%.2f kolo 1: %.1f s" % [_lap_car, _lap_g, t - _lap_start])
		_lap_start = t
	if _ai.laps >= _lap_count or t > _lap_limit:
		print("[LAP] %s g=%.2f %s: %.1f s | odchylka od stopy max %.1f m | narazy %d (tvrde %d) | poskozeni %.0f | v min %.0f max %.0f | smyk max %.0f st" % [
			_lap_car, _lap_g, ("kolo %d" % _lap_count) if _ai.laps >= _lap_count else "NEDOJEL (i %d z %d)" % [_ai.index, _ai.line.size()], t - _lap_start, _ai.off_line_max, _impacts, _hard_impacts, car.damage, _min_v, _max_v, _max_slip])
		var city = arena.city
		print("[MESTO] nacitani okoli: %d dlazdic, prumer %.1f ms, nejdele %.1f ms, aktivnich %d" % [city.activate_count, city.activate_ms_sum / maxf(city.activate_count, 1), city.activate_ms_max, city._active.size()])
		print("[MESTO] nejpomalejsi krok: %s %.1f ms" % [city.slowest_job, city.slowest_job_ms])
		get_tree().quit()


var _wall_angle := -1.0
var _wall_dir := Vector2.RIGHT


## Najde dlouhou rovnou ulici: vraci [bod 60 m od zacatku, smer].
func _straight_street() -> Array:
	var map: CityMap = arena.city.map
	for e in map.polylines.size():
		var pl := map.polylines[e]
		if pl.size() == 2 and pl[0].distance_to(pl[1]) > 260.0 and map.side_type(e, 1) == "" and map.edge_class[e] == "ulice":
			var dir := (pl[1] - pl[0]).normalized()
			return [pl[0] + dir * 70.0, dir, map.edge_height(e, 70.0)]
	return [Vector2.ZERO, Vector2.RIGHT, 0.0]


## Test otreni o zed: auto jede 100 km/h pod uhlem do zdi budovy, plny plyn, bez volantu.
func _wall_test(t: float, car) -> void:
	if t > 0.2 and _once("wallset"):
		# Rovna ulice (najde se v planu mesta); auto miri pod uhlem k prave zdi
		var st := _straight_street()
		var dir: Vector2 = st[1]
		_wall_dir = dir
		var start: Vector2 = st[0] + CityMap.right_of(dir) * 2.0
		var basis := Basis.looking_at(CityMap.to3(dir.rotated(deg_to_rad(_wall_angle))), Vector3.UP)
		arena.spawn_car("octavia", Transform3D(basis, CityMap.to3(start, st[2] + 0.6)))
		arena.car.impact.connect(func(_c, dv, pos): print("[WALL] naraz dv=%.1f v miste (%.1f, %.2f, %.1f)" % [dv, pos.x, pos.y, pos.z]))
		return
	if t > 1.2 and _once("wallgo"):
		car.linear_velocity = -car.global_basis.z * 27.8
	_press("plyn", t > 1.2)
	if t > 1.2 and t >= _phase_log:
		_phase_log = t + 0.25
		var f: Vector3 = -car.global_basis.z
		print("[WALL] t=%.2f pos=(%.1f, %.1f) v=%.0f km/h smer=%.0f st (0 = podel zdi) poskozeni=%.1f" % [t - 1.2, car.global_position.x, car.global_position.z, car.linear_velocity.length() * 3.6, rad_to_deg(_wall_dir.angle_to(Vector2(f.x, f.z))), car.damage])
	if t > 4.5:
		get_tree().quit()


var _speed_car := ""
var _handling_car := ""
var _marks := {}
var _phase_log := 0.0


## Test rizeni na volne plose: zatacky v ruznych rychlostech, slalom, drift.
func _handling_test(t: float, car) -> void:
	if t > 0.2 and _once("hset"):
		arena.spawn_car(_handling_car, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, CityBuilder.SAFE_Y + 0.6, 7500)))
	# Faze: [od, do, plyn, volant(-1 vlevo..1 vpravo), rucni, cil km/h pro rozjezd]
	var phases := [
		[1.0, 6.0, "rozjezd 60", 0.0, false, 60.0],
		[6.0, 9.0, "zatacka 60 bez plynu", -1.0, false, -1.0],
		[9.0, 16.0, "rozjezd 100", 0.0, false, 100.0],
		[16.0, 19.0, "zatacka 100 s plynem", 1.0, false, 100.0],
		[19.0, 26.0, "rozjezd 80", 0.0, false, 80.0],
		[26.0, 32.0, "slalom 80", 2.0, false, 80.0],
		[32.0, 38.0, "rozjezd 90", 0.0, false, 90.0],
		[38.0, 38.6, "rucni brzda + vlevo", -1.0, true, -2.0],
		[38.6, 41.6, "drift: plyn + drzet volant", -1.0, false, 200.0],
		[41.6, 44.0, "volant rovne + plyn", 0.0, false, 200.0],
	]
	var cur: Array = []
	for ph in phases:
		if t >= ph[0] and t < ph[1]:
			cur = ph
	if cur.is_empty():
		_press("plyn", false); _press("vlevo", false); _press("vpravo", false); _press("rucni_brzda", false)
		if t > 44.5:
			print("[HANDLING] %s konec" % _handling_car)
			get_tree().quit()
		return
	var target: float = cur[5]
	var throttle := false
	if target > 0.0:
		throttle = car.speed_kmh < target
	elif target < -1.5:
		throttle = true
	var steer: float = cur[3]
	if steer > 1.5:
		steer = -1.0 if int(t) % 2 == 0 else 1.0
	_press("plyn", throttle)
	_press("vlevo", steer < -0.1, absf(steer))
	_press("vpravo", steer > 0.1, absf(steer))
	_press("rucni_brzda", cur[4])
	if OS.get_environment("HDEBUG") != "" and t > 38.3 and t < 40.0:
		print("[DBG] t=%.2f mode=%s ang=%.0f fwd=%.1f yaw=%.2f in=%.2f hb=%s grounded=%d up=%.2f pos=%s" % [t, car._drift_mode, car.drift_angle, car.get_forward_speed(), car.angular_velocity.y, car._steer_input, car.in_handbrake, car.grounded_wheels, car.global_basis.y.y, car.global_position])
	if t >= _phase_log:
		_phase_log = t + 0.5
		var w: float = car.angular_velocity.y
		var v: float = car.linear_velocity.length()
		var r: float = v / absf(w) if absf(w) > 0.01 else 9999.0
		print("[HANDLING] %s %-24s t=%.1f km/h=%3.0f yaw=%5.2f R=%6.1f m drift=%s %2.0f° steer=%.2f" % [
			_handling_car, cur[2], t, car.speed_kmh, w, r, car.drifting, car.drift_angle, rad_to_deg(car.steer_angle)])


func _speed_test(t: float, car) -> void:
	# Rovinka mimo mesto: plny plyn 45 s, vypis casu na 100/200 km/h a max. rychlosti
	if t > 0.2 and _once("speed_setup"):
		arena.spawn_car(_speed_car, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(4500, CityBuilder.SAFE_Y + 0.6, 8200)))
	_press("plyn", t > 1.5)
	var drive_t: float = t - 1.5
	for kmh in [100, 200]:
		if car.speed_kmh >= kmh and not _marks.has(kmh) and drive_t > 0.0:
			_marks[kmh] = drive_t
			print("[SPEEDTEST] %s 0-%d km/h: %.1f s" % [_speed_car, kmh, drive_t])
	if t >= _next_log:
		_next_log += 5.0
		print("[SPEEDTEST] %s t=%.0f km/h=%.0f gear=%s rpm=%.0f" % [_speed_car, drive_t, car.speed_kmh, car.gear_label(), car.rpm])
	if t > 47.0:
		print("[SPEEDTEST] %s konec, max %.0f km/h" % [_speed_car, car.speed_kmh])
		get_tree().quit()


func _physics_process(delta: float) -> void:
	_time += delta
	var car = arena.car
	var t := _time
	if _speed_car != "":
		_speed_test(t, car)
		return
	if _handling_car != "":
		_handling_test(t, car)
		return
	if _lap_car != "":
		_lap_test(t, car)
		return
	if _wall_angle >= 0.0:
		_wall_test(t, car)
		return
	_press("plyn", (t > 1.0 and t < 10.0) or (t > 22.6 and t < 23.0))
	_press("vlevo", t > 4.0 and t < 5.6)
	_press("rucni_brzda", t > 4.0 and t < 4.5)
	_press("vpravo", t > 5.6 and t < 6.4)
	_press("nitro", t > 7.0 and t < 10.0)
	_press("brzda", t > 10.0 and t < 12.5)

	if t > 13.0 and _once("dmg1"):
		car.apply_damage(50.0)
		print("[AUTOTEST] poskozeni 50 -> ", car.damage)
	if t > 14.0 and _once("dmg2"):
		car.apply_damage(40.0)
		print("[AUTOTEST] poskozeni +40 -> ", car.damage)
	if t > 15.0 and _once("dmg3"):
		car.apply_damage(20.0)
		print("[AUTOTEST] vybuch, destroyed=", car.destroyed)
	if t > 21.0 and _once("crash"):
		print("[AUTOTEST] test narazu do steny 30 m/s, poskozeni pred: ", car.damage)
		var st := _straight_street()
		_wall_dir = CityMap.right_of(st[1])
		car.teleport(Transform3D(Basis.looking_at(CityMap.to3(_wall_dir), Vector3.UP), CityMap.to3(st[0], st[2] + 1.0)))
	if t > 21.3 and _once("crash_vel"):
		car.linear_velocity = CityMap.to3(_wall_dir) * 30.0
	if t > 23.0 and _once("crash_res"):
		print("[AUTOTEST] poskozeni po narazu: ", car.damage)

	if t >= _next_log:
		_next_log += 0.5
		print("[AUTOTEST] t=%.1f pos=(%.1f, %.2f, %.1f) km/h=%.0f kola=%d drift=%s(%.0f) nitro=%.2f dmg=%.0f up=%.2f" % [
			t, car.global_position.x, car.global_position.y, car.global_position.z, car.speed_kmh,
			car.grounded_wheels, car.drifting, car.drift_angle, car.nitro, car.damage, car.global_basis.y.y])

	if _shots_dir != "" and not _shot_times.is_empty() and t >= _shot_times[0]:
		var st: float = _shot_times.pop_front()
		_screenshot("shot_%04.1f.png" % st)

	if _shots_dir != "" and _shot_times.is_empty() and "--rychle" in OS.get_cmdline_user_args():
		get_tree().quit()
	if t > 24.0:
		print("[AUTOTEST] konec")
		get_tree().quit()


func _screenshot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(_shots_dir.path_join(file))
		print("[AUTOTEST] snimek ", file)
