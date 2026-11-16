class_name CityBuilder
extends Node3D
## Stavi mesto z planu CityMap: ulice s nepravidelnymi uhly a oblouky, krizovatky,
## obrubniky, domy podel ulic, zdi (kolize), lampy, neonove cedule a treninkovou plochu.
## Vse je v rovine y = 0 a stavi se v kodu z textur a modelu v assets/.

const CURB := 0.12
const WALL_HEIGHT := 10.0
const NEON := [Color(1.0, 0.15, 0.75), Color(0.1, 0.85, 1.0), Color(1.0, 0.5, 0.1),
	Color(0.6, 0.25, 1.0), Color(0.2, 1.0, 0.45), Color(1.0, 0.2, 0.2)]
const FACADES := ["concrete_tile_facade", "exterior_wall_cladding", "red_brick"]

var map: CityMap
var rng := RandomNumberGenerator.new()
var signs: NeonSigns
var ground_material: ShaderMaterial      # material silnic (mokro se meni podle dne/noci)
var building_count := 0
var _mats := {}
var _facade_mats := {}
var _lamp_positions: Array[Transform3D] = []
var _lamp_mm := {}
var _lamp_meshes := {}
var _grid := {}                           # prostorova mrizka obrysu (domy, koridory ulic)
var _node_ends := {}                      # "krizovatka:ulice" -> [levy roh, pravy roh] konce vozovky


func build() -> void:
	rng.seed = 2427
	map = CityMap.new()
	signs = NeonSigns.new()
	signs.name = "NeonoveCedule"
	signs.rng.seed = 99
	add_child(signs)
	_build_ground()
	_build_roads()
	_build_walls()
	_build_buildings()
	_build_lot()
	_collect_street_lamps()
	_build_street_lamps()
	_build_street_props()
	signs.set_view_distance(320.0)
	if OS.get_cmdline_user_args().has("--statistika"):
		print("[MESTO] domu %d, lamp %d, cedul %d" % [building_count, _lamp_positions.size(), signs.get_child_count()])


## Ve dne okna a vylohy sviti jen slabe, v noci naplno.
func set_daylight(day: bool) -> void:
	for mat: ShaderMaterial in _facade_mats.values():
		mat.set_shader_parameter("window_energy", 0.3 if day else 1.3)
		mat.set_shader_parameter("shop_energy", 0.45 if day else 0.9)


# ---------------------------------------------------------------------
#  Materialy a pomocne funkce
# ---------------------------------------------------------------------

