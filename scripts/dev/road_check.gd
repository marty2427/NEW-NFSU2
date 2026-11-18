extends Node3D
## Kontrola jizdni plochy:  godot --headless --path . res://scenes/dev/road_check.tscn [-- --ulic=N]
## Projde ulice i plochy krizovatek a hleda:
##  - SCHOD: sousedni body povrchu (0,7 m od sebe) se vyskove lisi o vic nez 9 cm,
##  - PREKAZKA: vodorovny paprsek 35 cm nad silnici do neceho narazi (zed, vystouply chodnik).

var city: CityBuilder


func _ready() -> void:
	city = CityBuilder.new()
	add_child(city)
	city.build()
	for i in 3:
		await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var map := city.map
	var limit: int = map.polylines.size()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ulic="):
			limit = int(arg.substr(7))
	var steps := []
	var walls := []
	var wet := []                 # povrch silnice pod hladinou vody (auto by jelo "pod vodou")
	var samples := 0
	var ground := func(q: Vector2, y: float) -> float:
		var from := Vector3(q.x, y + 2.5, q.y)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 6.0))
		return hit.position.y if hit else -999.0
	for e in limit:
		var pl := map.polylines[e]
		var total: float = map.stations[e][map.stations[e].size() - 1]
		var w: float = map.half_width[e]
		var s := 0.0
		while s <= total:
			var pd := CityMap.point_at(pl, s)
			var p: Vector2 = pd[0]
			var d: Vector2 = pd[1]
			var r := CityMap.right_of(d)
			var y := map.edge_height(e, s)
			var under := map.is_under(e, s)
			# povrch napric vozovkou po 0,7 m
			var prev := -999.0
			var lat := -w + 0.6
			while lat <= w - 0.6:
				var q: Vector2 = p + r * lat
				var h: float = ground.call(q, y)
				samples += 1
				if h > -900.0 and h < map.water_level + 0.3:
					wet.append([e, s, q, h])
				if prev > -900.0 and h > -900.0 and absf(h - prev) > 0.09 and not under:
					steps.append([e, s, q, h - prev])
				prev = h
				lat += 0.7
			# podel ulice (0,7 m dopredu) ve trech pruzich
			for lf in [-0.7, 0.0, 0.7]:
				var q1: Vector2 = p + r * float(lf) * w
				var q2: Vector2 = q1 + d * 0.7
				var h1: float = ground.call(q1, y)
				var h2: float = ground.call(q2, y)
				if h1 > -900.0 and h2 > -900.0 and absf(h2 - h1) > 0.09 + 0.7 * 0.25 and not under:
					steps.append([e, s, q1, h2 - h1])
			s += 3.0
		# vodorovne paprsky 35 cm nad povrchem
		s = 0.0
		while s < total - 0.5:
			var s2 := minf(s + 5.0, total)
			var a := CityMap.point_at(pl, s)[0] as Vector2
			var b := CityMap.point_at(pl, s2)[0] as Vector2
			var dd: Vector2 = (b - a).normalized()
			for lf in [-0.7, 0.0, 0.7]:
				var off: Vector2 = CityMap.right_of(dd) * float(lf) * w
				var ha: float = ground.call(a + off, map.edge_height(e, s))
				var hb: float = ground.call(b + off, map.edge_height(e, s2))
				if ha < -900.0 or hb < -900.0:
					continue
				var q := PhysicsRayQueryParameters3D.create(Vector3(a.x + off.x, ha + 0.35, a.y + off.y), Vector3(b.x + off.x, hb + 0.35, b.y + off.y))
				q.hit_back_faces = true
				var hit := space.intersect_ray(q)
				if hit:
					walls.append([e, s, Vector2(hit.position.x, hit.position.z), hit.collider.name])
			s = s2
	var cells_s := {}
	for st in steps:
		var ck := Vector2i(int(st[2].x / 25.0), int(st[2].y / 25.0))
		if not cells_s.has(ck) or absf(st[3]) > absf(cells_s[ck][3]):
			cells_s[ck] = st
	var cells_w := {}
	for wl in walls:
		cells_w[Vector2i(int(wl[2].x / 25.0), int(wl[2].y / 25.0))] = wl
	printerr("[KONTROLA] vzorku %d | SCHODY: %d bodu na %d mistech | PREKAZKY: %d paprsku na %d mistech" % [samples, steps.size(), cells_s.size(), walls.size(), cells_w.size()])
	var n := 0
	var worst: Array = cells_s.values()
	worst.sort_custom(func(a, b): return absf(a[3]) > absf(b[3]))
	var hist := {}
	for st in worst:
		var b := snappedf(absf(st[3]), 0.05)
		hist[b] = hist.get(b, 0) + 1
	printerr("  rozlozeni nejvetsich skoku (m: mist): ", hist)
	for st: Array in worst:
		if n < 12:
			printerr("  SCHOD ulice %d (%s) s=%.0f u (%.0f, %.0f) skok %.2f m" % [st[0], map.edge_class[st[0]], st[1], st[2].x, st[2].y, st[3]])
		n += 1
	n = 0
	for k in cells_w:
		var wl: Array = cells_w[k]
		if n < 12:
			printerr("  PREKAZKA ulice %d (%s) s=%.0f u (%.0f, %.0f) %s" % [wl[0], map.edge_class[wl[0]], wl[1], wl[2].x, wl[2].y, wl[3]])
		n += 1
	printerr("[KONTROLA] POD VODOU: %d bodu" % wet.size())
	for i in mini(wet.size(), 8):
		printerr("  VODA ulice %d (%s) u (%.0f, %.0f) vyska %.2f" % [wet[i][0], map.edge_class[wet[i][0]], wet[i][2].x, wet[i][2].y, wet[i][3]])
	get_tree().quit()
