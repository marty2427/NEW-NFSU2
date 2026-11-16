class_name Circuit
extends Node3D
## Mestsky okruh: trasa po ulicich z planu mesta, svitici sipky v zatackach,
## startovni brana a mereni casu kola (prujezdy krizovatkami musi jit po poradku).

signal lap_finished(time: float, best: float)
signal checkpoint_passed(index: int, total: int)

const GATE_RADIUS := 26.0

var map: CityMap
var route := PackedVector3Array()       # osa okruhu (uzavrena lomena cara)
var checkpoints := PackedVector3Array() # krizovatky okruhu v poradi jizdy
var start_xf := Transform3D()
var car: Node3D
var lap_time := 0.0
var best_time := 0.0
var last_time := 0.0
var lap_count := 0
var running := false
var next_cp := 0

var _markers: Array[Node3D] = []


func setup(city_map: CityMap) -> void:
	map = city_map
	for p in map.circuit_polyline():
		route.append(CityMap.to3(p))
	for id in CityMap.CIRCUIT:
		checkpoints.append(CityMap.to3(CityMap.NODES[id]))
	# Start: na prvnim useku, 60 m za prvni krizovatkou
	var e := map.find_edge(CityMap.CIRCUIT[0], CityMap.CIRCUIT[1])
	var pl := map.polylines[e].duplicate()
	if CityMap.EDGES[e][0] != CityMap.CIRCUIT[0]:
		pl.reverse()
	var cut := CityMap.cut_polyline(pl, 60.0, 0.0)
	var dir := (cut[1] - cut[0]).normalized()
	start_xf = Transform3D(Basis.looking_at(CityMap.to3(dir), Vector3.UP), CityMap.to3(cut[0], 0.6))
	_build_visuals(map.half_width[e])


## Zavodni stopa pro pocitacoveho jezdce: rohy (najizdi se zvenku) a polomer oblouku pro kazdy roh.
## margin = jak daleko od obrubniku se ma auto drzet.
func racing_line(margin := 2.0) -> Dictionary:
	var corners := PackedVector3Array()
	var radii := PackedFloat32Array()
	var n := CityMap.CIRCUIT.size()
	# Udaje o kazde krizovatce okruhu
	var info := []
	for k in n:
		var id: String = CityMap.CIRCUIT[k]
		var e_in := map.find_edge(CityMap.CIRCUIT[posmod(k - 1, n)], id)
		var e_out := map.find_edge(id, CityMap.CIRCUIT[(k + 1) % n])
		var d_in := Vector2.ZERO
		var d_out := Vector2.ZERO
		for ne in map.node_edges[id]:
			if ne.e == e_in:
				d_in = -ne.out
			if ne.e == e_out:
				d_out = ne.out
		var theta := absf(d_in.angle_to(d_out))
		var w := minf(map.half_width[e_in], map.half_width[e_out])
		var wide := minf(w - margin - 0.5, 5.0) * clampf(theta / deg_to_rad(60.0), 0.0, 1.0)
		var radius := clampf((w - margin + wide) / maxf(1.0 - cos(theta * 0.5), 0.001), 8.0, 160.0)
		var p: Vector2 = CityMap.NODES[id]
		if theta > 0.05:
			p -= (d_out - d_in).normalized() * wide / cos(theta * 0.5)
		info.append({"p": p, "r": radius, "t": radius * tan(theta * 0.5)})
	for k in n:
		var a: String = CityMap.CIRCUIT[k]
		var b: String = CityMap.CIRCUIT[(k + 1) % n]
		corners.append(CityMap.to3(info[k].p))
		radii.append(info[k].r)
		var e := map.find_edge(a, b)
		var pl := map.polylines[e].duplicate()
		if CityMap.EDGES[e][0] != a:
			pl.reverse()
		# Body oblouku ulice; ty tesne u krizovatek se vynechaji, aby se zatacka dala najet zesiroka
		var keep_a: float = info[k].t * 1.4 + 10.0
		var keep_b: float = info[(k + 1) % n].t * 1.4 + 10.0
		for i in range(1, pl.size() - 1):
			if pl[i].distance_to(pl[0]) > keep_a and pl[i].distance_to(pl[pl.size() - 1]) > keep_b:
				corners.append(CityMap.to3(pl[i]))
				radii.append(250.0)
	return {"corners": corners, "radii": radii}


## Misto pro auto pred startovni carou.
func grid_transform() -> Transform3D:
	return Transform3D(start_xf.basis, start_xf.origin + start_xf.basis.z * 25.0)


