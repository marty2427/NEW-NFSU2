extends Node
## Automaticky test (jen pro vyvoj). Spusti se parametrem:  -- --autotest [--shots=SLOZKA]
## Projede sekvenci jizdy, poskozeni a vybuchu, vypisuje stav a dela snimky obrazovky.

var _time := 0.0
var _next_log := 0.0
var _shots_dir := ""
var _shot_times := [2.0, 4.6, 6.5, 8.0, 10.0, 13.3, 14.5, 15.4, 16.2, 22.4]
var _events := {}
var arena: Node


func _ready() -> void:
	arena = get_parent()
	for arg in OS.get_cmdline_user_args():
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


func _physics_process(delta: float) -> void:
	_time += delta
	var car: Car = arena.car
	var t := _time
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
		car.teleport(Transform3D(Basis(), Vector3(0, 1.0, -70)))
	if t > 21.3 and _once("crash_vel"):
		car.linear_velocity = Vector3(0, 0, -30)
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

	if t > 24.0:
		print("[AUTOTEST] konec")
		get_tree().quit()


func _screenshot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img:
		img.save_png(_shots_dir.path_join(file))
		print("[AUTOTEST] snimek ", file)