func pbr(tex_name: String, scale: float, tint := Color.WHITE, rough_mult := 1.0) -> StandardMaterial3D:
	var key := "%s_%.3f_%s_%.2f" % [tex_name, scale, tint.to_html(), rough_mult]
	if _mats.has(key):
		return _mats[key]
	var base := "res://assets/textures/%s/%s_" % [tex_name, tex_name]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(base + "diff.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(base + "nor.jpg")
	m.roughness_texture = load(base + "rough.jpg")
	m.roughness = rough_mult
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


func simple(color: Color, metallic := 0.0, roughness := 0.8, emission := 0.0) -> StandardMaterial3D:
	var key := "s_%s_%.2f_%.2f_%.1f" % [color.to_html(), metallic, roughness, emission]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_mats[key] = m
	return m


func static_box(size: Vector3, xform: Transform3D, mat: Material, parent: Node = self, collide := true) -> Node3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	if not collide:
		parent.add_child(mi)
		mi.transform = xform
		return mi
	var body := StaticBody3D.new()
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	body.transform = xform
	return body


func mesh_at(mesh: Mesh, mat: Material, pos: Vector3, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos
	return mi


func noise_texture(freq: float, size: int, seed_value: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = freq
	n.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.noise = n
	tex.width = size
	tex.height = size
	tex.seamless = true
	tex.generate_mipmaps = true
	return tex


## Umisti model rekvizity z assets/props. dynamic = fyzicky objekt, ktery jde odstrcit.
func place_prop(prop: String, pos: Vector3, yaw: float, dynamic: bool, mass := 30.0) -> Node3D:
	var scene := load("res://assets/props/%s/%s_1k.gltf" % [prop, prop]) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate() as Node3D
	# Nektere modely obsahuji vedle sebe dve varianty (nova/rezava) - nechame jen jednu
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		if nm.contains("aged") or nm.contains("rust"):
			mi.get_parent().remove_child(mi)
			mi.free()
	var aabb := AABB()
	var first := true
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh:
			var a: AABB = CarModel.xform_to(m, inst) * m.mesh.get_aabb()
			aabb = a if first else aabb.merge(a)
			first = false
	var body: CollisionObject3D
	if dynamic:
		var rb := RigidBody3D.new()
		rb.mass = mass
		rb.add_to_group("props")
		body = rb
	else:
		body = StaticBody3D.new()
	body.name = prop
	body.add_child(inst)
	inst.position = -Vector3(aabb.get_center().x, 0, aabb.get_center().z)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = aabb.size.max(Vector3.ONE * 0.05)
	cs.shape = shape
	cs.position = Vector3(0, aabb.get_center().y, 0)
	body.add_child(cs)
	add_child(body)
	body.position = pos + Vector3(0, 0.02, 0)
	body.rotation.y = yaw
	return body


func _multimesh(mesh: Mesh, mat: Material) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	return mmi


func _fill_multimesh(mmi: MultiMeshInstance3D, xforms: Array[Transform3D]) -> void:
	mmi.multimesh.instance_count = xforms.size()
	for i in xforms.size():
		mmi.multimesh.set_instance_transform(i, xforms[i])

static func v3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


## Prida trojuhelnik lezici v rovine tak, aby byl videt shora.
func _tri_up(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, uv_a := Vector2.ZERO, uv_b := Vector2.ZERO, uv_c := Vector2.ZERO, uv2_a := Vector2.ZERO, uv2_b := Vector2.ZERO, uv2_c := Vector2.ZERO) -> void:
	var cross := (b.x - a.x) * (c.z - a.z) - (b.z - a.z) * (c.x - a.x)
	var pts := [[a, uv_a, uv2_a], [b, uv_b, uv2_b], [c, uv_c, uv2_c]]
	if cross < 0.0:
		pts = [pts[0], pts[2], pts[1]]
	for p in pts:
		st.set_normal(Vector3.UP)
		st.set_uv(p[1])
		st.set_uv2(p[2])
		st.add_vertex(p[0])


# ---------------------------------------------------------------------
#  Zem a silnice
# ---------------------------------------------------------------------

func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Zem"
	add_child(body)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(8000, 2, 8000)
	cs.shape = shape
	cs.position = Vector3(0, -1, 0)
	body.add_child(cs)
	# Dlazba (chodniky a vnitrky bloku); silnice lezi tesne nad ni
	var plane := PlaneMesh.new()
	plane.size = Vector2(8000, 8000)
	var mi := mesh_at(plane, pbr("concrete_pavement", 0.3, Color(0.8, 0.8, 0.86)), Vector3(0, -0.02, 0), body)
	mi.name = "Dlazba"


func _build_roads() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/road.gdshader")
	mat.set_shader_parameter("asphalt_albedo", load("res://assets/textures/asphalt_02/asphalt_02_diff.jpg"))
	mat.set_shader_parameter("asphalt_normal", load("res://assets/textures/asphalt_02/asphalt_02_nor.jpg"))
	mat.set_shader_parameter("asphalt_rough", load("res://assets/textures/asphalt_02/asphalt_02_rough.jpg"))
	mat.set_shader_parameter("puddle_noise", noise_texture(0.02, 512, 7))
	ground_material = mat

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var curb := SurfaceTool.new()
	curb.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := 0.02
	for e in map.polylines.size():
		var w: float = map.half_width[e]
		var axis := map.trimmed(e)
		var left := CityMap.offset_polyline(axis, -w)
		var right := CityMap.offset_polyline(axis, w)
		var total := CityMap.polyline_length(axis)
		var along := 0.0
		st.set_color(Color(w / 32.0, 1.0, 0.0))
		for i in axis.size() - 1:
			var seg := axis[i].distance_to(axis[i + 1])
			var a0 := along
			var a1 := along + seg
			_tri_up(st, v3(left[i], y), v3(left[i + 1], y), v3(right[i + 1], y),
				Vector2(-w, a0), Vector2(-w, a1), Vector2(w, a1), Vector2(a0, total), Vector2(a1, total), Vector2(a1, total))
			_tri_up(st, v3(left[i], y), v3(right[i + 1], y), v3(right[i], y),
				Vector2(-w, a0), Vector2(w, a1), Vector2(w, a0), Vector2(a0, total), Vector2(a1, total), Vector2(a0, total))
			along = a1
		# Konce vozovky pro plochu krizovatky (levy/pravy roh pri pohledu z krizovatky ven)
		var last := axis.size() - 1
		_node_ends["%s:%d" % [CityMap.EDGES[e][0], e]] = [left[0], right[0]]
		_node_ends["%s:%d" % [CityMap.EDGES[e][1], e]] = [right[last], left[last]]
		# Obrubniky podel vozovky
		for side in [-1, 1]:
			if not map.is_open(e, side):
				_curb_strip(curb, left if side < 0 else right, float(side))

	# Plochy krizovatek
	st.set_color(Color(0.0, 0.0, 0.0))
	for id in CityMap.NODES:
		var arr: Array = map.node_edges[id]
		var poly: Array[Vector2] = []
		for k in arr.size():
			var ends: Array = _node_ends["%s:%d" % [id, arr[k].e]]
			poly.append(ends[0])
			poly.append(ends[1])
		var center := v3(CityMap.NODES[id], y)
		for i in poly.size():
			_tri_up(st, center, v3(poly[i], y), v3(poly[(i + 1) % poly.size()], y))
		# Obrubnik pres roh bloku (mezi sousednimi ulicemi)
		for k in arr.size():
			var e_a: int = arr[k].e
			var e_b: int = arr[(k + 1) % arr.size()].e
			var a_right_side := 1 if CityMap.EDGES[e_a][0] == id else -1
			var b_left_side := -1 if CityMap.EDGES[e_b][0] == id else 1
			if map.is_open(e_a, a_right_side) or map.is_open(e_b, b_left_side) or arr.size() < 2:
				continue
			var p0: Vector2 = poly[k * 2 + 1]
			var p1: Vector2 = poly[((k + 1) % arr.size()) * 2]
			if p0.distance_to(p1) > 0.3:
				_curb_strip(curb, PackedVector2Array([p0, p1]), 1.0)

	var mi := MeshInstance3D.new()
	mi.name = "Silnice"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var cmi := MeshInstance3D.new()
	cmi.name = "Obrubniky"
	cmi.mesh = curb.commit()
	cmi.material_override = simple(Color(0.55, 0.55, 0.58), 0.0, 0.85)
	add_child(cmi)


## Obrubnik: uzky zvyseny pruh podel cary (side = na kterou stranu od cary lezi).
func _curb_strip(st: SurfaceTool, line: PackedVector2Array, side: float) -> void:
	var outer := CityMap.offset_polyline(line, side * 0.3)
	for i in line.size() - 1:
		var a := v3(line[i], CURB)
		var b := v3(line[i + 1], CURB)
		var c := v3(outer[i + 1], CURB)
		var d := v3(outer[i], CURB)
		_tri_up(st, a, b, c)
		_tri_up(st, a, c, d)
		# Svisla hrana k vozovce
		var a0 := v3(line[i], 0.0)
		var b0 := v3(line[i + 1], 0.0)
		var n := v3(CityMap.right_of((line[i + 1] - line[i]).normalized()) * -side)
		for tri in [[a0, b0, b], [a0, b, a]]:
			var t0: Vector3 = tri[0]
			var t1: Vector3 = tri[1]
			var t2: Vector3 = tri[2]
			if (t1 - t0).cross(t2 - t0).dot(n) > 0.0:   # Godot: predni strana = po smeru hodin
				var tmp := t1
				t1 = t2
				t2 = tmp
			for p in [t0, t1, t2]:
				st.set_normal(n)
				st.set_uv(Vector2.ZERO)
				st.add_vertex(p)


# ---------------------------------------------------------------------
#  Zdi (kolize): jedna spojita sit kolem vsech bloku
# ---------------------------------------------------------------------

func _build_walls() -> void:
	# Auto se dotyka jen teto hladke site (domy samy kolizi nemaji), takze se nezasekne o spary.
	var faces := PackedVector3Array()
	for e in map.polylines.size():
		for side in [-1, 1]:
			if map.is_open(e, side):
				continue
			var line := map.block_line(e, side, CityMap.SIDEWALK)
			for i in line.size() - 1:
				var a := v3(line[i])
				var b := v3(line[i + 1])
				var a1 := a + Vector3.UP * WALL_HEIGHT
				var b1 := b + Vector3.UP * WALL_HEIGHT
				faces.append_array([a, b, b1, a, b1, a1])
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.name = "Zdi"
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)


# ---------------------------------------------------------------------
#  Domy podel ulic
# ---------------------------------------------------------------------

## Obrys v rovine: stred c, osa ax (jednotkova), polovina delky hx (podel osy) a hy (kolmo).
func _obb(c: Vector2, ax: Vector2, hx: float, hy: float) -> Dictionary:
	return {"c": c, "ax": ax, "hx": hx, "hy": hy}


func _obb_overlap(a: Dictionary, b: Dictionary) -> bool:
	var d: Vector2 = b.c - a.c
	for ax in [a.ax, CityMap.right_of(a.ax), b.ax, CityMap.right_of(b.ax)]:
		var axis: Vector2 = ax
		var ra: float = absf(axis.dot(a.ax)) * a.hx + absf(axis.dot(CityMap.right_of(a.ax))) * a.hy
		var rb: float = absf(axis.dot(b.ax)) * b.hx + absf(axis.dot(CityMap.right_of(b.ax))) * b.hy
		if absf(d.dot(axis)) > ra + rb:
			return false
	return true


func _grid_cells(o: Dictionary) -> Array:
	var px: Vector2 = CityMap.right_of(o.ax)
	var ex: float = absf(o.ax.x) * o.hx + absf(px.x) * o.hy
	var ez: float = absf(o.ax.y) * o.hx + absf(px.y) * o.hy
	var cells := []
	for gx in range(int(floor((o.c.x - ex) / 80.0)), int(floor((o.c.x + ex) / 80.0)) + 1):
		for gz in range(int(floor((o.c.y - ez) / 80.0)), int(floor((o.c.y + ez) / 80.0)) + 1):
			cells.append(Vector2i(gx, gz))
	return cells


func _grid_add(o: Dictionary) -> void:
	for cell in _grid_cells(o):
		if not _grid.has(cell):
			_grid[cell] = []
		_grid[cell].append(o)


func _grid_free(o: Dictionary) -> bool:
	for cell in _grid_cells(o):
		for other in _grid.get(cell, []):
			if _obb_overlap(o, other):
				return false
	return true


func _build_buildings() -> void:
	var holder := Node3D.new()
	holder.name = "Domy"
	add_child(holder)
	# Koridory ulic (vozovka + chodniky): do nich dum nesmi zasahnout
	for e in map.polylines.size():
		var pl := map.polylines[e]
		for i in pl.size() - 1:
			var d := (pl[i + 1] - pl[i])
			_grid_add(_obb((pl[i] + pl[i + 1]) * 0.5, d.normalized(), d.length() * 0.5 + 1.0, map.half_width[e] + CityMap.SIDEWALK - 0.4))
	for e in map.polylines.size():
		for side in [-1, 1]:
			if map.is_open(e, side):
				continue
			var line := map.block_line(e, side, CityMap.SIDEWALK + 0.25)
			for i in line.size() - 1:
				_fill_frontage(holder, line[i], line[i + 1], float(side))


## Zaplni usek ulicni cary domy (od bodu p k bodu q; domy stoji na strane side od smeru p->q).
func _fill_frontage(holder: Node3D, p: Vector2, q: Vector2, side: float) -> void:
	var length := p.distance_to(q)
	if length < 7.0:
		return
	var dir := (q - p) / length
	var inward := CityMap.right_of(dir) * side
	var s := 0.3
	while s < length - 6.0:
		var width := minf(rng.randf_range(14.0, 30.0), length - s - 0.3)
		if length - s - width < 8.0:
			width = length - s - 0.3
		var placed := false
		for attempt in [[width, rng.randf_range(16.0, 26.0)], [width, 11.0], [minf(width, 12.0), 9.0], [minf(width, 8.0), 6.5]]:
			var wd: float = attempt[0]
			var depth: float = attempt[1]
			var center := p + dir * (s + wd * 0.5) + inward * (depth * 0.5)
			var o := _obb(center, dir, wd * 0.5 - 0.1, depth * 0.5 - 0.1)
			if _grid_free(o):
				_grid_add(_obb(center, dir, wd * 0.5 + 0.4, depth * 0.5 + 0.4))
				_make_building(holder, center, dir, inward, wd, depth)
				# Druha rada: vyssi dum ve vnitrobloku (aby mezi domy nebylo videt prazdno)
				if depth > 10.0 and rng.randf() < 0.7:
					var bw := rng.randf_range(18.0, 32.0)
					var bd := rng.randf_range(18.0, 30.0)
					var bc := center + inward * (depth * 0.5 + 3.0 + bd * 0.5)
					if _grid_free(_obb(bc, dir, bw * 0.5, bd * 0.5)):
						_grid_add(_obb(bc, dir, bw * 0.5 + 0.4, bd * 0.5 + 0.4))
						_make_building(holder, bc, dir, inward, bw, bd, true)
				s += wd + rng.randf_range(0.0, 1.5)
				placed = true
				break
		if not placed:
			s += 5.0


func _facade_material(facade: String) -> ShaderMaterial:
	if not _facade_mats.has(facade):
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/building.gdshader")
		mat.set_shader_parameter("wall_albedo", load("res://assets/textures/%s/%s_diff.jpg" % [facade, facade]))
		mat.set_shader_parameter("wall_normal", load("res://assets/textures/%s/%s_nor.jpg" % [facade, facade]))
		mat.set_shader_parameter("wall_scale", 0.22 if facade != "red_brick" else 0.35)
		_facade_mats[facade] = mat
	return _facade_mats[facade]


## Jeden dum: kvadr s fasadou (okna, vylohy), obcas neon na strese, cedule nebo billboard.
func _make_building(holder: Node3D, center: Vector2, dir: Vector2, inward: Vector2, width: float, depth: float, back_row := false) -> void:
	building_count += 1
	var tall := clampf(1.0 - center.length() / 650.0, 0.0, 1.0)
	var height := rng.randf_range(11.0, 26.0) + rng.randf() * 95.0 * tall * tall
	if depth < 10.0:
		height = minf(height, rng.randf_range(8.0, 16.0))
	if back_row:
		height = height * 1.25 + rng.randf_range(6.0, 22.0)
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, height, depth)
	mi.mesh = box
	mi.material_override = _facade_material(FACADES[rng.randi() % FACADES.size()])
	holder.add_child(mi)
	mi.position = Vector3(center.x, height * 0.5, center.y)
	mi.rotation.y = -atan2(dir.y, dir.x)
	var tints := [Color(1, 1, 1), Color(0.75, 0.78, 0.85), Color(0.9, 0.82, 0.75), Color(0.6, 0.62, 0.7)]
	var shop_cols := [Color(1.0, 0.8, 0.55), Color(0.8, 0.9, 1.0), Color(1.0, 0.65, 0.4)]
	mi.set_instance_shader_parameter("wall_tint", tints[rng.randi() % tints.size()])
	mi.set_instance_shader_parameter("seed", rng.randf() * 100.0)
	mi.set_instance_shader_parameter("lit_ratio", rng.randf_range(0.25, 0.55))
	mi.set_instance_shader_parameter("half_height", height * 0.5)
	mi.set_instance_shader_parameter("cell", Vector2(rng.randf_range(2.6, 3.8), rng.randf_range(3.2, 3.8)))
	mi.set_instance_shader_parameter("shop_color", shop_cols[rng.randi() % shop_cols.size()])

	if back_row:
		mi.visibility_range_end = 900.0
		if height > 45.0 and rng.randf() < 0.5:
			var top := BoxMesh.new()
			top.size = Vector3(width + 0.25, 0.3, depth + 0.25)
			var tmi := mesh_at(top, simple(NEON[rng.randi() % NEON.size()], 0.0, 0.3, 5.0), Vector3(0, height * 0.5 - 0.6, 0), mi)
			tmi.visibility_range_end = 700.0
		return
	if rng.randf() < 0.4 and height > 14.0:
		var rim := BoxMesh.new()
		rim.size = Vector3(width + 0.25, 0.22, depth + 0.25)
		var rmi := mesh_at(rim, simple(NEON[rng.randi() % NEON.size()], 0.0, 0.3, 5.0), Vector3(0, height * 0.5 - rng.randf_range(0.4, 2.0), 0), mi)
		rmi.visibility_range_end = 700.0

	# Cedule na fasade k ulici
	var out := -inward
	var yaw_deg := rad_to_deg(atan2(out.x, out.y))
	var front := center + out * (depth * 0.5 + 0.08)
	if width >= 9.0 and rng.randf() < 0.45:
		var off := rng.randf_range(-width * 0.2, width * 0.2)
		signs.shop_sign(v3(front + dir * off, 5.5), yaw_deg, minf(width * 0.6, 14.0))
	if height > 20.0 and rng.randf() < 0.12:
		var corner_off := (width * 0.5 - 1.2) * (1.0 if rng.randf() < 0.5 else -1.0)
		signs.blade_sign(v3(front + dir * corner_off, rng.randf_range(9.0, 13.0)), yaw_deg)
	if height < 40.0 and width >= 15.0 and depth > 10.0 and rng.randf() < 0.1:
		signs.billboard(Vector3(center.x, height + 3.8, center.y), yaw_deg)


# ---------------------------------------------------------------------
#  Treninkova plocha (velke parkoviste bez domu)
# ---------------------------------------------------------------------

func _build_lot() -> void:
	var holder := Node3D.new()
	holder.name = "TreninkovaPlocha"
	add_child(holder)
	var poly := map.lot_polygon(-0.3)
	var inner := map.lot_polygon(6.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color(0.0, 0.0, 0.0))
	var idx := Geometry2D.triangulate_polygon(poly)
	for i in range(0, idx.size(), 3):
		_tri_up(st, v3(poly[idx[i]], 0.012), v3(poly[idx[i + 1]], 0.012), v3(poly[idx[i + 2]], 0.012))
	var mi := MeshInstance3D.new()
	mi.name = "AsfaltPlochy"
	mi.mesh = st.commit()
	mi.material_override = ground_material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)

	var c := Vector2.ZERO
	for p in poly:
		c += p / poly.size()
	var inside := func(p: Vector2) -> bool: return Geometry2D.is_point_in_polygon(p, inner)

	# Sklad "NITRO GARAZ" s rolovacimi vraty
	var shutter := pbr("painted_metal_shutter", 0.25, Color(0.6, 0.65, 0.75))
	var wh_pos := c + Vector2(-70, -30)
	var wh := Vector3(16, 11, 70)
	static_box(wh, Transform3D(Basis(), v3(wh_pos, wh.y * 0.5)), pbr("container_side", 0.12, Color(0.35, 0.38, 0.45)), holder)
	for i in 3:
		var dz := -22.0 + i * 22.0
		static_box(Vector3(0.2, 5, 8), Transform3D(Basis(), v3(wh_pos + Vector2(wh.x * 0.5 + 0.1, dz), 2.5)), shutter, holder, false)
		var lamp := BoxMesh.new()
		lamp.size = Vector3(0.6, 0.15, 1.2)
		mesh_at(lamp, simple(Color(1.0, 0.85, 0.6), 0.0, 0.3, 8.0), v3(wh_pos + Vector2(wh.x * 0.5 + 0.5, dz), 5.6), holder)
	signs.big_text("NITRO GARÁŽ", "stencil", v3(wh_pos + Vector2(wh.x * 0.5 + 0.2, 0), 8.6), 90.0, 0.05, NEON[0], 220)
	signs.big_text("NEON WRECK", "monoton", v3(c + Vector2(0, -95), 9.0), 0.0, 0.06, NEON[1], 260)

	# Rampy
	var ramp_mat := pbr("concrete_floor_worn_001", 0.4, Color(0.6, 0.6, 0.65))
	var stripe := simple(Color(1.0, 0.75, 0.0), 0.0, 0.4, 3.0)
	for rp in [[c + Vector2(-10, 20), 0.0, 12.0, 2.2, 8.0], [c + Vector2(45, -20), 90.0, 18.0, 3.6, 10.0], [c + Vector2(20, 60), -90.0, 10.0, 1.5, 7.0]]:
		var pos: Vector2 = rp[0]
		if not inside.call(pos):
			continue
		var length: float = rp[2]
		var height: float = rp[3]
		var width: float = rp[4]
		var prism := PrismMesh.new()
		prism.left_to_right = 1.0
		prism.size = Vector3(length, height, width)
		var body := StaticBody3D.new()
		body.name = "Rampa"
		holder.add_child(body)
		body.position = v3(pos, height * 0.5)
		body.rotation_degrees = Vector3(0, 90.0 + float(rp[1]), 0)
		mesh_at(prism, ramp_mat, Vector3.ZERO, body)
		var cs := CollisionShape3D.new()
		cs.shape = prism.create_convex_shape()
		body.add_child(cs)
		var edge_mesh := BoxMesh.new()
		edge_mesh.size = Vector3(0.2, 0.1, width)
		mesh_at(edge_mesh, stripe, Vector3(length * 0.5 - 0.1, height * 0.5 + 0.02, 0), body)

	# Kontejnery, zabrany (slalom), sudy a bedny
	var cont_tints := [Color(0.7, 0.2, 0.15), Color(0.15, 0.35, 0.65), Color(0.2, 0.5, 0.3), Color(0.75, 0.55, 0.15)]
	for cdef in [[Vector2(70, 40), 0.2], [Vector2(76, 44), 0.05], [Vector2(-30, 80), 1.5], [Vector2(60, -70), -0.4]]:
		var cp: Vector2 = c + cdef[0]
		if inside.call(cp):
			static_box(Vector3(2.5, 2.6, 6.1), Transform3D(Basis(Vector3.UP, cdef[1]), v3(cp, 1.3)), pbr("container_side", 0.33, cont_tints[rng.randi() % cont_tints.size()]), holder)
	for i in 9:
		var bp := c + Vector2(-40.0 + i * 10.0, -55.0 + (3.0 if i % 2 == 0 else -3.0))
		if inside.call(bp):
			place_prop("concrete_road_barrier", v3(bp), rng.randf_range(-0.3, 0.3), false)
	for i in 14:
		var bp := c + Vector2(55 + rng.randf_range(-10, 10), 5 + rng.randf_range(-10, 10))
		if inside.call(bp):
			place_prop("Barrel_01", v3(bp), rng.randf() * TAU, true, 40.0)
	for i in 8:
		var bp := c + Vector2(-25 + rng.randf_range(-6, 6), 45 + rng.randf_range(-6, 6))
		if inside.call(bp):
			place_prop("wooden_crate_01", v3(bp), rng.randf() * TAU, true, 15.0)

	# Vysoke lampy na plose (y = 0 znamena vysokou lampu se dvema svetly)
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var lp := c + Vector2(ix * 55.0, iz * 55.0 + 27.0)
			if inside.call(lp):
				_lamp_positions.append(Transform3D(Basis(), v3(lp)))


