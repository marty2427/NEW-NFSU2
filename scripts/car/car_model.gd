class_name CarModel
extends Node3D
## Nacte 3D model auta (.glb) podle data/modely_aut.cfg a pripravi ho pro hru:
## kola na otocnych uzlech, materialy (lak, skla, svetla), svetlomety a dily pro demolici.
## Souradnice vystupu: predek auta smeruje k -Z, zem je v y = 0.

const CONFIG_PATH := "res://data/modely_aut.cfg"

var car_id := ""
## Otocne uzly kol (natoceni + odpruzeni), poradi: PL, PP, ZL, ZP
var wheels: Array[Node3D] = []
## Uzly, ktere se toci s kolem
var wheel_spins: Array[Node3D] = []
## Stred kola v klidu (souradnice auta)
var wheel_rest: Array[Vector3] = []
var wheel_radius := 0.33
## Dily pro demolici: nazev -> uzel
var parts := {}
## Obrys karoserie bez kol (souradnice auta)
var body_aabb := AABB(Vector3(-0.9, 0.2, -2.3), Vector3(1.8, 1.2, 4.6))
var paint: StandardMaterial3D
var tail_mat: StandardMaterial3D
var head_mat: StandardMaterial3D
var beams: Array[SpotLight3D] = []
var underglow: OmniLight3D

static var _shared := {}


static func build(id: String, is_player: bool, color := Color(0.1, 0.3, 0.8)) -> CarModel:
	var m := CarModel.new()
	m.name = "Vzhled"
	m.car_id = id
	m._build(is_player, color)
	return m


static func has_model(id: String) -> bool:
	var cfg := ConfigFile.new()
	return cfg.load(CONFIG_PATH) == OK and cfg.has_section(id)


func _build(is_player: bool, color: Color) -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK or not cfg.has_section(car_id):
		push_error("Model auta '%s' neni v %s" % [car_id, CONFIG_PATH])
		return
	var c := func(key: String, def: Variant) -> Variant: return cfg.get_value(car_id, key, def)

	var packed := load(c.call("soubor", "")) as PackedScene
	if packed == null:
		push_error("Nelze nacist model auta '%s'" % car_id)
		return
	var scale_f: float = c.call("meritko", 1.0)
	var holder := Node3D.new()
	holder.name = "Model"
	holder.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(c.call("otoceni", 0.0))).scaled(Vector3.ONE * scale_f), Vector3.ZERO)
	add_child(holder)
	var scene := packed.instantiate()
	holder.add_child(scene)

	for n in c.call("skryt", []):
		var node := _find(scene, n)
		if node:
			node.get_parent().remove_child(node)
			node.free()

	# Opravy modelu: zavrit otevrene dvere/kapotu apod.
	var xforms: Dictionary = c.call("transformace", {})
	for n in xforms:
		var node := _find(scene, n) as Node3D
		if node:
			node.transform = xforms[n]
	for n in c.call("reset_deti", []):
		var node := _find(scene, n)
		if node:
			for child in node.get_children():
				if child is Node3D:
					(child as Node3D).transform = Transform3D.IDENTITY

	wheel_radius = float(c.call("polomer_kola", 0.33)) * scale_f
	_setup_wheels(scene, holder, c)
	# Zem do y = 0
	var ground := wheel_rest[0].y - wheel_radius if not wheel_rest.is_empty() else 0.0
	holder.position.y -= ground
	for i in wheels.size():
		wheels[i].position.y -= ground
		wheel_rest[i].y -= ground

	_setup_materials(scene, c, color)
	_setup_lights(holder, c, is_player)
	var part_map: Dictionary = c.call("dily", {})
	for key in part_map:
		var value: Variant = part_map[key]
		if value is Array:
			# Dil slozeny z vice uzlu se stejnym rodicem -> spojit pod jeden uzel
			var group: Node3D = null
			for nm in value:
				var node := _find(scene, nm) as Node3D
				if node == null:
					continue
				if group == null:
					group = Node3D.new()
					group.name = "Dil_" + key
					node.get_parent().add_child(group)
				if node.get_parent() == group.get_parent():
					node.get_parent().remove_child(node)
					group.add_child(node)
			if group:
				parts[key] = group
		else:
			var node := _find(scene, value)
			if node:
				parts[key] = node
	body_aabb = _aabb_of(holder, wheels)


## Najde uzel podle jmena (porovnava i s nahrazenymi znaky, jak je importer meni).
func _find(root: Node, wanted: String) -> Node:
	var w := wanted.replace(".", "_").replace(":", "_")
	if String(root.name) == w or String(root.name) == wanted:
		return root
	for child in root.get_children():
		var r := _find(child, wanted)
		if r:
			return r
	return null


