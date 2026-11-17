class_name Circuit
extends Node3D
## Mestsky okruh: trasa po ulicich z planu mesta, svitici sipky v zatackach,
## startovni brana a mereni casu kola (prujezdy krizovatkami musi jit po poradku).

signal lap_finished(time: float, best: float)
signal checkpoint_passed(index: int, total: int)

const GATE_RADIUS := 26.0

var map: CityMap
var index := 0                          # ktery okruh z planu mesta
var title := ""
var length := 0.0
var route := PackedVector3Array()       # osa okruhu (uzavrena lomena cara)
var checkpoints := PackedVector3Array() # krizovatky okruhu v poradi jizdy
var edge_set := {}                      # ulice okruhu (pro minimapu)
var start_xf := Transform3D()
var car: Node3D
var lap_time := 0.0
var best_time := 0.0
var last_time := 0.0
var lap_count := 0
var running := false
var next_cp := 0

var _markers: Array[Node3D] = []
var _items: Array = []                  # [[ulice, vpred]]
var _grid_xf := Transform3D()


func setup(city_map: CityMap, circuit_index := 0) -> void:
	map = city_map
	index = circuit_index
	var info: Dictionary = map.circuits[index]
	title = info.nazev
	length = info.delka
	_items = info.ulice
	route = map.circuit_polyline3(index)
	for item in _items:
		edge_set[item[0]] = true
		var nid := _from_node(item)
		checkpoints.append(CityMap.to3(map.nodes[nid], map.node_y[nid]))
	# Start: na prvnim useku kousek za prvni krizovatkou
	var e: int = _items[0][0]
	var total: float = map.stations[e][map.stations[e].size() - 1]
	var dist := minf(map.trim[_from_node(_items[0])] + 45.0, total * 0.45)
	start_xf = _road_transform(e, _items[0][1], dist)
	_grid_xf = _road_transform(e, _items[0][1], maxf(dist - 25.0, map.trim[_from_node(_items[0])] + 2.0))
	_build_visuals(map.half_width[e])


## Poloha a smer na ulici e ve vzdalenosti dist od zacatku jizdy (forward = jede se od "a" k "b").
func _road_transform(e: int, forward: bool, dist: float) -> Transform3D:
	var pl := map.polylines[e].duplicate()
	var total: float = map.stations[e][map.stations[e].size() - 1]
	if not forward:
		pl.reverse()
	var pd := CityMap.point_at(pl, dist)
	var s := dist if forward else total - dist
	var s2 := s + (3.0 if forward else -3.0)
	var y := map.edge_height(e, s)
	var slope := (map.edge_height(e, s2) - y) / 3.0
	var dir2: Vector2 = pd[1]
	var dir3 := Vector3(dir2.x, slope, dir2.y).normalized()
	return Transform3D(Basis.looking_at(dir3, Vector3.UP), CityMap.to3(pd[0], y + 0.6))


func _from_node(item: Array) -> int:
	return map.edge_a[item[0]] if item[1] else map.edge_b[item[0]]


## Smery v krizovatce k: [smer prijezdu, smer odjezdu, sirka].
func _node_dirs(k: int) -> Array:
	var n := _items.size()
	var item_in: Array = _items[posmod(k - 1, n)]
	var item_out: Array = _items[k]
	var id := _from_node(item_out)
	var d_in := Vector2.RIGHT
	var d_out := Vector2.RIGHT
	for ne in map.node_edges[id]:
		if ne.e == item_in[0]:
			d_in = -ne.out
		if ne.e == item_out[0]:
			d_out = ne.out
	return [d_in, d_out, minf(map.half_width[item_in[0]], map.half_width[item_out[0]]), id]


## Zavodni stopa pro pocitacoveho jezdce: rohy (najizdi se zvenku) a polomer oblouku pro kazdy roh.
## margin = jak daleko od obrubniku se ma auto drzet.
func racing_line(margin := 2.0) -> Dictionary:
	var corners := PackedVector3Array()
	var radii := PackedFloat32Array()
	var n := _items.size()
	var info := []
	for k in n:
		var nd := _node_dirs(k)
		var d_in: Vector2 = nd[0]
		var d_out: Vector2 = nd[1]
		var w: float = nd[2]
		var theta := absf(d_in.angle_to(d_out))
		var wide := minf(w - margin - 0.5, 5.0) * clampf(theta / deg_to_rad(60.0), 0.0, 1.0)
		var radius := clampf((w - margin + wide) / maxf(1.0 - cos(theta * 0.5), 0.001), 8.0, 160.0)
		var p: Vector2 = map.nodes[nd[3]]
		if theta > 0.05:
			p -= (d_out - d_in).normalized() * wide / cos(theta * 0.5)
		info.append({"p": p, "r": radius, "t": radius * tan(theta * 0.5)})
	for k in n:
		corners.append(CityMap.to3(info[k].p))
		radii.append(info[k].r)
		var pl := map.polylines[_items[k][0]].duplicate()
		if not _items[k][1]:
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
	return _grid_xf


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
	var n := _items.size()
	for k in n:
		var nd := _node_dirs(k)
		var d_in: Vector2 = nd[0]
		var d_out: Vector2 = nd[1]
		var id: int = nd[3]
		var p := CityMap.to3(map.nodes[id], map.node_y[id])
		var turn := d_in.angle_to(d_out)            # + = doprava (pri pohledu shora)
		var size: float = map.trim[id] + 6.0
		# Svitici sipky na vnejsi strane zatacky (bez kolize), celem k prijizdejicimu autu
		if absf(turn) > deg_to_rad(28.0):
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
			label.visibility_range_end = 450.0
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
	if absf(local.x) < 13.0 and absf(local.z) < 3.5 and absf(local.y) < 5.0 and car.linear_velocity.dot(-start_xf.basis.z) > 2.0:
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
		if Vector2(p.x - cp.x, p.z - cp.z).length() < GATE_RADIUS and absf(p.y - cp.y) < 9.0:
			next_cp = (next_cp + 1) % n
			checkpoint_passed.emit(next_cp, n)
	for i in _markers.size():
		_markers[i].visible = (not running and i == 1) or (running and i == next_cp)


func reset() -> void:
	running = false
	lap_time = 0.0
	next_cp = 0
