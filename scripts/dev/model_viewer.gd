extends Node3D
## Vyvojovy prohlizec modelu:  godot --path . res://scenes/dev/model_viewer.tscn -- --view=res://cesta.glb --out=/slozka/prefix [--car=id]
## Vypise strom uzlu (s AABB) a ulozi snimky z nekolika uhlu. S --car pouzije CarModel (hotove auto).

var _out := ""
var _views := []
var _frame := 0
var _cam: Camera3D
var _center := Vector3.ZERO
var _radius := 3.0


func _ready() -> void:
	var path := ""
	var car_id := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--view="):
			path = arg.substr(7)
		elif arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--car="):
			car_id = arg.substr(6)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.35, 0.37, 0.42)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.4
	add_child(sun)
	var sun2 := DirectionalLight3D.new()
	sun2.rotation_degrees = Vector3(-30, -150, 0)
	sun2.light_energy = 0.6
	add_child(sun2)

	var model: Node3D
	if car_id != "":
		model = CarModel.build(car_id, true)
		add_child(model)
	else:
		model = (load(path) as PackedScene).instantiate()
		add_child(model)
		_print_tree(model, 0)
	var aabb := _total_aabb(model)
	print("CELKOVE AABB: ", aabb)
	_center = aabb.get_center()
	_radius = aabb.size.length() * 0.5
	_cam = Camera3D.new()
	_cam.fov = 35.0
	add_child(_cam)
	var d := _radius * 3.2
	_views = [
		["bok_plusX", Vector3(d, 0, 0)],
		["bok_minusX", Vector3(-d, 0, 0)],
		["predek_minusZ", Vector3(0, d * 0.15, -d)],
		["zad_plusZ", Vector3(0, d * 0.15, d)],
		["shora", Vector3(0.01, d, 0)],
		["tri_ctvrte", Vector3(d * 0.6, d * 0.35, -d * 0.7)],
	]


func _total_aabb(n: Node) -> AABB:
	var result := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.is_visible_in_tree() or m.mesh == null:
			continue
		var a: AABB = m.global_transform * m.mesh.get_aabb()
		if first:
			result = a
			first = false
		else:
			result = result.merge(a)
	return result


func _print_tree(n: Node, depth: int) -> void:
	var s := "  ".repeat(depth) + String(n.name)
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var m := n as MeshInstance3D
		var a: AABB = m.global_transform * m.mesh.get_aabb()
		var mats := []
		for i in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(i)
			mats.append(mat.resource_name if mat else "-")
		s += "  [mesh] c=%s size=%s mats=%s" % [_v(a.get_center()), _v(a.size), mats]
	elif n is Node3D and depth < 8:
		var aabb := _total_aabb(n)
		if aabb.size != Vector3.ZERO:
			s += "  {c=%s size=%s}" % [_v(aabb.get_center()), _v(aabb.size)]
	print(s)
	for c in n.get_children():
		_print_tree(c, depth + 1)


func _v(v: Vector3) -> String:
	return "(%.2f,%.2f,%.2f)" % [v.x, v.y, v.z]


func _process(_delta: float) -> void:
	_frame += 1
	if _views.is_empty():
		get_tree().quit()
		return
	var view: Array = _views[0]
	_cam.global_position = _center + view[1]
	var up := Vector3.UP if absf(view[1].normalized().y) < 0.9 else Vector3.FORWARD
	_cam.look_at(_center, up)
	if _frame % 4 == 0:
		_views.pop_front()
		await RenderingServer.frame_post_draw
		if _out != "":
			get_viewport().get_texture().get_image().save_png("%s_%s.png" % [_out, view[0]])