# ---------------------------------------------------------------------
#  Poulicni lampy
# ---------------------------------------------------------------------

func _collect_street_lamps() -> void:
	for e in map.polylines.size():
		var w: float = map.half_width[e]
		var axis := map.trimmed(e)
		var total := CityMap.polyline_length(axis)
		var count := int(total / 46.0)
		for k in count:
			var dist := total * (k + 0.5) / count
			var side := 1.0 if (k + e) % 2 == 0 else -1.0
			# Bod a smer ve vzdalenosti dist podel osy
			var acc := 0.0
			for i in axis.size() - 1:
				var seg := axis[i].distance_to(axis[i + 1])
				if acc + seg >= dist:
					var dir := (axis[i + 1] - axis[i]) / seg
					var p := axis[i] + dir * (dist - acc) + CityMap.right_of(dir) * side * (w + 0.9)
					var to_road := -CityMap.right_of(dir) * side
					_lamp_positions.append(Transform3D(Basis.looking_at(v3(to_road), Vector3.UP), v3(p, 0.06)))
					break
				acc += seg


func _build_street_lamps() -> void:
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.09
	pole_mesh.bottom_radius = 0.15
	pole_mesh.height = 9.0
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.12, 0.12, 2.4)
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.45, 0.16, 0.9)
	var glow_mesh := BoxMesh.new()
	glow_mesh.size = Vector3(0.38, 0.03, 0.8)
	var metal := simple(Color(0.22, 0.23, 0.25), 0.85, 0.35)
	var mm_pole := _multimesh(pole_mesh, metal)
	var mm_arm := _multimesh(arm_mesh, metal)
	var mm_head := _multimesh(head_mesh, metal)
	var warm := Color(1.0, 0.68, 0.38)
	var cool := Color(0.75, 0.88, 1.0)
	var mm_glow_warm := _multimesh(glow_mesh, simple(warm, 0.0, 0.3, 5.0))
	var mm_glow_cool := _multimesh(glow_mesh, simple(cool, 0.0, 0.3, 5.0))
	var poles: Array[Transform3D] = []
	var arms: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	var glows_w: Array[Transform3D] = []
	var glows_c: Array[Transform3D] = []
	var lights := Node3D.new()
	lights.name = "SvetlaLamp"
	add_child(lights)
	var i := 0
	for xf in _lamp_positions:
		var tall := xf.origin.y < 0.05  # lampy na parkovisti jsou vyssi
		var h := 13.0 if tall else 9.0
		var s := h / 9.0
		poles.append(Transform3D(xf.basis.scaled(Vector3(s, s, s)), xf.origin + Vector3(0, h * 0.5, 0)))
		var heads_local := [Vector3(0, h, -1.9)] if not tall else [Vector3(0, h, -1.9), Vector3(0, h, 1.9)]
		var is_warm := (i % 5) != 0
		# Zaznam lampy: indexy v MultiMeshich a svetla (aby sla lampa porazit)
		var rec := {"pole": poles.size() - 1, "arms": [], "heads": [], "glows": [], "lights": [], "xf": xf, "h": h,
			"glow_mm": mm_glow_warm if is_warm else mm_glow_cool}
		for hl in heads_local:
			var arm_pos: Vector3 = xf * Vector3(0, h - 0.1, (hl as Vector3).z * 0.55)
			arms.append(Transform3D(xf.basis, arm_pos))
			rec.arms.append(arms.size() - 1)
			var head_pos: Vector3 = xf * (hl as Vector3)
			heads.append(Transform3D(xf.basis, head_pos))
			rec.heads.append(heads.size() - 1)
			var glow_xf := Transform3D(xf.basis, head_pos - Vector3(0, 0.08, 0))
			if is_warm:
				glows_w.append(glow_xf)
				rec.glows.append(glows_w.size() - 1)
			else:
				glows_c.append(glow_xf)
				rec.glows.append(glows_c.size() - 1)
			var spot := SpotLight3D.new()
			spot.light_color = warm if is_warm else cool
			spot.light_energy = 26.0 if not tall else 34.0
			spot.spot_range = h * 2.0
			spot.spot_angle = 58.0
			spot.spot_attenuation = 0.7
			spot.light_volumetric_fog_energy = 1.2
			spot.light_specular = 0.8
			spot.distance_fade_enabled = true
			spot.distance_fade_begin = 130.0
			spot.distance_fade_length = 40.0
			spot.position = head_pos - Vector3(0, 0.2, 0)
			spot.rotation_degrees = Vector3(-90, 0, 0)
			spot.add_to_group("street_lights")
			lights.add_child(spot)
			rec.lights.append(spot)
		# Kolize sloupu (v male rychlosti sloup auto zastavi)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.18
		shape.height = h
		cs.shape = shape
		body.add_child(cs)
		lights.add_child(body)
		body.position = xf.origin + Vector3(0, h * 0.5, 0)
		rec["body"] = body
		# Oblast kolem sloupu: rychle jedouci auto sloup porazi drive, nez do nej narazi
		var area := Area3D.new()
		var acs := CollisionShape3D.new()
		var ashape := CylinderShape3D.new()
		ashape.radius = 1.3
		ashape.height = 2.0
		acs.shape = ashape
		area.add_child(acs)
		area.monitorable = false
		lights.add_child(area)
		area.position = xf.origin + Vector3(0, 1.0, 0)
		area.body_entered.connect(_on_lamp_hit.bind(rec, area))
		i += 1
	_fill_multimesh(mm_pole, poles)
	_fill_multimesh(mm_arm, arms)
	_fill_multimesh(mm_head, heads)
	_fill_multimesh(mm_glow_warm, glows_w)
	_fill_multimesh(mm_glow_cool, glows_c)
	_lamp_mm = {"pole": mm_pole, "arm": mm_arm, "head": mm_head}
	_lamp_meshes = {"pole": pole_mesh, "arm": arm_mesh, "head": head_mesh, "metal": metal}