## Transformace uzlu vuci predkovi (funguje i mimo strom sceny).
static func xform_to(node: Node, ancestor: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n := node
	while n != null and n != ancestor:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func _aabb_of(root: Node, exclude: Array) -> AABB:
	var result := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var skip := false
		for e in exclude:
			if e == mi or (e as Node).is_ancestor_of(mi):
				skip = true
				break
		var m := mi as MeshInstance3D
		if skip or m.mesh == null:
			continue
		var a: AABB = xform_to(m, self) * m.mesh.get_aabb()
		result = a if first else result.merge(a)
		first = false
	return result


func _setup_wheels(scene: Node, holder: Node3D, c: Callable) -> void:
	var to_car := holder.transform
	var template_name: String = c.call("kolo_sablona", "")
	if template_name != "":
		var template := _find(scene, template_name) as Node3D
		if template == null:
			push_error("Sablona kola nenalezena")
			return
		template.get_parent().remove_child(template)
		template.transform = Transform3D.IDENTITY
		var disk_plus_x: bool = c.call("kolo_sablona_disk_k_plus_x", true)
		var positions: Array = c.call("kola_pozice", [])
		for i in positions.size():
			var car_pos: Vector3 = to_car * (positions[i] as Vector3)
			_make_pivot(i, car_pos)
			var copy := template.duplicate() as Node3D
			# Disk musi smerovat ven z auta
			var flip := (car_pos.x < 0.0) == disk_plus_x
			copy.transform = Transform3D(Basis(Vector3.UP, PI if flip else 0.0).scaled(Vector3.ONE * to_car.basis.get_scale().x), Vector3.ZERO)
			wheel_spins[i].add_child(copy)
		template.free()
	else:
		var groups: Array = c.call("kola_uzly", [])
		var non_spin: Array = c.call("kolo_nerotuje", ["Cal"])
		for i in groups.size():
			var nodes: Array[Node3D] = []
			for nm in groups[i]:
				var n := _find(scene, nm) as Node3D
				if n:
					nodes.append(n)
			# Pneumatika = nejvetsi dil kola; podle ni se urci stred a osa otaceni
			var tire: MeshInstance3D = null
			var best := -1.0
			for n in nodes:
				for mi in ([n] + n.find_children("*", "MeshInstance3D", true, false)):
					if mi is MeshInstance3D and (mi as MeshInstance3D).mesh:
						var vol := (xform_to(mi, self) * (mi as MeshInstance3D).mesh.get_aabb()).get_volume()
						if vol > best:
							best = vol
							tire = mi
			if tire == null:
				continue
			var txf := xform_to(tire, self)
			var laabb := tire.mesh.get_aabb()
			var center := txf * laabb.get_center()
			var sz := laabb.size
			var axis_local := Vector3.RIGHT if (sz.x <= sz.y and sz.x <= sz.z) else (Vector3.UP if sz.y <= sz.z else Vector3.BACK)
			var axle := (txf.basis * axis_local).normalized()
			if axle.x < 0.0:
				axle = -axle
			var yv := (Vector3.UP - axle * axle.dot(Vector3.UP)).normalized()
			var spin_basis := Basis(axle, yv, axle.cross(yv).normalized())
			var pivot := _make_pivot(i, center)
			wheel_spins[i].transform = Transform3D(spin_basis, Vector3.ZERO)
			var spin_xf := Transform3D(spin_basis, center)
			# Dily, ktere se netoci (brzdove trmeny), patri na otocny uzel kola, ne na rotaci
			var fixed: Array[Node3D] = []
			for n in nodes:
				for d in ([n] + n.find_children("*", "Node3D", true, false)):
					for key in non_spin:
						if String(d.name).begins_with(key) and not fixed.any(func(f): return f.is_ancestor_of(d)):
							fixed.append(d)
			var fixed_xf := {}
			for d in fixed:
				fixed_xf[d] = xform_to(d, self)
			for n in nodes:
				var xf := xform_to(n, self)
				n.get_parent().remove_child(n)
				wheel_spins[i].add_child(n)
				n.transform = spin_xf.affine_inverse() * xf
			for d in fixed:
				d.get_parent().remove_child(d)
				pivot.add_child(d)
				d.transform = Transform3D(Basis(), center).affine_inverse() * (fixed_xf[d] as Transform3D)


func _make_pivot(i: int, pos: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "Kolo%d" % i
	add_child(pivot)
	pivot.position = pos
	var spin := Node3D.new()
	spin.name = "Rotace"
	pivot.add_child(spin)
	wheels.append(pivot)
	wheel_spins.append(spin)
	wheel_rest.append(pos)
	return pivot


# ---------------------------------------------------------------------
#  Materialy
# ---------------------------------------------------------------------

func _setup_materials(scene: Node, c: Callable, color: Color) -> void:
	paint = _paint_material(color)
	tail_mat = _std(Color(1.0, 0.04, 0.05), 0.0, 0.3)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1.0, 0.03, 0.04)
	tail_mat.emission_energy_multiplier = 2.0
	head_mat = _std(Color(1, 1, 1), 0.0, 0.2)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1.0, 0.97, 0.9)
	head_mat.emission_energy_multiplier = 8.0

	var paint_names: Array = c.call("lak", [])
	var mat_map: Dictionary = c.call("materialy", {})
	var node_map: Dictionary = c.call("uzly_materialy", {})
	for mi in find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var path := _ancestor_names(m)
		for s in m.mesh.get_surface_count():
			var mat := m.mesh.surface_get_material(s)
			var mname := mat.resource_name if mat else ""
			var preset := ""
			if mname in paint_names:
				preset = "lak"
			if mat_map.has(mname):
				preset = mat_map[mname]
			for key in node_map:
				var bits: PackedStringArray = String(key).split("|")
				if bits.size() == 2 and path.contains(bits[0]) and (bits[1] == "*" or bits[1] == mname):
					preset = node_map[key]
			if preset != "" and preset != "puvodni":
				m.set_surface_override_material(s, _preset(preset))


