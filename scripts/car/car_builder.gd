class_name CarBuilder
extends RefCounted
## Sklada vzhled auta z jednoduchych tvaru. Kazdy dil je samostatny uzel,
## aby mohl pri demolici odpadnout (nárazniky, kapota, dvere, kola...).

const BODY_BOTTOM := -0.45  # spodek karoserie vuci stredu auta
const MOUNT_Y := -0.15      # vyska uchyceni pruzin


## Vytvori kvadr, ktery je nahore uzsi (tvar kabiny, kapoty...).
## bottom/top = (sirka, delka), top_shift = posun horni plochy dopredu(-)/dozadu(+).
static func tapered_box(bottom: Vector2, top: Vector2, height: float, top_shift := 0.0) -> ArrayMesh:
	var bw := bottom.x * 0.5
	var bl := bottom.y * 0.5
	var tw := top.x * 0.5
	var tl := top.y * 0.5
	var y0 := -height * 0.5
	var y1 := height * 0.5
	# spodni rohy
	var b0 := Vector3(-bw, y0, -bl)
	var b1 := Vector3(bw, y0, -bl)
	var b2 := Vector3(bw, y0, bl)
	var b3 := Vector3(-bw, y0, bl)
	# horni rohy
	var t0 := Vector3(-tw, y1, -tl + top_shift)
	var t1 := Vector3(tw, y1, -tl + top_shift)
	var t2 := Vector3(tw, y1, tl + top_shift)
	var t3 := Vector3(-tw, y1, tl + top_shift)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0, 0, top_shift * 0.5)
	_quad(st, t0, t1, t2, t3, center)  # vrch
	_quad(st, b0, b1, b2, b3, center)  # spodek
	_quad(st, b0, b1, t1, t0, center)  # predek
	_quad(st, b2, b3, t3, t2, center)  # zad
	_quad(st, b1, b2, t2, t1, center)  # pravy bok
	_quad(st, b3, b0, t0, t3, center)  # levy bok
	return st.commit()


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, center: Vector3) -> void:
	var n := (b - a).cross(c - a).normalized()
	var mid := (a + b + c + d) * 0.25
	var outward := (mid - center).normalized()
	# Godot bere jako prední stranu trojuhelniky po smeru hodinovych rucicek.
	if n.dot(outward) > 0.0:
		var tmp := b
		b = d
		d = tmp
		n = -n
	n = -n
	for v in [a, b, c, a, c, d]:
		st.set_normal(n)
		st.set_uv(Vector2(v.x + v.z, v.y))
		st.add_vertex(v)


static func paint_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.35
	m.roughness = 0.3
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.08
	return m


static func simple_material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


