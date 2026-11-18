extends SceneTree
func _init() -> void:
	for id in OS.get_cmdline_user_args():
		var m := CarModel.build(id, false)
		root.add_child(m)
		var seen := {}
		for node in m.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if not (mi.mesh is ArrayMesh):
				continue
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s)
				var orig := mi.mesh.surface_get_material(s)
				var key := "%s | %s" % [orig.resource_name if orig else "-", mat.resource_name if mat else "-"]
				var tr := ""
				if mat is BaseMaterial3D:
					tr = "transp=%d a=%.2f" % [(mat as BaseMaterial3D).transparency, (mat as BaseMaterial3D).albedo_color.a]
				if not seen.has(key):
					seen[key] = true
					printerr(id, ": ", key, "  ", tr, "  (", mi.name, ")")
	quit()
