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
	var st: Transform3D = arena.circuit.grid_transform()
	var lot := Vector3.ZERO
	for p in arena.city.map.lot_polygon(0.0):
		lot += CityMap.to3(p)
	lot /= float(arena.city.map.lot_polygon(0.0).size())
	var all := [
		["mapa", Vector3(0, 1750, 1), Vector3(0, 0, 0), true],
		["start", st.origin + st.basis * Vector3(0.5, 2.2, 7.5), st.origin + st.basis * Vector3(0, 0.6, -20), false],
		["plocha", lot + Vector3(120, 90, 160), lot, false],
		["centrum_vyska", Vector3(20, 160, 200), Vector3(20, 0, 10), false],
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
		all.append(["okruh%d" % k, p + Vector3(0, 1.8, 0) + d.cross(Vector3.UP) * 2.0, p + d * 40.0 + Vector3(0, 2.5, 0), false])
	for v in all:
		if _only.is_empty() or _only.has(v[0]):
			_views.append(v)


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
		tacho.queue_redraw()
	if _index >= _views.size():
		get_tree().quit()
		return
	var v: Array = _views[_index]
	cam.far = 6000.0
	cam.fov = 60.0
	cam.global_position = v[1]
	cam.look_at(v[2], Vector3.UP)
	var env: Environment = arena.world_env.environment
	env.fog_enabled = not v[3] and env.fog_enabled
	if v[3]:
		env.volumetric_fog_enabled = false
		env.fog_enabled = false
	_frames += 1
	if _frames == 8:
		_frames = 0
		_index += 1
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_dir.path_join(v[0] + ".png"))
		print("[SNAPSHOT] ", v[0])
