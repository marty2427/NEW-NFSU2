extends SceneTree
## Vyvojovy vypis: pocty vrcholu karoserie aut a cas pripravy dat pro promackliny.
func _init() -> void:
	for id in ["octavia", "mustang", "silvia", "skyline", "rx7", "supra", "impreza", "m3"]:
		var m := CarModel.build(id, false)
		root.add_child(m)
		var verts := 0
		var surfs := 0
		var meshes := 0
		var t0 := Time.get_ticks_usec()
		for node in m.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			var skip := false
			for w in m.wheels:
				if w.is_ancestor_of(mi):
					skip = true
			if skip or mi.mesh == null:
				continue
			meshes += 1
			for s in mi.mesh.get_surface_count():
				var a: Array = mi.mesh.surface_get_arrays(s)
				verts += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
				surfs += 1
		var t1 := Time.get_ticks_usec()
		printerr("%s: siti %d, ploch %d, vrcholu %d, cteni %.0f ms" % [id, meshes, surfs, verts, (t1 - t0) / 1000.0])
		m.queue_free()
	quit()