func _mat(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	if energy > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = energy
	return m


func _build_visuals(start_half_width: float) -> void:
	var font: Font = load("res://assets/fonts/RussoOne-Regular.ttf")
	var n := CityMap.CIRCUIT.size()
	for k in n:
		var id: String = CityMap.CIRCUIT[k]
		var e_in := map.find_edge(CityMap.CIRCUIT[posmod(k - 1, n)], id)
		var e_out := map.find_edge(id, CityMap.CIRCUIT[(k + 1) % n])
		var d_in := Vector2.ZERO
		var d_out := Vector2.ZERO
		for ne in map.node_edges[id]:
			if ne.e == e_in:
				d_in = -ne.out
			if ne.e == e_out:
				d_out = ne.out
		var p := CityMap.to3(CityMap.NODES[id])
		var turn := d_in.angle_to(d_out)            # + = doprava (pri pohledu shora)
		var size: float = map.trim[id] + 6.0
		# Svitici sipky na vnejsi strane zatacky (bez kolize), celem k prijizdejicimu autu
		if absf(turn) > deg_to_rad(20.0):
			var board := Node3D.new()
			add_child(board)
			board.position = p + CityMap.to3(d_in) * size
			board.basis = Basis.looking_at(CityMap.to3(d_in), Vector3.UP)
			var label := Label3D.new()
			label.font = font
			label.text = "› › › › ›" if turn > 0.0 else "‹ ‹ ‹ ‹ ‹"
			label.font_size = 220
			label.pixel_size = 0.011
			label.modulate = Color(2.2, 1.6, 0.1, 0.9)
			label.outline_modulate = Color(0.4, 0.2, 0.0, 0.6)
			label.outline_size = 20
			label.shaded = false
			label.double_sided = false
			label.position = Vector3(0, 2.2, 0)
			board.add_child(label)
		# Svitici sloupek u krizovatky, kterou ma hrac projet jako dalsi
		var marker := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.3
		cyl.bottom_radius = 0.3
		cyl.height = 7.0
		marker.mesh = cyl
		marker.material_override = _mat(Color(0.2, 1.0, 0.4), 4.0)
		var inner := (d_out - d_in)
		if inner.length() < 0.2:
			inner = CityMap.right_of(d_in)
		marker.position = p + CityMap.to3(inner.normalized()) * (size + 2.0) + Vector3(0, 3.5, 0)
		add_child(marker)
		_markers.append(marker)

	# Startovni / cilova brana
	var gate := Node3D.new()
	add_child(gate)
	gate.transform = Transform3D(start_xf.basis, start_xf.origin - Vector3(0, 0.6, 0))
	var hw := start_half_width
	for side in [-1.0, 1.0]:
		var pole := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.5, 7.5, 0.5)
		pole.mesh = pb
		pole.material_override = _mat(Color(0.05, 0.05, 0.06), 0.0)
		pole.position = Vector3(side * (hw + 1.2), 3.75, 0)
		gate.add_child(pole)
	var beam := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(hw * 2.0 + 2.9, 1.5, 0.5)
	beam.mesh = bb
	beam.material_override = _mat(Color(0.05, 0.05, 0.06), 0.0)
	beam.position = Vector3(0, 7.0, 0)
	gate.add_child(beam)
	for face in [1.0, -1.0]:
		var txt := Label3D.new()
		txt.font = font
		txt.text = "START  ·  CÍL"
		txt.font_size = 200
		txt.pixel_size = 0.0065
		txt.modulate = Color(0.3, 2.2, 2.6)
		txt.shaded = false
		txt.position = Vector3(0, 7.0, 0.27 * face)
		txt.rotation.y = 0.0 if face > 0 else PI
		gate.add_child(txt)
	# Sachovnicova cara na zemi
	var cells := int(hw * 2.0)
	for i in cells:
		for j in 2:
			if (i + j) % 2 == 0:
				var q := MeshInstance3D.new()
				var qb := BoxMesh.new()
				qb.size = Vector3(1.0, 0.02, 1.0)
				q.mesh = qb
				q.material_override = _mat(Color(0.9, 0.9, 0.9), 0.2)
				q.position = Vector3(-hw + 0.5 + i, 0.035, -0.5 + j)
				gate.add_child(q)


func _physics_process(delta: float) -> void:
	if car == null or not is_instance_valid(car) or map == null:
		return
	if running:
		lap_time += delta
	var n := checkpoints.size()
	var p := car.global_position
	# Start / cil: prujezd carou ve smeru jizdy
	var local := start_xf.affine_inverse() * p
	if absf(local.x) < 13.0 and absf(local.z) < 3.5 and car.linear_velocity.dot(-start_xf.basis.z) > 2.0:
		if not running:
			running = true
			lap_time = 0.0
			next_cp = 1
		elif next_cp == 0:
			last_time = lap_time
			if best_time <= 0.0 or lap_time < best_time:
				best_time = lap_time
			lap_count += 1
			lap_finished.emit(last_time, best_time)
			lap_time = 0.0
			next_cp = 1
	# Prujezdy krizovatkami v poradi
	if running:
		var cp := checkpoints[next_cp]
		if Vector2(p.x - cp.x, p.z - cp.z).length() < GATE_RADIUS:
			next_cp = (next_cp + 1) % n
			checkpoint_passed.emit(next_cp, n)
	for i in _markers.size():
		_markers[i].visible = (not running and i == 1) or (running and i == next_cp)


func reset() -> void:
	running = false
	lap_time = 0.0
	next_cp = 0