func _ancestor_names(n: Node) -> String:
	var s := ""
	while n != null and n != self:
		s += String(n.name) + "/"
		n = n.get_parent()
	return s


func _preset(name_: String) -> Material:
	match name_:
		"lak":
			return paint
		"zadni_svetlo":
			return tail_mat
		"predni_svetlo":
			return head_mat
	if _shared.has(name_):
		return _shared[name_]
	var m: StandardMaterial3D
	match name_:
		"chrom":
			m = _std(Color(0.9, 0.9, 0.92), 1.0, 0.1)
		"cerny_lesk":
			m = _std(Color(0.015, 0.015, 0.017), 0.2, 0.18)
		"cerny_mat":
			m = _std(Color(0.02, 0.02, 0.022), 0.0, 0.75)
		"sedy":
			m = _std(Color(0.09, 0.09, 0.1), 0.3, 0.5)
		"sklo":
			m = _std(Color(0.03, 0.04, 0.05, 0.72), 0.2, 0.02)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
			m.metallic_specular = 0.8
		"svetlo_kryt":
			m = _std(Color(0.9, 0.95, 1.0, 0.12), 0.0, 0.0)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.metallic_specular = 1.0
		"svetlo_vnitrek":
			m = _std(Color(0.8, 0.8, 0.82), 1.0, 0.15)
		"blinkr":
			m = _std(Color(1.0, 0.55, 0.05), 0.0, 0.3)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.5, 0.05)
			m.emission_energy_multiplier = 0.6
		"mlhovka":
			m = _std(Color(0.9, 0.95, 1.0), 0.0, 0.2)
			m.emission_enabled = true
			m.emission = Color(0.9, 0.95, 1.0)
			m.emission_energy_multiplier = 1.5
		"interier":
			m = _std(Color(0.05, 0.05, 0.055), 0.0, 0.8)
		"kov":
			m = _std(Color(0.22, 0.22, 0.24), 0.8, 0.45)
		"guma":
			m = _std(Color(0.03, 0.03, 0.032), 0.0, 0.9)
		"disk":
			m = _std(Color(0.75, 0.76, 0.78), 1.0, 0.22)
		"disk_tmavy":
			m = _std(Color(0.12, 0.12, 0.13), 0.9, 0.35)
		"zrcatko":
			m = _std(Color(0.95, 0.95, 0.95), 1.0, 0.02)
		"odrazka":
			m = _std(Color(0.6, 0.02, 0.02), 0.2, 0.2)
		_:
			push_warning("Neznama predvolba materialu: " + name_)
			m = _std(Color(1, 0, 1), 0.0, 0.5)
	_shared[name_] = m
	return m


static func _std(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


static func _paint_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.35
	m.roughness = 0.3
	m.metallic_specular = 0.6
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.clearcoat_roughness = 0.04
	return m


# ---------------------------------------------------------------------
#  Svetla
# ---------------------------------------------------------------------

func _setup_lights(holder: Node3D, c: Callable, is_player: bool) -> void:
	var lights_node := Node3D.new()
	lights_node.name = "Svetla"
	add_child(lights_node)
	var positions: Array = c.call("svetla_predni", [])
	var i := 0
	for p in positions:
		var spot := SpotLight3D.new()
		spot.name = "Reflektor%d" % i
		spot.light_color = Color(1.0, 0.96, 0.88)
		spot.light_energy = 12.0
		spot.spot_range = 55.0
		spot.spot_angle = 32.0
		spot.spot_attenuation = 0.8
		spot.light_volumetric_fog_energy = 0.4
		spot.shadow_enabled = is_player and i == 0
		spot.position = holder.transform * (p as Vector3) + Vector3(0, 0, -0.05)
		spot.rotation_degrees = Vector3(-5, 0, 0)
		lights_node.add_child(spot)
		beams.append(spot)
		i += 1
	underglow = OmniLight3D.new()
	underglow.name = "Podsviceni"
	underglow.light_color = Color(0.2, 0.6, 1.0)
	underglow.light_energy = 1.6
	underglow.omni_range = 3.2
	underglow.omni_attenuation = 1.5
	underglow.position = Vector3(0, 0.12, 0)
	underglow.visible = false
	lights_node.add_child(underglow)
	if is_player:
		# Jemne "studiove" svetlo nad autem hrace - auto je videt i v tmavych mistech
		var key := OmniLight3D.new()
		key.name = "SvetloNadAutem"
		key.light_color = Color(0.85, 0.9, 1.0)
		key.light_energy = 1.4
		key.light_specular = 0.7
		key.omni_range = 7.5
		key.omni_attenuation = 1.2
		key.position = Vector3(0, 3.2, 0.6)
		lights_node.add_child(key)