## Auto v rychlosti porazi lampu: sloup odleti jako fyzicky objekt, svetlo zhasne.
func _on_lamp_hit(hit_body: Node3D, rec: Dictionary, area: Area3D) -> void:
	var rb := hit_body as RigidBody3D
	if rb == null or not rb.is_in_group("cars") or rec.get("down", false):
		return
	var v := rb.linear_velocity
	if v.length() < 7.0:
		return
	rec["down"] = true
	var zero := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0))
	(_lamp_mm.pole as MultiMeshInstance3D).multimesh.set_instance_transform(rec.pole, zero)
	for idx in rec.arms:
		(_lamp_mm.arm as MultiMeshInstance3D).multimesh.set_instance_transform(idx, zero)
	for idx in rec.heads:
		(_lamp_mm.head as MultiMeshInstance3D).multimesh.set_instance_transform(idx, zero)
	for idx in rec.glows:
		(rec.glow_mm as MultiMeshInstance3D).multimesh.set_instance_transform(idx, zero)
	for l in rec.lights:
		(l as Node).queue_free()
	(rec.body as Node).queue_free()
	area.queue_free()
	# Padajici sloup
	var xf: Transform3D = rec.xf
	var h: float = rec.h
	var pole := RigidBody3D.new()
	pole.name = "PorazenaLampa"
	pole.mass = 70.0
	pole.add_to_group("debris")
	var mi := MeshInstance3D.new()
	mi.mesh = _lamp_meshes.pole
	mi.material_override = _lamp_meshes.metal
	mi.scale = Vector3.ONE * (h / 9.0)
	pole.add_child(mi)
	var head := MeshInstance3D.new()
	head.mesh = _lamp_meshes.head
	head.material_override = _lamp_meshes.metal
	head.position = Vector3(0, h * 0.5, -1.9)
	pole.add_child(head)
	var arm := MeshInstance3D.new()
	arm.mesh = _lamp_meshes.arm
	arm.material_override = _lamp_meshes.metal
	arm.position = Vector3(0, h * 0.5 - 0.1, -1.0)
	pole.add_child(arm)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.15
	shape.height = h
	cs.shape = shape
	pole.add_child(cs)
	add_child.call_deferred(pole)
	pole.transform = Transform3D(xf.basis, xf.origin + Vector3(0, h * 0.5 + 0.1, 0))
	var dir := Vector3(v.x, 0, v.z).normalized()
	pole.linear_velocity = dir * v.length() * 0.45 + Vector3.UP * 2.5
	# Sloup se preklopi ve smeru jizdy auta
	pole.angular_velocity = Vector3.UP.cross(dir) * clampf(v.length() * 0.12, 1.0, 4.0)
	pole.add_collision_exception_with(rb)
	get_tree().create_timer(1.2).timeout.connect(func():
		if is_instance_valid(pole) and is_instance_valid(rb):
			pole.remove_collision_exception_with(rb))
	# Auto trochu zpomali, zajiskri to
	rb.apply_central_impulse(-v * rb.mass * 0.05)
	FX.spawn_sparks(self, xf.origin + Vector3(0, 0.6, 0), -dir + Vector3.UP, 50)
	for cam in get_tree().get_nodes_in_group("camera_shake"):
		cam.call("add_shake", 0.25)
	if rb.has_method("apply_damage"):
		rb.call("apply_damage", 0.8)


# ---------------------------------------------------------------------
#  Drobnosti na chodnicich (daji se odstrcit)
# ---------------------------------------------------------------------

func _build_street_props() -> void:
	for e in map.polylines.size():
		var w: float = map.half_width[e]
		var axis := map.trimmed(e)
		for i in axis.size() - 1:
			var seg := axis[i].distance_to(axis[i + 1])
			if seg < 30.0 or rng.randf() > 0.35:
				continue
			var dir := (axis[i + 1] - axis[i]) / seg
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			if map.is_open(e, int(side)):
				continue
			var p := axis[i] + dir * rng.randf_range(10.0, seg - 10.0) + CityMap.right_of(dir) * side * (w + 2.4)
			if rng.randf() < 0.6:
				place_prop("metal_trash_can", v3(p, 0.0), rng.randf() * TAU, true, 20.0)
			else:
				place_prop("fire_hydrant", v3(p, 0.0), 0.0, true, 45.0)
