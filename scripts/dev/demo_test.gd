extends Node
## Test demolice (jen pro vyvoj):  -- --demotest=octavia [--shots=SLOZKA]
## Auto stoji (zmrazene) a dostava umele narazy z ruznych stran. Vypisuje promackliny, skla, dily
## a casy prestavby siti; se --shots fotí auto z nekolika stran po kazde fazi.

var arena: Node
var _car_id := "octavia"
var _dir := ""
var _hits := [
	# [bod v souradnicich auta (x doleva-/doprava+, y, z dopredu-), rychlost narazu m/s, popis]
	[Vector3(0.0, 0.6, -9.0), 13.0, "predek stred"],
	[Vector3(-0.5, 0.7, -9.0), 16.0, "predek vlevo"],
	[Vector3(-9.0, 0.8, -0.4), 15.0, "levy bok (dvere)"],
	[Vector3(-9.0, 0.9, 0.3), 18.0, "levy bok znovu"],
	[Vector3(0.3, 0.7, 9.0), 15.0, "zadek"],
	[Vector3(0.0, 9.0, 0.0), 11.0, "strecha"],
	[Vector3(9.0, 0.8, 0.0), 20.0, "pravy bok"],
	[Vector3(0.0, 0.7, -9.0), 22.0, "predek znovu"],
	[Vector3(-9.0, 0.8, -0.2), 22.0, "levy bok potreti"],
	[Vector3(0.0, 0.7, 9.0), 25.0, "zadek znovu"],
	[Vector3(9.0, 0.8, 0.6), 26.0, "pravy bok znovu"],
	[Vector3(0.0, 0.7, -9.0), 30.0, "predek naplno"],
]


func _ready() -> void:
	arena = get_parent()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--demotest="):
			_car_id = arg.substr(11)
		if arg.begins_with("--shots="):
			_dir = arg.substr(8)
			DirAccess.make_dir_recursive_absolute(_dir)
	_run.call_deferred()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, true).timeout


func _run() -> void:
	while arena.get("car") == null:
		await get_tree().process_frame
	await _wait(0.5)
	var spot: Vector3 = arena.city.lot_spawns[0] if not arena.city.lot_spawns.is_empty() else arena.circuit.grid_transform().origin
	arena.spawn_car(_car_id, Transform3D(Basis(), spot + Vector3.UP * 0.6))
	var car: Car = arena.car
	await _wait(2.0)
	car.freeze = true
	var t0 := Time.get_ticks_msec()
	while not car.demolition.dents_ready and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
	printerr("[DEMO] %s: vrcholu %d, siti %d, oken %d, dilu %d, mrizka hotova za %d ms" % [_car_id, car.demolition.vertex_total,
		car.demolition._meshes.size(), car.demolition._windows.size(), car.demolition._parts.size(), Time.get_ticks_msec() - t0])
	var cam := Camera3D.new()
	arena.add_child(cam)
	await _shots(car, cam, "0_nove")
	var k := 0
	for h: Array in _hits:
		k += 1
		if car.destroyed:
			break
		var lp: Vector3 = h[0]
		var box := car.model.body_aabb
		var p := lp.clamp(box.position - Vector3.ONE * 0.05, box.end + Vector3.ONE * 0.05)
		var gp := car.model.global_transform * p
		var t1 := Time.get_ticks_usec()
		car._on_impact(float(h[1]), gp, Vector3.UP, null)
		var hit_ms := (Time.get_ticks_usec() - t1) / 1000.0
		await _wait(0.35)
		var ws: Vector3i = car.demolition.windows_state()
		var ps: Vector3i = car.demolition.parts_state()
		printerr("[DEMO] naraz %d (%s, %.0f m/s): poskozeni %.0f %% | skla cela %d prasla %d rozbita %d | dily drzi %d volne %d upadle %d | naraz %.1f ms, prestavba max %.1f ms%s" % [
			k, h[2], h[1], car.damage, ws.x, ws.y, ws.z, ps.x, ps.y, ps.z, hit_ms, car.demolition.max_rebuild_ms, " | VYBUCH" if car.destroyed else ""])
		if k in [3, 6, 9] or car.destroyed:
			await _shots(car, cam, "%d_naraz%d" % [k, k])
	# dohorit do vybuchu
	if not car.destroyed:
		car.apply_damage(100.0)
	await _wait(1.0)
	await _shots(car, cam, "9_vybuch")
	printerr("[DEMO] konec")
	get_tree().quit()


func _shots(car: Car, cam: Camera3D, tag: String) -> void:
	if _dir == "":
		return
	var c := car.global_position + Vector3.UP * 0.6
	var views := {"pl": Vector3(-4.2, 1.6, -4.4), "pz": Vector3(4.0, 1.8, 4.6)}
	for v: String in views:
		cam.current = true
		cam.global_position = car.global_transform * (views[v] as Vector3)
		cam.look_at(c, Vector3.UP)
		for i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_dir.path_join("%s_%s.png" % [tag, v]))
