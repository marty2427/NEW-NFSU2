extends Node3D
## Vypise vyskovy profil povrchu okolo bodu:  -- --bod=x,z [--r=12]
func _ready() -> void:
	var city := CityBuilder.new()
	add_child(city)
	city.build()
	for i in 3:
		await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var map := city.map
	var c := Vector2.ZERO
	var r := 12.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bod="):
			var parts := arg.substr(6).split(",")
			c = Vector2(float(parts[0]), float(parts[1]))
		if arg.begins_with("--r="):
			r = float(arg.substr(4))
	var ne := map.nearest_edge(c, 100.0)
	printerr("nejblizsi ulice %d (%s) w=%.1f vzd %.1f s=%.1f y=%.2f" % [ne.e, map.edge_class[ne.e], map.half_width[ne.e], ne.dist, ne.s, ne.y])
	for id in map.nodes.size():
		if map.nodes[id].distance_to(c) < 60.0:
			var arr: Array = map.node_edges[id]
			var info := []
			for k in arr.size():
				info.append("e%d %s ang%.0f" % [arr[k].e, "od" if arr[k].start else "do", rad_to_deg(arr[k].ang)])
			printerr("krizovatka %d u %s y=%.2f trim=%.1f: %s" % [id, map.nodes[id], map.node_y[id], map.trim[id], ", ".join(info)])
			for k in arr.size():
				var key := "%d:%d" % [id, arr[k].e]
				var e: int = arr[k].e
				var ends: Array = city._node_ends.get(key, [])
				var p0 := map.corner(id, k, 0.0)
				var td := map.trimmed_data(e)
				printerr("   ulice e%d w=%.1f delka %.0f trida %s | konec L %s P %s y=%.2f | roh P0 %s y=%.2f | trimmed %d bodu s0=%.1f y0=%.2f s1=%.1f y1=%.2f" % [e, map.half_width[e], map.stations[e][map.stations[e].size()-1], map.edge_class[e], ends[0] if ends.size() else "-", ends[1] if ends.size() else "-", ends[2] if ends.size() else 0.0, p0, city._corner_height(id, k, p0), td.p.size(), td.s[0] if td.s.size() else -1.0, td.y[0] if td.y.size() else 0.0, td.s[td.s.size()-1] if td.s.size() else -1.0, td.y[td.y.size()-1] if td.y.size() else 0.0])
	var step := r / 10.0
	var y0: float = ne.y
	for iz in range(-10, 11):
		var line := ""
		for ix in range(-10, 11):
			var q := c + Vector2(ix, iz) * step
			var from := Vector3(q.x, y0 + 4.0, q.y)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 10.0))
			if hit:
				var tag := "v" if hit.collider.name == "Vozovka" else "z"
				line += "%+5.2f%s" % [hit.position.y - y0, tag]
			else:
				line += "  ---- "
		printerr(line)
	get_tree().quit()
