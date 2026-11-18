extends Node
## Vyvojove snimky:  -- --snapshot=SLOZKA [--pohledy=a,b,c]
## Ulozi nekolik pohledu na mesto (z vysky i z ulice) jako PNG.
var _frames := 0
var _dir := ""
var _views := []
var _index := 0
var _only := PackedStringArray()
var _tacho := Vector3(-1, 0, 0)     # otacky, rychlost, nitro (pro kontrolu vzhledu tachometru)


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snapshot="):
			_dir = arg.substr(11)
		if arg.begins_with("--tacho="):
			var parts := arg.substr(8).split(",")
			_tacho = Vector3(float(parts[0]), float(parts[1]), float(parts[2]) if parts.size() > 2 else 0.5)
		if arg.begins_with("--pohledy="):
			_only = arg.substr(10).split(",")
	DirAccess.make_dir_recursive_absolute(_dir)
	var arena := get_parent()
	if OS.get_cmdline_user_args().has("--mapa"):
		arena.hud._bigmap.toggle()
	var st: Transform3D = arena.circuit.grid_transform()
	var map: CityMap = arena.city.map
	var g := func(x: float, z: float, up: float) -> Vector3: return Vector3(x, map.height_at(x, z) + up, z)
	var lot := Vector3.ZERO
	if not arena.city.lot_spawns.is_empty():
		lot = arena.city.lot_spawns[0]
	# most a podjezd na magistrale, serpentiny v kopcich
	var bridge := Vector3.ZERO
	var bridge_dir := Vector3.FORWARD
	var under := Vector3.ZERO
	var under_dir := Vector3.FORWARD
	var hill := Vector3.ZERO
	for e in map.polylines.size():
		var pl := map.polylines[e]
		if map.edge_class[e] == "magistrala":
			for sp in map.bridges[e]:
				if bridge == Vector3.ZERO and sp[1] - sp[0] < 80.0:
					var pd := CityMap.point_at(pl, sp[0] - 70.0)
					bridge = CityMap.to3(pd[0], map.edge_height(e, sp[0] - 70.0) + 2.0)
					bridge_dir = CityMap.to3(pd[1])
			for sp in map.underpasses[e]:
				if under == Vector3.ZERO:
					var pd := CityMap.point_at(pl, sp[0] - 60.0)
					under = CityMap.to3(pd[0], map.edge_height(e, sp[0] - 60.0) + 1.8)
					under_dir = CityMap.to3(pd[1])
		if map.edge_class[e] == "horska" and hill == Vector3.ZERO and pl.size() > 200:
			hill = CityMap.to3(pl[150], map.heights[e][150])
	var all := [
		["mapa", Vector3(4700, 14000, -1801), Vector3(4700, 0, -1800), true],
		["start", st.origin + st.basis * Vector3(0.5, 1.6, 7.5), st.origin + st.basis * Vector3(0, 0.0, -20), false],
		["plocha", lot + Vector3(90, 45, 120), lot, false],
		["reka", g.call(250, 520, 60), g.call(-200, 250, 0), false],
		["stare", g.call(150, 150, 110), g.call(-50, -80, 0), false],
		["mestoB", g.call(8200, 300, 160), g.call(9500, 900, 0), false],
		["most", bridge, bridge + bridge_dir * 60.0, false],
		["podjezd", under, under + under_dir * 60.0, false],
		["serpentiny", hill + Vector3(0, 60, 0) + (hill * Vector3(1, 0, 1)).normalized() * 250.0, hill, false],
		["vyhled", hill + Vector3(0, 12, 0), Vector3(4700, 30, 0), false],
		["kopce", g.call(-600, -3600, 120), g.call(-900, -6500, 250), false],
		["hory", g.call(4000, -4200, 250), g.call(2500, -7500, 450), false],
	]
	# Pohledy ridice podel okruhu
	var route: PackedVector3Array = arena.circuit.route
	var total := 0.0
	var acc := PackedFloat32Array([0.0])
	for i in route.size():
		total += route[i].distance_to(route[(i + 1) % route.size()])
		acc.append(total)
	for k in 8:
		var dist := total * (k + 0.37) / 8.0
		var i := 0
		while acc[i + 1] < dist:
			i += 1
		var a := route[i]
		var b := route[(i + 1) % route.size()]
		var p := a.lerp(b, (dist - acc[i]) / maxf(acc[i + 1] - acc[i], 0.01))
		var d := (b - a).normalized()
		all.append(["okruh%d" % k, p + Vector3(0, 1.8, 0) + d.cross(Vector3.UP).normalized() * 2.0, p + d * 40.0 + Vector3(0, 2.0, 0), false])
	for v in all:
		if _only.is_empty() or _only.has(v[0]):
			_views.append(v)
	# Pohledy na auta: -- --auta=skyline,supra  (kazde auto se postavi na start a vyfoti z 3/4 zepredu)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--auta="):
			for id in arg.substr(7).split(","):
				var front := st.origin + st.basis * Vector3(-4.2, 0.6, -6.2)
				_views.append(["auto_" + id, front, st.origin + Vector3(0, 0.1, 0), false, id])
		if arg.begins_with("--nitro="):
			NitroFlame.force_on = true
			for id in arg.substr(8).split(","):
				var back := st.origin + st.basis * Vector3(-3.0, 0.9, 4.6)
				_views.append(["nitro_" + id, back, st.origin + st.basis * Vector3(0, 0.3, 1.5), false, id])


func _process(_delta: float) -> void:
	var arena := get_parent()
	var cam: Camera3D = arena.camera
	cam.set_physics_process(false)
	cam.set_process(false)
	if _tacho.x >= 0.0:
		var tacho: Tachometer = arena.hud._tacho
		tacho.set_process(false)
		tacho._rpm = _tacho.x
		tacho._speed = _tacho.y
		arena.car.nitro = _tacho.z
		tacho._nitro_shown = _tacho.z
		tacho.queue_redraw()
	if _index >= _views.size():
		get_tree().quit()
		return
	var v: Array = _views[_index]
	if v.size() > 4 and _frames == 0:
		arena.spawn_car(v[4], arena.circuit.grid_transform())

	cam.far = 16000.0
	cam.fov = 60.0
	cam.global_position = v[1]
	cam.look_at(v[2], Vector3.UP)
	if _frames == 0:
		arena.city.load_around(v[1] if not v[3] else Vector3(0, 0, 9e6))
	var env: Environment = arena.world_env.environment
	env.fog_enabled = not v[3] and env.fog_enabled
	if v[3]:
		env.volumetric_fog_enabled = false
		env.fog_enabled = false
	_frames += 1
	if _frames == (14 if v.size() > 4 else 8):
		_frames = 0
		_index += 1
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_dir.path_join(v[0] + ".png"))
		print("[SNAPSHOT] ", v[0])
