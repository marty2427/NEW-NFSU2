extends SceneTree
## Kontrola planu mesta: uhly, delky, krizeni, okruh.  godot --headless -s res://scripts/dev/map_check.gd

func _seg_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var r := b - a
	var s := d - c
	var den := r.cross(s)
	if absf(den) < 1e-6:
		return false
	var t := (c - a).cross(s) / den
	var u := (c - a).cross(r) / den
	return t > 0.001 and t < 0.999 and u > 0.001 and u < 0.999

func _init() -> void:
	var m := CityMap.new()
	var total := 0.0
	for i in m.polylines.size():
		var l := CityMap.polyline_length(m.polylines[i])
		total += l
		var tl := CityMap.polyline_length(m.trimmed(i))
		if tl < 60.0:
			print("KRATKA ulice ", CityMap.EDGES[i][0], "-", CityMap.EDGES[i][1], " po zkraceni ", snappedf(tl, 1))
	print("ulic ", m.polylines.size(), ", krizovatek ", CityMap.NODES.size(), ", celkova delka ", int(total), " m")
	for id in CityMap.NODES:
		var arr: Array = m.node_edges[id]
		var min_gap := 999.0
		for k in arr.size():
			min_gap = minf(min_gap, rad_to_deg(fposmod(arr[(k + 1) % arr.size()].ang - arr[k].ang, TAU)))
		if min_gap < 40.0 or m.trim[id] > 24.0:
			print("krizovatka ", id, ": ", arr.size(), " ulic, nejmensi uhel ", snappedf(min_gap, 0.1), " st, zkraceni ", snappedf(m.trim[id], 0.1), " m")
	for i in m.polylines.size():
		for j in range(i + 1, m.polylines.size()):
			var shared := false
			for a in [CityMap.EDGES[i][0], CityMap.EDGES[i][1]]:
				if a == CityMap.EDGES[j][0] or a == CityMap.EDGES[j][1]:
					shared = true
			var pi := m.polylines[i]
			var pj := m.polylines[j]
			for x in pi.size() - 1:
				for y in pj.size() - 1:
					if _seg_cross(pi[x], pi[x + 1], pj[y], pj[y + 1]):
						print("KRIZENI ", CityMap.EDGES[i], " x ", CityMap.EDGES[j], " (spolecna krizovatka: ", shared, ")")
	var c := m.circuit_polyline()
	var clen := 0.0
	for i in c.size():
		clen += c[i].distance_to(c[(i + 1) % c.size()])
	print("okruh: ", c.size(), " bodu, delka ", int(clen), " m")
	for k in CityMap.CIRCUIT.size():
		var id: String = CityMap.CIRCUIT[k]
		var e_in := m.find_edge(CityMap.CIRCUIT[posmod(k - 1, CityMap.CIRCUIT.size())], id)
		var e_out := m.find_edge(id, CityMap.CIRCUIT[(k + 1) % CityMap.CIRCUIT.size()])
		var d_in := Vector2.ZERO
		var d_out := Vector2.ZERO
		for ne in m.node_edges[id]:
			if ne.e == e_in:
				d_in = -ne.out
			if ne.e == e_out:
				d_out = ne.out
		print("  zatacka ", id, ": ", int(rad_to_deg(d_in.angle_to(d_out))), " st")
	var lot := m.lot_polygon(CityMap.SIDEWALK)
	var area := 0.0
	for i in lot.size():
		area += lot[i].cross(lot[(i + 1) % lot.size()]) * 0.5
	print("treninkova plocha: ", lot.size(), " bodu, ", int(absf(area)), " m2")
	quit()
