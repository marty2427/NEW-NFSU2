extends SceneTree
## Kontrola planu mesta: delky, uhly, plochy, okruhy.  godot --headless --path . -s res://scripts/dev/map_check.gd

func _init() -> void:
	var m := CityMap.new()
	var total := 0.0
	var problems := 0
	for e in m.polylines.size():
		total += CityMap.polyline_length(m.polylines[e])
		var tl := CityMap.polyline_length(m.trimmed(e))
		if tl < 10.0:
			problems += 1
			print("KRATKA ulice ", e, " po zkraceni ", snappedf(tl, 0.1), " m u ", m.polylines[e][0])
	print("krizovatek ", m.nodes.size(), ", ulic ", m.polylines.size(), ", celkova delka ", snappedf(total / 1000.0, 0.1), " km")
	for id in m.nodes.size():
		var arr: Array = m.node_edges[id]
		for k in arr.size():
			var gap := rad_to_deg(m.corner_angle(id, k))
			if gap < 42.0:
				problems += 1
				print("OSTRY UHEL ", snappedf(gap, 0.1), " st u ", m.nodes[id])
	for lot: Dictionary in m.lots:
		var poly := m.lot_polygon(lot, 0.0)
		var ok := Geometry2D.triangulate_polygon(poly).size() > 0
		var inside := Geometry2D.is_point_in_polygon(lot.stred, poly)
		if not ok:
			problems += 1
			print("PLOCHA ", lot.typ, " u ", lot.stred, ": nejde vyplnit (", poly.size(), " bodu)")
		elif not inside and lot.typ != "reka":
			print("plocha ", lot.typ, " u ", lot.stred, ": stred lezi mimo obrys")
	for c: Dictionary in m.circuits:
		var ok := true
		var n: int = c.ulice.size()
		for k in n:
			var a: Array = c.ulice[k]
			var b: Array = c.ulice[(k + 1) % n]
			var end_node := m.edge_b[a[0]] if a[1] else m.edge_a[a[0]]
			var start_node := m.edge_a[b[0]] if b[1] else m.edge_b[b[0]]
			ok = ok and end_node == start_node
		print("okruh ", c.nazev, ": ", snappedf(c.delka / 1000.0, 0.1), " km, ", n, " ulic, navazuje: ", ok)
		if not ok:
			problems += 1
	print("problemu: ", problems)
	quit()