static func emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func _part(parent: Node3D, part_name: String, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## Postavi cele auto. Vraci slovnik s odkazy na dily a materialy.
static func build(car: Node3D, t: CarTuning, is_player: bool) -> Dictionary:
	var W := t.rozmery.x
	var H := t.rozmery.y
	var L := t.rozmery.z
	var lower_h := H * 0.5
	var cabin_h := H * 0.48
	var lower_y := BODY_BOTTOM + lower_h * 0.5
	var lower_top := BODY_BOTTOM + lower_h

	var paint := paint_material(t.barva)
	var dark_paint := simple_material(t.barva.darkened(0.55), 0.4, 0.5)
	var glass := simple_material(Color(0.02, 0.03, 0.05), 0.9, 0.04)
	var plastic := simple_material(Color(0.04, 0.04, 0.045), 0.0, 0.7)
	var rubber := simple_material(Color(0.03, 0.03, 0.03), 0.0, 0.92)
	var rim := simple_material(Color(0.75, 0.75, 0.8), 1.0, 0.18)
	var head_mat := emissive_material(Color(1.0, 0.95, 0.85), 6.0)
	var tail_mat := emissive_material(Color(1.0, 0.05, 0.08), 2.5)
	var glow_color := Color.from_hsv(fposmod(t.barva.h + 0.5, 1.0), 0.9, 1.0)
	var underglow_mat := emissive_material(glow_color, 5.0)

	var visual := Node3D.new()
	visual.name = "Vzhled"
	car.add_child(visual)

	var parts := {}
	# Spodni cast karoserie (zkosena dopredu)
	parts["karoserie"] = _part(visual, "Karoserie", tapered_box(Vector2(W, L), Vector2(W - 0.08, L - 0.35), lower_h, 0.05), paint, Vector3(0, lower_y, 0))
	# Kabina - skla
	var cab_len := L * 0.46
	parts["kabina"] = _part(visual, "Kabina", tapered_box(Vector2(W - 0.16, cab_len), Vector2(W - 0.42, cab_len * 0.6), cabin_h, 0.12), glass, Vector3(0, lower_top + cabin_h * 0.5, L * 0.04))
	# Strecha
	parts["strecha"] = _part(visual, "Strecha", _box(Vector3(W - 0.44, 0.05, cab_len * 0.58)), paint, Vector3(0, lower_top + cabin_h + 0.01, L * 0.04 + 0.12))
	# Kapota a kufr
	parts["kapota"] = _part(visual, "Kapota", _box(Vector3(W - 0.14, 0.05, L * 0.27)), paint, Vector3(0, lower_top + 0.01, -L * 0.33))
	parts["kufr"] = _part(visual, "Kufr", _box(Vector3(W - 0.14, 0.05, L * 0.16)), paint, Vector3(0, lower_top + 0.01, L * 0.4))
	# Narazniky
	parts["naraznik_predni"] = _part(visual, "NaraznikPredni", _box(Vector3(W + 0.02, 0.26, 0.22)), dark_paint, Vector3(0, BODY_BOTTOM + 0.16, -L * 0.5 - 0.04))
	parts["naraznik_zadni"] = _part(visual, "NaraznikZadni", _box(Vector3(W + 0.02, 0.26, 0.22)), dark_paint, Vector3(0, BODY_BOTTOM + 0.16, L * 0.5 + 0.04))
	# Dvere
	parts["dvere_leve"] = _part(visual, "DvereLeve", _box(Vector3(0.05, lower_h * 0.82, L * 0.28)), paint, Vector3(-W * 0.5 - 0.01, lower_y + 0.02, -L * 0.02))
	parts["dvere_prave"] = _part(visual, "DverePrave", _box(Vector3(0.05, lower_h * 0.82, L * 0.28)), paint, Vector3(W * 0.5 + 0.01, lower_y + 0.02, -L * 0.02))
	# Spoiler
	var wing := Node3D.new()
	wing.name = "Spoiler"
	visual.add_child(wing)
	wing.position = Vector3(0, lower_top + 0.28, L * 0.45)
	_part(wing, "Kridlo", _box(Vector3(W - 0.1, 0.04, 0.32)), dark_paint, Vector3.ZERO)
	_part(wing, "DrzakL", _box(Vector3(0.05, 0.26, 0.12)), plastic, Vector3(-W * 0.32, -0.14, 0.02))
	_part(wing, "DrzakP", _box(Vector3(0.05, 0.26, 0.12)), plastic, Vector3(W * 0.32, -0.14, 0.02))
	parts["spoiler"] = wing

	# Svetla
	var lights_node := Node3D.new()
	lights_node.name = "Svetla"
	visual.add_child(lights_node)
	for side in [-1.0, 1.0]:
		_part(lights_node, "Predni%s" % ("L" if side < 0 else "P"), _box(Vector3(0.36, 0.1, 0.05)), head_mat, Vector3(side * (W * 0.5 - 0.26), lower_top - 0.12, -L * 0.5 + 0.06))
		_part(lights_node, "Zadni%s" % ("L" if side < 0 else "P"), _box(Vector3(0.42, 0.09, 0.05)), tail_mat, Vector3(side * (W * 0.5 - 0.28), lower_top - 0.1, L * 0.5 - 0.06))
	var beams: Array[SpotLight3D] = []
	for side in [-1.0, 1.0]:
		var spot := SpotLight3D.new()
		spot.name = "Reflektor%s" % ("L" if side < 0 else "P")
		spot.light_color = Color(1.0, 0.95, 0.85)
		spot.light_energy = 6.0
		spot.spot_range = 45.0
		spot.spot_angle = 28.0
		spot.spot_attenuation = 0.6
		spot.light_volumetric_fog_energy = 0.6
		spot.shadow_enabled = is_player and side > 0
		spot.position = Vector3(side * (W * 0.5 - 0.26), lower_top - 0.12, -L * 0.5 - 0.05)
		spot.rotation_degrees = Vector3(-4, 0, 0)
		lights_node.add_child(spot)
		beams.append(spot)

	# Neonove podsviceni (styl Underground)
	_part(visual, "Podsviceni", _box(Vector3(W - 0.3, 0.03, L - 0.8)), underglow_mat, Vector3(0, BODY_BOTTOM - 0.02, 0))
	var glow := OmniLight3D.new()
	glow.name = "PodsviceniSvetlo"
	glow.light_color = glow_color
	glow.light_energy = 2.2
	glow.omni_range = 3.6
	glow.omni_attenuation = 1.4
	glow.position = Vector3(0, BODY_BOTTOM - 0.15, 0)
	visual.add_child(glow)

	# Kola
	var wheel_nodes: Array[Node3D] = []
	var wheel_positions: Array[Vector3] = []
	var r := t.polomer_kola
	var wheel_x := W * 0.5 - 0.1
	var wheel_z := L * 0.5 - 0.78
	for i in 4:
		var front := i < 2
		var side := -1.0 if i % 2 == 0 else 1.0
		var mount := Vector3(side * wheel_x, MOUNT_Y, -wheel_z if front else wheel_z)
		wheel_positions.append(mount)
		var pivot := Node3D.new()
		pivot.name = "Kolo%d" % i
		visual.add_child(pivot)
		pivot.position = mount
		var spin := Node3D.new()
		spin.name = "Rotace"
		pivot.add_child(spin)
		var tire := CylinderMesh.new()
		tire.top_radius = r
		tire.bottom_radius = r
		tire.height = 0.3
		tire.radial_segments = 20
		var tire_mi := _part(spin, "Pneu", tire, rubber, Vector3.ZERO)
		tire_mi.rotation_degrees = Vector3(0, 0, 90)
		var hub := CylinderMesh.new()
		hub.top_radius = r * 0.62
		hub.bottom_radius = r * 0.62
		hub.height = 0.31
		hub.radial_segments = 6
		var hub_mi := _part(spin, "Disk", hub, rim, Vector3.ZERO)
		hub_mi.rotation_degrees = Vector3(0, 0, 90)
		wheel_nodes.append(pivot)

	return {
		"visual": visual,
		"parts": parts,
		"paint": paint,
		"dark_paint": dark_paint,
		"tail_mat": tail_mat,
		"head_mat": head_mat,
		"beams": beams,
		"underglow": glow,
		"underglow_mat": underglow_mat,
		"wheels": wheel_nodes,
		"wheel_positions": wheel_positions,
		"body_size": Vector3(W, H, L),
		"body_center_y": BODY_BOTTOM + H * 0.5,
	}
