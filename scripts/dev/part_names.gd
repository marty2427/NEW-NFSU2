extends SceneTree
## Vypise uzly modelu, jejichz jmeno pripomina dil karoserie (dvere, kapota, kufr, naraznik...).
func _init() -> void:
	var cfg := ConfigFile.new()
	cfg.load("res://data/modely_aut.cfg")
	var ids := OS.get_cmdline_user_args()
	for id in ids:
		var packed: PackedScene = load(cfg.get_value(id, "soubor"))
		var sc := packed.instantiate()
		printerr("== ", id)
		for n in sc.find_children("*", "", true, false):
			var nm := String(n.name).to_lower()
			for k in ["door", "hood", "bonnet", "trunk", "boot", "bumper", "fender", "tailgate", "capot", "porta", "puerta", "tur", "kofferraum", "glass", "window", "windshield", "sklo"]:
				if nm.contains(k):
					printerr("  ", sc.get_path_to(n), "  [", n.get_class(), "]")
					break
		sc.free()
	quit()
