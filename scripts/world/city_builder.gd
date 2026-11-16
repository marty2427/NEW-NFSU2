class_name CityBuilder
extends Node3D
## Stavi obri mesto podle planu (CityMap): silnice, obrubniky, zdi, domy, reku, volne plochy.
## Aby to bezelo plynule:
##  - domy se kresli hromadne po dlazdicich (MultiMesh, jeden shader),
##  - lampy, cedule a drobnosti existuji jen v okoli kamery (dlazdice se nacitaji a uvolnuji za jizdy),
##  - auto narazi jen do jedne spojite site zdi (domy samy kolizi nemaji), takze se nezasekne o spary.

const CURB := 0.12
const WALL_HEIGHT := 10.0
const CHUNK := 320.0                 # velikost dlazdice (m)
const DETAIL_ON := 400.0             # do teto vzdalenosti od kamery se nacitaji lampy, cedule a drobnosti
const DETAIL_OFF := 540.0            # za touto vzdalenosti se zase uvolni
const BUILDING_VIEW := 2300.0        # dohled domu (dal uz je mlha)
const NEON := [Color(1.0, 0.15, 0.75), Color(0.1, 0.85, 1.0), Color(1.0, 0.5, 0.1),
	Color(0.55, 0.25, 1.0), Color(0.2, 1.0, 0.5), Color(1.0, 0.9, 0.2)]
const FACADES := ["concrete_tile_facade", "exterior_wall_cladding", "red_brick", "container_side"]

## Vzhled domu podle ctvrti: vyska [od, do], prirazka vezaku, sirka, hloubka, mezera mezi domy,
## fasady (indexy do FACADES), podil domu s obchodem, podil rozsvicenych oken, sance na druhou radu.
const STYLES := {
	"stare": {"h": [12.0, 22.0], "tower": 0.0, "w": [10.0, 20.0], "d": [12.0, 18.0], "gap": [0.0, 0.6], "fac": [2, 2, 0], "shop": 0.6, "lit": [0.3, 0.6], "back": 0.55},
	"mesto": {"h": [14.0, 32.0], "tower": 38.0, "w": [14.0, 28.0], "d": [16.0, 26.0], "gap": [0.0, 1.5], "fac": [0, 1, 2], "shop": 0.45, "lit": [0.25, 0.55], "back": 0.7},
	"jih": {"h": [12.0, 26.0], "tower": 22.0, "w": [14.0, 28.0], "d": [16.0, 24.0], "gap": [0.0, 2.5], "fac": [0, 2, 2], "shop": 0.4, "lit": [0.25, 0.5], "back": 0.6},
	"mrizka": {"h": [34.0, 80.0], "tower": 120.0, "w": [18.0, 34.0], "d": [20.0, 30.0], "gap": [0.0, 1.0], "fac": [1, 1, 0], "shop": 0.5, "lit": [0.35, 0.65], "back": 0.85},
	"predmesti": {"h": [7.0, 15.0], "tower": 0.0, "w": [12.0, 24.0], "d": [12.0, 18.0], "gap": [2.0, 9.0], "fac": [2, 0, 0], "shop": 0.2, "lit": [0.2, 0.45], "back": 0.3},
	"prumysl": {"h": [8.0, 15.0], "tower": 0.0, "w": [28.0, 55.0], "d": [20.0, 30.0], "gap": [1.0, 8.0], "fac": [3, 3, 0], "shop": 0.06, "lit": [0.04, 0.12], "back": 0.35},
}

var map: CityMap
var rng := RandomNumberGenerator.new()
var ground_material: ShaderMaterial      # material silnic (mokro se meni podle dne/noci)
var building_count := 0
var lamp_count := 0
var sign_count := 0
var activate_ms_max := 0.0               # mereni: jak dlouho trva nacteni jedne dlazdice detailu
var activate_ms_sum := 0.0
var activate_count := 0
var _mats := {}
var _facade_mats := {}
var _grid := {}                           # prostorova mrizka obrysu (domy, koridory ulic)
var _node_ends := {}                      # "krizovatka:ulice" -> [levy roh, pravy roh] konce vozovky
var _chunks := {}                         # Vector2i -> zaznam dlazdice (domy, lampy, cedule, drobnosti)
var _tools := {}                          # "druh:dlazdice" -> SurfaceTool (sit se sklada po dlazdicich)
var _active := {}                         # Vector2i -> Node3D s nactenymi detaily
var _queue: Array[Vector2i] = []
var _jobs: Array = []                     # rozpracovane nacitani: [koren dlazdice, druh, data]
var _lamp_meshes := {}
var _unit_box: BoxMesh
var _rim_material: ShaderMaterial
var _scan_timer := 0.0
var _static_holder: Node3D


func build() -> void:
	rng.seed = 2427
	map = CityMap.new()
	_unit_box = BoxMesh.new()
	_static_holder = Node3D.new()
	_static_holder.name = "Site"
	add_child(_static_holder)
	_build_ground()
	_build_roads()
	_build_walls()
	_build_buildings()
	_build_lots()
	_collect_street_lamps()
	_collect_street_props()
	_commit_meshes()
	_commit_buildings()
	_prepare_lamp_meshes()
	if OS.get_cmdline_user_args().has("--statistika"):
		print("[MESTO] krizovatek %d, ulic %d, domu %d, lamp %d, cedul %d, dlazdic %d" % [
			map.nodes.size(), map.polylines.size(), building_count, lamp_count, sign_count, _chunks.size()])


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
func place_prop(prop: String, pos: Vector3, yaw: float, dynamic: bool, mass := 30.0, parent: Node = self) -> Node3D:
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
	parent.add_child(body)
	body.position = pos + Vector3(0, 0.02, 0)
	body.rotation.y = yaw
	return body


func _multimesh(mesh: Mesh, mat: Material, parent: Node, colors := false, custom := false) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.use_custom_data = custom
	mm.mesh = mesh
	mmi.multimesh = mm
	mmi.material_override = mat
	parent.add_child(mmi)
	return mmi


func _fill_multimesh(mmi: MultiMeshInstance3D, xforms: Array[Transform3D]) -> void:
	mmi.multimesh.instance_count = xforms.size()
	for i in xforms.size():
		mmi.multimesh.set_instance_transform(i, xforms[i])


static func v3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


static func chunk_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / CHUNK)), int(floor(p.y / CHUNK)))


## Zaznam dlazdice (vytvori se pri prvnim pouziti).
func _chunk(p: Vector2) -> Dictionary:
	var key := chunk_of(p)
	if not _chunks.has(key):
		_chunks[key] = {"b_xf": [[], [], [], []], "b_col": [[], [], [], []], "b_cus": [[], [], [], []],
			"rim_xf": [], "rim_col": [], "lamps": [], "signs": [], "props": []}
	return _chunks[key]


## SurfaceTool pro dany druh site (silnice, obrubnik, plot...) v dlazdici, kam patri bod p.
func _tool(kind: String, p: Vector2) -> SurfaceTool:
	var key := "%s:%s" % [kind, chunk_of(p)]
	if not _tools.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[key] = st
	return _tools[key]


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



## Svisla stena (plot, zabradli, protihlukova stena) mezi dvema body; inward = smer od ulice.
func _fence(a: Vector2, b: Vector2, inward: Vector2, height: float, kind := "plot") -> void:
	if a.distance_to(b) < 0.8:
		return
	var st := _tool(kind, (a + b) * 0.5)
	var thick := 0.4
	var base := height - 0.4 if kind == "pruh" else 0.0
	var a0 := v3(a, base)
	var b0 := v3(b, base)
	var a1 := v3(a, height)
	var b1 := v3(b, height)
	var a2 := v3(a + inward * thick, height)
	var b2 := v3(b + inward * thick, height)
	var n_front := v3(-inward)
	for quad in [[a0, b0, b1, a1, n_front], [a1, b1, b2, a2, Vector3.UP]]:
		var n: Vector3 = quad[4]
		for tri in [[quad[0], quad[1], quad[2]], [quad[0], quad[2], quad[3]]]:
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
#  Zem a silnice
# ---------------------------------------------------------------------

func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Zem"
	add_child(body)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(14000, 2, 14000)
	cs.shape = shape
	cs.position = Vector3(0, -1, 0)
	body.add_child(cs)
	# Dlazba (chodniky a vnitrky bloku); silnice lezi tesne nad ni
	var plane := PlaneMesh.new()
	plane.size = Vector2(14000, 14000)
	var mi := mesh_at(plane, pbr("concrete_pavement", 0.3, Color(0.8, 0.8, 0.86)), Vector3(0, -0.02, 0), body)
	mi.name = "Dlazba"
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_roads() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/road.gdshader")
	mat.set_shader_parameter("asphalt_albedo", load("res://assets/textures/asphalt_02/asphalt_02_diff.jpg"))
	mat.set_shader_parameter("asphalt_normal", load("res://assets/textures/asphalt_02/asphalt_02_nor.jpg"))
	mat.set_shader_parameter("asphalt_rough", load("res://assets/textures/asphalt_02/asphalt_02_rough.jpg"))
	mat.set_shader_parameter("puddle_noise", noise_texture(0.02, 512, 7))
	ground_material = mat

	var y := 0.02
	for e in map.polylines.size():
		var w: float = map.half_width[e]
		var axis := map.trimmed(e)
		if axis.size() < 2:
			push_warning("Ulice %d je po zkraceni prazdna" % e)
			continue
		var left := CityMap.offset_polyline(axis, -w)
		var right := CityMap.offset_polyline(axis, w)
		var total := CityMap.polyline_length(axis)
		var along := 0.0
		for i in axis.size() - 1:
			var st := _tool("silnice", (axis[i] + axis[i + 1]) * 0.5)
			st.set_color(Color(w / 32.0, 1.0, 0.0))
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
		_node_ends["%d:%d" % [map.edge_a[e], e]] = [left[0], right[0]]
		_node_ends["%d:%d" % [map.edge_b[e], e]] = [right[last], left[last]]
		# Obrubniky podel vozovky
		for side in [-1, 1]:
			if not map.is_open(e, side):
				var line := left if side < 0 else right
				for i in line.size() - 1:
					_curb_strip(_tool("obrubnik", line[i]), PackedVector2Array([line[i], line[i + 1]]), float(side))

	# Plochy krizovatek
	for id in map.nodes.size():
		var arr: Array = map.node_edges[id]
		if arr.is_empty():
			continue
		var st := _tool("silnice", map.nodes[id])
		st.set_color(Color(0.0, 0.0, 0.0))
		var poly: Array[Vector2] = []
		var curb_runs := []
		for k in arr.size():
			var key := "%d:%d" % [id, arr[k].e]
			if not _node_ends.has(key):
				continue
			var ends: Array = _node_ends[key]
			poly.append(ends[0])
			poly.append(ends[1])
			# Roh mezi touto a dalsi ulici: u ostre zatacky (vnejsi strana) se prida spicka,
			# aby asfalt dosahl az k obrubniku
			var e_a: int = arr[k].e
			var e_b: int = arr[(k + 1) % arr.size()].e
			var a_right_side := 1 if arr[k].start else -1
			var b_left_side := -1 if arr[(k + 1) % arr.size()].start else 1
			var open := map.is_open(e_a, a_right_side) or map.is_open(e_b, b_left_side)
			var run := [ends[1]]
			if map.corner_angle(id, k) > PI * 1.1:
				var tip := map.corner(id, k, 0.0)
				poly.append(tip)
				run.append(tip)
			curb_runs.append([run, open])
		var center := v3(map.nodes[id], y)
		for i in poly.size():
			_tri_up(st, center, v3(poly[i], y), v3(poly[(i + 1) % poly.size()], y))
		# Obrubnik pres roh bloku (mezi sousednimi ulicemi)
		var count := curb_runs.size()
		for k in count:
			var run: Array = curb_runs[k][0]
			if curb_runs[k][1] or arr.size() < 2:
				continue
			var next_key := "%d:%d" % [id, arr[(k + 1) % arr.size()].e]
			if not _node_ends.has(next_key):
				continue
			run.append(_node_ends[next_key][0])
			for i in run.size() - 1:
				var p0: Vector2 = run[i]
				var p1: Vector2 = run[i + 1]
				if p0.distance_to(p1) > 0.3:
					_curb_strip(_tool("obrubnik", p0), PackedVector2Array([p0, p1]), 1.0)


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



## Vsechny poskladane site (silnice, obrubniky, ploty) se ulozi jako jeden objekt na dlazdici.
func _commit_meshes() -> void:
	var mats := {
		"silnice": ground_material,
		"obrubnik": simple(Color(0.55, 0.55, 0.58), 0.0, 0.85),
		"plot": pbr("concrete_floor_worn_001", 0.25, Color(0.62, 0.62, 0.66)),
		"zabradli": pbr("concrete_floor_worn_001", 0.4, Color(0.75, 0.74, 0.7)),
		"bariera": pbr("concrete_tile_facade", 0.2, Color(0.82, 0.84, 0.9)),
		"pruh": simple(Color(1.0, 0.55, 0.12), 0.0, 0.4, 2.0),
	}
	for key: String in _tools:
		var kind := key.get_slice(":", 0)
		var mi := MeshInstance3D.new()
		mi.mesh = (_tools[key] as SurfaceTool).commit()
		mi.material_override = mats[kind]
		if kind == "silnice" or kind == "obrubnik":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if kind != "silnice":
			mi.visibility_range_end = 900.0
		_static_holder.add_child(mi)
	_tools.clear()


# ---------------------------------------------------------------------
#  Zdi (kolize): jedna spojita sit kolem vsech bloku
# ---------------------------------------------------------------------

func _build_walls() -> void:
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
	# Koridory ulic (vozovka + chodniky): do nich dum nesmi zasahnout
	for e in map.polylines.size():
		var pl := map.polylines[e]
		for i in pl.size() - 1:
			var d := (pl[i + 1] - pl[i])
			_grid_add(_obb((pl[i] + pl[i + 1]) * 0.5, d.normalized(), d.length() * 0.5 + 1.0, map.half_width[e] + CityMap.SIDEWALK - 0.4))
	for e in map.polylines.size():
		var style: Dictionary = STYLES[map.edge_district[e]]
		for side in [-1, 1]:
			var kind := map.side_type(e, side)
			if map.is_open(e, side):
				continue
			var line := map.block_line(e, side, CityMap.SIDEWALK + 0.25)
			if kind == "reka":
				# Nabrezi a mosty: nizke zabradli, za nim voda
				for i in line.size() - 1:
					var dir := (line[i + 1] - line[i]).normalized()
					_fence(line[i], line[i + 1], CityMap.right_of(dir) * side, 1.1, "zabradli")
				continue
			if map.edge_class[e] == "dalnice":
				# Mestska dalnice: protihlukove steny misto domu
				for i in line.size() - 1:
					var dir := (line[i + 1] - line[i]).normalized()
					var inw: Vector2 = CityMap.right_of(dir) * side
					_fence(line[i], line[i + 1], inw, 5.0, "bariera")
					# Svitici pruh na hrane steny (vede oko v rychlosti, v noci osvetluje dalnici)
					_fence(line[i] - inw * 0.03, line[i + 1] - inw * 0.03, inw, 5.25, "pruh")
				continue
			for i in line.size() - 1:
				_fill_frontage(line[i], line[i + 1], float(side), style)


## Zaplni usek ulicni cary domy (od bodu p k bodu q; domy stoji na strane side od smeru p->q).
## Kde se dum nevejde, postavi se plot (aby neviditelna zed nikdy nebyla "ve vzduchu").
func _fill_frontage(p: Vector2, q: Vector2, side: float, style: Dictionary) -> void:
	var length := p.distance_to(q)
	if length < 0.5:
		return
	var dir := (q - p) / length
	var inward := CityMap.right_of(dir) * side
	var s := 0.3
	var fence_from := 0.0
	var w_range: Array = style.w
	var d_range: Array = style.d
	var gap: Array = style.gap
	while s < length - 5.0:
		var width := minf(rng.randf_range(w_range[0], w_range[1]), length - s - 0.3)
		if length - s - width < 7.0:
			width = length - s - 0.3
		var placed := false
		for attempt in [[width, rng.randf_range(d_range[0], d_range[1])], [width, 11.0], [minf(width, 12.0), 9.0], [minf(width, 8.0), 6.5]]:
			var wd: float = attempt[0]
			var depth: float = attempt[1]
			if wd < 4.5:
				continue
			var center := p + dir * (s + wd * 0.5) + inward * (depth * 0.5)
			var o := _obb(center, dir, wd * 0.5 - 0.1, depth * 0.5 - 0.1)
			if _grid_free(o):
				_grid_add(_obb(center, dir, wd * 0.5 + 0.4, depth * 0.5 + 0.4))
				_make_building(center, dir, inward, wd, depth, style, false)
				# Druha rada: vyssi dum ve vnitrobloku (aby mezi domy nebylo videt prazdno)
				if depth > 10.0 and rng.randf() < float(style.back):
					var bw := rng.randf_range(18.0, 32.0)
					var bd := rng.randf_range(18.0, 30.0)
					var bc := center + inward * (depth * 0.5 + 3.0 + bd * 0.5)
					if _grid_free(_obb(bc, dir, bw * 0.5, bd * 0.5)):
						_grid_add(_obb(bc, dir, bw * 0.5 + 0.4, bd * 0.5 + 0.4))
						_make_building(bc, dir, inward, bw, bd, style, true)
				if s - fence_from > 1.2:
					_fence(p + dir * fence_from, p + dir * s, inward, 2.6)
				s += wd
				fence_from = s
				s += rng.randf_range(gap[0], gap[1])
				placed = true
				break
		if not placed:
			s += 4.0
	if length - fence_from > 1.2:
		_fence(p + dir * fence_from, q, inward, 2.6)


func _facade_material(index: int) -> ShaderMaterial:
	if not _facade_mats.has(index):
		var facade: String = FACADES[index]
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/building.gdshader")
		mat.set_shader_parameter("wall_albedo", load("res://assets/textures/%s/%s_diff.jpg" % [facade, facade]))
		mat.set_shader_parameter("wall_normal", load("res://assets/textures/%s/%s_nor.jpg" % [facade, facade]))
		mat.set_shader_parameter("wall_scale", 0.35 if facade == "red_brick" else (0.12 if facade == "container_side" else 0.22))
		_facade_mats[index] = mat
	return _facade_mats[index]


## Jeden dum: zaznam do dlazdice (kvadr s fasadou), obcas neon na strese, cedule nebo billboard.
func _make_building(center: Vector2, dir: Vector2, inward: Vector2, width: float, depth: float, style: Dictionary, back_row: bool) -> void:
	building_count += 1
	var ch := _chunk(center)
	var h_range: Array = style.h
	var height := rng.randf_range(h_range[0], h_range[1])
	if float(style.tower) > 0.0 and rng.randf() < 0.3:
		height += rng.randf() * rng.randf() * float(style.tower)
	if depth < 10.0:
		height = minf(height, rng.randf_range(7.0, 14.0))
	if back_row:
		height = height * 1.25 + rng.randf_range(5.0, 18.0)
	var fac: Array = style.fac
	var facade: int = fac[rng.randi() % fac.size()]
	var basis := Basis(Vector3.UP, -atan2(dir.y, dir.x)).scaled_local(Vector3(width, height, depth))
	ch.b_xf[facade].append(Transform3D(basis, Vector3(center.x, height * 0.5, center.y)))
	var tints := [Color(1, 1, 1), Color(0.75, 0.78, 0.85), Color(0.9, 0.82, 0.75), Color(0.6, 0.62, 0.7)]
	var tint: Color = tints[rng.randi() % tints.size()]
	var lit: Array = style.lit
	ch.b_col[facade].append(Color(tint.r, tint.g, tint.b, rng.randf_range(lit[0], lit[1])))
	ch.b_cus[facade].append(Color(rng.randf() * 100.0, rng.randf_range(2.6, 3.8), rng.randf_range(3.2, 3.8), rng.randf()))

	# Neonovy pruh pod strechou
	if height > 14.0 and rng.randf() < (0.5 if back_row and height > 45.0 else 0.3):
		var rim_basis := Basis(Vector3.UP, -atan2(dir.y, dir.x)).scaled_local(Vector3(width + 0.25, 0.24, depth + 0.25))
		ch.rim_xf.append(Transform3D(rim_basis, Vector3(center.x, height - rng.randf_range(0.4, 2.0), center.y)))
		ch.rim_col.append(NEON[rng.randi() % NEON.size()])
	if back_row:
		return

	# Cedule na fasade k ulici (vytvori se, az kdyz je hrac pobliz)
	var out := -inward
	var yaw_deg := rad_to_deg(atan2(out.x, out.y))
	var front := center + out * (depth * 0.5 + 0.08)
	if width >= 9.0 and rng.randf() < float(style.shop):
		var off := rng.randf_range(-width * 0.2, width * 0.2)
		ch.signs.append(["shop", v3(front + dir * off, 5.5), yaw_deg, minf(width * 0.6, 14.0)])
		sign_count += 1
	if height > 20.0 and rng.randf() < 0.12:
		var corner_off := (width * 0.5 - 1.2) * (1.0 if rng.randf() < 0.5 else -1.0)
		ch.signs.append(["blade", v3(front + dir * corner_off, rng.randf_range(9.0, 13.0)), yaw_deg])
		sign_count += 1
	if height < 40.0 and width >= 15.0 and depth > 10.0 and rng.randf() < 0.08:
		ch.signs.append(["billboard", Vector3(center.x, height + 3.8, center.y), yaw_deg])
		sign_count += 1


func _commit_buildings() -> void:
	var holder := Node3D.new()
	holder.name = "Domy"
	add_child(holder)
	_rim_material = ShaderMaterial.new()
	_rim_material.shader = load("res://shaders/neon_rim.gdshader")
	for key: Vector2i in _chunks:
		var ch: Dictionary = _chunks[key]
		for f in FACADES.size():
			var xf: Array = ch.b_xf[f]
			if xf.is_empty():
				continue
			var mmi := _multimesh(_unit_box, _facade_material(f), holder, true, true)
			var mm := mmi.multimesh
			mm.instance_count = xf.size()
			for i in xf.size():
				mm.set_instance_transform(i, xf[i])
				mm.set_instance_color(i, ch.b_col[f][i])
				mm.set_instance_custom_data(i, ch.b_cus[f][i])
			mmi.visibility_range_end = BUILDING_VIEW
			mmi.visibility_range_end_margin = 60.0
		if not (ch.rim_xf as Array).is_empty():
			var rmi := _multimesh(_unit_box, _rim_material, holder, true, false)
			rmi.multimesh.instance_count = ch.rim_xf.size()
			for i in ch.rim_xf.size():
				rmi.multimesh.set_instance_transform(i, ch.rim_xf[i])
				rmi.multimesh.set_instance_color(i, ch.rim_col[i])
			rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			rmi.visibility_range_end = 900.0
		# uz nejsou potreba
		ch.erase("b_xf")
		ch.erase("b_col")
		ch.erase("b_cus")
		ch.erase("rim_xf")
		ch.erase("rim_col")
	_grid.clear()


# ---------------------------------------------------------------------
#  Volne plochy: reka, treninkove plochy, parkoviste, namesti
# ---------------------------------------------------------------------

func _polygon_mesh(st: SurfaceTool, poly: PackedVector2Array, y: float) -> bool:
	var idx := Geometry2D.triangulate_polygon(poly)
	if idx.is_empty():
		return false
	for i in range(0, idx.size(), 3):
		_tri_up(st, v3(poly[idx[i]], y), v3(poly[idx[i + 1]], y), v3(poly[idx[i + 2]], y))
	return true


func _build_lots() -> void:
	var holder := Node3D.new()
	holder.name = "Plochy"
	add_child(holder)
	var water := SurfaceTool.new()
	water.begin(Mesh.PRIMITIVE_TRIANGLES)
	var asphalt := SurfaceTool.new()
	asphalt.begin(Mesh.PRIMITIVE_TRIANGLES)
	asphalt.set_color(Color(0.0, 0.0, 0.0))
	var plaza := SurfaceTool.new()
	plaza.begin(Mesh.PRIMITIVE_TRIANGLES)
	var training := 0
	for lot: Dictionary in map.lots:
		if lot.typ == "reka":
			if not _polygon_mesh(water, map.lot_polygon(lot, CityMap.SIDEWALK + 0.3), 0.0):
				push_warning("Vodni plochu u %s se nepodarilo vyplnit" % lot.stred)
			continue
		var poly := map.lot_polygon(lot, -0.3)
		var inner := map.lot_polygon(lot, 7.0)
		if not _polygon_mesh(plaza if lot.typ == "namesti" else asphalt, poly, 0.012):
			push_warning("Plochu u %s se nepodarilo vyplnit" % lot.stred)
			continue
		var c: Vector2 = lot.stred
		var inside := func(p: Vector2) -> bool: return Geometry2D.is_point_in_polygon(p, inner)
		if not inside.call(c):
			c = Vector2.ZERO
			for p in inner:
				c += p / inner.size()
		match lot.typ:
			"trenink":
				_training_lot(holder, c, inside, training)
				training += 1
			"plocha":
				_parking_lot(holder, c, inside)
			"namesti":
				_plaza(holder, c)
		# Vysoke lampy na plose
		var step := 55.0 if lot.typ != "namesti" else 38.0
		for ix in range(-6, 7):
			for iz in range(-6, 7):
				var lp := c + Vector2(ix * step, iz * step + step * 0.5)
				if inside.call(lp):
					_chunk(lp).lamps.append({"xf": Transform3D(Basis(), v3(lp)), "tall": true})
					lamp_count += 1
	var wm := ShaderMaterial.new()
	wm.shader = load("res://shaders/water.gdshader")
	wm.set_shader_parameter("ripple", _ripple_texture())
	for item in [[water, wm, "Reka"], [asphalt, ground_material, "Asfalt"], [plaza, pbr("concrete_pavement", 0.22, Color(0.95, 0.86, 0.74)), "Namesti"]]:
		var mi := MeshInstance3D.new()
		mi.name = item[2]
		mi.mesh = (item[0] as SurfaceTool).commit()
		mi.material_override = item[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)


func _ripple_texture() -> NoiseTexture2D:
	var tex := noise_texture(0.03, 512, 31)
	tex.as_normal_map = true
	tex.bump_strength = 6.0
	return tex


## Treninkova plocha: sklad, rampy, kontejnery, slalom ze zabran, sudy a bedny.
func _training_lot(holder: Node3D, c: Vector2, inside: Callable, index: int) -> void:
	var shutter := pbr("painted_metal_shutter", 0.25, Color(0.6, 0.65, 0.75))
	var wh_pos := c + Vector2(-70, -30)
	var wh := Vector3(16, 11, 70)
	var fits := true
	for corner in [Vector2(-10, -37), Vector2(10, -37), Vector2(-10, 37), Vector2(14, 37)]:
		fits = fits and inside.call(wh_pos + corner)
	if fits:
		static_box(wh, Transform3D(Basis(), v3(wh_pos, wh.y * 0.5)), pbr("container_side", 0.12, Color(0.35, 0.38, 0.45)), holder)
		for i in 3:
			var dz := -22.0 + i * 22.0
			static_box(Vector3(0.2, 5, 8), Transform3D(Basis(), v3(wh_pos + Vector2(wh.x * 0.5 + 0.1, dz), 2.5)), shutter, holder, false)
			var lamp := BoxMesh.new()
			lamp.size = Vector3(0.6, 0.15, 1.2)
			mesh_at(lamp, simple(Color(1.0, 0.85, 0.6), 0.0, 0.3, 8.0), v3(wh_pos + Vector2(wh.x * 0.5 + 0.5, dz), 5.6), holder)
		var title: String = ["NITRO GARÁŽ", "DRIFT ARÉNA", "TEST ZÓNA"][index % 3]
		_chunk(wh_pos).signs.append(["big", title, "stencil", v3(wh_pos + Vector2(wh.x * 0.5 + 0.2, 0), 8.6), 90.0, 0.05, NEON[index % NEON.size()], 220])
	if inside.call(c + Vector2(0, -95)):
		_chunk(c + Vector2(0, -95)).signs.append(["big", "NEON WRECK", "monoton", v3(c + Vector2(0, -95), 9.0), 0.0, 0.06, NEON[1], 260])

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
			_chunk(bp).props.append(["concrete_road_barrier", v3(bp), rng.randf_range(-0.3, 0.3), false, 0.0])
	for i in 14:
		var bp := c + Vector2(55 + rng.randf_range(-10, 10), 5 + rng.randf_range(-10, 10))
		if inside.call(bp):
			_chunk(bp).props.append(["Barrel_01", v3(bp), rng.randf() * TAU, true, 40.0])
	for i in 8:
		var bp := c + Vector2(-25 + rng.randf_range(-6, 6), 45 + rng.randf_range(-6, 6))
		if inside.call(bp):
			_chunk(bp).props.append(["wooden_crate_01", v3(bp), rng.randf() * TAU, true, 15.0])


## Mensi volna plocha (parkoviste, dvur): par kontejneru, zabran a beden.
func _parking_lot(holder: Node3D, c: Vector2, inside: Callable) -> void:
	var cont_tints := [Color(0.7, 0.2, 0.15), Color(0.15, 0.35, 0.65), Color(0.2, 0.5, 0.3), Color(0.75, 0.55, 0.15)]
	for i in 3:
		var cp := c + Vector2(rng.randf_range(-45, 45), rng.randf_range(-45, 45))
		if inside.call(cp) and inside.call(cp + Vector2(5, 5)) and inside.call(cp - Vector2(5, 5)):
			static_box(Vector3(2.5, 2.6, 6.1), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), v3(cp, 1.3)), pbr("container_side", 0.33, cont_tints[rng.randi() % cont_tints.size()]), holder)
	for i in 6:
		var bp := c + Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))
		if inside.call(bp):
			_chunk(bp).props.append(["wooden_crate_01" if i % 2 == 0 else "Barrel_01", v3(bp), rng.randf() * TAU, true, 20.0])


## Namesti ve starem meste: pomnik se svitici korunou.
func _plaza(holder: Node3D, c: Vector2) -> void:
	static_box(Vector3(6, 1.2, 6), Transform3D(Basis(), v3(c, 0.6)), pbr("concrete_floor_worn_001", 0.4, Color(0.7, 0.68, 0.62)), holder)
	var column := CylinderMesh.new()
	column.top_radius = 0.7
	column.bottom_radius = 1.0
	column.height = 14.0
	mesh_at(column, pbr("concrete_floor_worn_001", 0.5, Color(0.8, 0.78, 0.72)), v3(c, 8.2), holder)
	for i in 3:
		var ring := TorusMesh.new()
		ring.inner_radius = 1.2 + i * 0.5
		ring.outer_radius = 1.35 + i * 0.5
		mesh_at(ring, simple(NEON[i], 0.0, 0.3, 6.0), v3(c, 15.6 - i * 0.9), holder)


# ---------------------------------------------------------------------
#  Poulicni lampy a drobnosti: jen zaznamy; skutecne objekty vznikaji v okoli kamery
# ---------------------------------------------------------------------

func _collect_street_lamps() -> void:
	for e in map.polylines.size():
		var w: float = map.half_width[e]
		var axis := map.trimmed(e)
		if axis.size() < 2:
			continue
		var total := CityMap.polyline_length(axis)
		var count := int(total / 46.0)
		for k in count:
			var dist := total * (k + 0.5) / count
			var side := 1.0 if (k + e) % 2 == 0 else -1.0
			var pd := CityMap.point_at(axis, dist)
			var dir: Vector2 = pd[1]
			var p: Vector2 = pd[0] + CityMap.right_of(dir) * side * (w + 0.9)
			var to_road := -CityMap.right_of(dir) * side
			_chunk(p).lamps.append({"xf": Transform3D(Basis.looking_at(v3(to_road), Vector3.UP), v3(p, 0.06)), "tall": false})
			lamp_count += 1


func _collect_street_props() -> void:
	for e in map.polylines.size():
		if map.edge_class[e] == "dalnice":
			continue
		var w: float = map.half_width[e]
		var axis := map.trimmed(e)
		if axis.size() < 2:
			continue
		var total := CityMap.polyline_length(axis)
		var count := int(total / 110.0)
		for k in count:
			if rng.randf() > 0.55:
				continue
			var side := 1 if rng.randf() < 0.5 else -1
			if map.side_type(e, side) != "":
				continue
			var pd := CityMap.point_at(axis, total * (k + rng.randf_range(0.2, 0.8)) / count)
			var p: Vector2 = pd[0] + CityMap.right_of(pd[1]) * side * (w + 2.4)
			if rng.randf() < 0.6:
				_chunk(p).props.append(["metal_trash_can", v3(p), rng.randf() * TAU, true, 20.0])
			else:
				_chunk(p).props.append(["fire_hydrant", v3(p), 0.0, true, 45.0])


func _prepare_lamp_meshes() -> void:
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
	_lamp_meshes = {"pole": pole_mesh, "arm": arm_mesh, "head": head_mesh, "glow": glow_mesh,
		"metal": simple(Color(0.22, 0.23, 0.25), 0.85, 0.35),
		"warm": simple(Color(1.0, 0.68, 0.38), 0.0, 0.3, 5.0), "cool": simple(Color(0.75, 0.88, 1.0), 0.0, 0.3, 5.0)}


# ---------------------------------------------------------------------
#  Nacitani detailu v okoli kamery
# ---------------------------------------------------------------------

func _process(delta: float) -> void:
	if map == null:
		return
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = 0.25
		_scan_chunks()
	# Nacitani po malych kouscich (nejvys ~2,5 ms za snimek), aby hra necukala
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < 2500:
		if _jobs.is_empty():
			if _queue.is_empty():
				break
			var key: Vector2i = _queue.pop_front()
			if _chunks.has(key) and not _active.has(key):
				_begin_chunk(key)
			continue
		_run_job(_jobs.pop_front())
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	activate_ms_max = maxf(activate_ms_max, ms)


func _chunk_distance(key: Vector2i, p: Vector2) -> float:
	var lo := Vector2(key) * CHUNK
	var q := p.clamp(lo, lo + Vector2(CHUNK, CHUNK))
	return p.distance_to(q)


func _scan_chunks() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var p := Vector2(cam.global_position.x, cam.global_position.z)
	for key: Vector2i in _active.keys():
		if _chunk_distance(key, p) > DETAIL_OFF:
			(_active[key] as Node).queue_free()
			_active.erase(key)
	var c := chunk_of(p)
	var reach := int(ceil(DETAIL_ON / CHUNK))
	var wanted: Array[Vector2i] = []
	for gx in range(c.x - reach, c.x + reach + 1):
		for gz in range(c.y - reach, c.y + reach + 1):
			var key := Vector2i(gx, gz)
			if _chunks.has(key) and not _active.has(key) and _chunk_distance(key, p) < DETAIL_ON:
				wanted.append(key)
	wanted.sort_custom(func(a, b): return _chunk_distance(a, p) < _chunk_distance(b, p))
	_queue = wanted


## Nacte hned vsechno v okoli bodu (pri startu a po presunu auta, aby nic nenaskakovalo).
func load_around(pos: Vector3) -> void:
	var p := Vector2(pos.x, pos.z)
	var c := chunk_of(p)
	var reach := int(ceil(DETAIL_ON / CHUNK))
	for gx in range(c.x - reach, c.x + reach + 1):
		for gz in range(c.y - reach, c.y + reach + 1):
			var key := Vector2i(gx, gz)
			if _chunks.has(key) and not _active.has(key) and _chunk_distance(key, p) < DETAIL_ON:
				_activate(key)


## Zalozi dlazdici detailu a naplanuje jeji naplneni po kouscich.
func _begin_chunk(key: Vector2i) -> void:
	var ch: Dictionary = _chunks[key]
	var root := Node3D.new()
	root.name = "Okoli_%d_%d" % [key.x, key.y]
	add_child(root)
	_active[key] = root
	activate_count += 1
	var lamps: Array = ch.lamps
	for i in range(0, lamps.size(), 6):
		_jobs.append([root, "lamps", lamps.slice(i, i + 6)])
	if not (ch.signs as Array).is_empty():
		var ns := NeonSigns.new()
		ns.rng.seed = hash(key)
		root.add_child(ns)
		for sdef: Array in ch.signs:
			_jobs.append([root, "sign", ns, sdef])
		_jobs.append([root, "signs_done", ns])
	for pr: Array in ch.props:
		_jobs.append([root, "prop", pr])


func _run_job(job: Array) -> void:
	var root: Node3D = job[0]
	if not is_instance_valid(root) or root.is_queued_for_deletion():
		return
	match job[1]:
		"lamps":
			_spawn_lamps(root, job[2])
		"sign":
			_make_sign(job[2], job[3])
		"signs_done":
			(job[2] as NeonSigns).set_view_distance(360.0)
		"prop":
			var pr: Array = job[2]
			place_prop(pr[0], pr[1], pr[2], pr[3], maxf(pr[4], 1.0), root)


func _make_sign(ns: NeonSigns, sdef: Array) -> void:
	match sdef[0]:
		"shop":
			ns.shop_sign(sdef[1], sdef[2], sdef[3])
		"blade":
			ns.blade_sign(sdef[1], sdef[2])
		"billboard":
			ns.billboard(sdef[1], sdef[2])
		"big":
			ns.big_text(sdef[1], sdef[2], sdef[3], sdef[4], sdef[5], sdef[6], sdef[7])


## Nacte dlazdici celou najednou (pri startu a po presunu auta).
func _activate(key: Vector2i) -> void:
	var before := _jobs.size()
	_begin_chunk(key)
	while _jobs.size() > before:
		_run_job(_jobs.pop_at(before))


func _spawn_lamps(root: Node3D, lamps: Array) -> void:
	if lamps.is_empty():
		return
	var lm := _lamp_meshes
	var mm_pole := _multimesh(lm.pole, lm.metal, root)
	var mm_arm := _multimesh(lm.arm, lm.metal, root)
	var mm_head := _multimesh(lm.head, lm.metal, root)
	var mm_glow_warm := _multimesh(lm.glow, lm.warm, root)
	var mm_glow_cool := _multimesh(lm.glow, lm.cool, root)
	var poles: Array[Transform3D] = []
	var arms: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	var glows_w: Array[Transform3D] = []
	var glows_c: Array[Transform3D] = []
	var warm := Color(1.0, 0.68, 0.38)
	var cool := Color(0.75, 0.88, 1.0)
	var fade: float = [70.0, 100.0, 130.0, 180.0][Graphics.quality]
	var i := 0
	for src: Dictionary in lamps:
		i += 1
		if src.get("down", false):
			continue
		var xf: Transform3D = src.xf
		var tall: bool = src.tall
		var h := 13.0 if tall else 9.0
		var s := h / 9.0
		poles.append(Transform3D(xf.basis.scaled(Vector3(s, s, s)), xf.origin + Vector3(0, h * 0.5, 0)))
		var heads_local := [Vector3(0, h, -1.9)] if not tall else [Vector3(0, h, -1.9), Vector3(0, h, 1.9)]
		var is_warm := (i + int(xf.origin.x)) % 5 != 0
		# Zaznam lampy: indexy v MultiMeshich a svetla (aby sla lampa porazit)
		var rec := {"pole": poles.size() - 1, "arms": [], "heads": [], "glows": [], "lights": [], "xf": xf, "h": h, "src": src,
			"mm_pole": mm_pole, "mm_arm": mm_arm, "mm_head": mm_head, "glow_mm": mm_glow_warm if is_warm else mm_glow_cool}
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
			spot.distance_fade_begin = fade
			spot.distance_fade_length = 40.0
			spot.position = head_pos - Vector3(0, 0.2, 0)
			spot.rotation_degrees = Vector3(-90, 0, 0)
			spot.visible = not Hra.daylight
			spot.add_to_group("street_lights")
			root.add_child(spot)
			rec.lights.append(spot)
		# Kolize sloupu (v male rychlosti sloup auto zastavi)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.18
		shape.height = h
		cs.shape = shape
		body.add_child(cs)
		root.add_child(body)
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
		root.add_child(area)
		area.position = xf.origin + Vector3(0, 1.0, 0)
		area.body_entered.connect(_on_lamp_hit.bind(rec, area))
	_fill_multimesh(mm_pole, poles)
	_fill_multimesh(mm_arm, arms)
	_fill_multimesh(mm_head, heads)
	_fill_multimesh(mm_glow_warm, glows_w)
	_fill_multimesh(mm_glow_cool, glows_c)


## Auto v rychlosti porazi lampu: sloup odleti jako fyzicky objekt, svetlo zhasne.
func _on_lamp_hit(hit_body: Node3D, rec: Dictionary, area: Area3D) -> void:
	var rb := hit_body as RigidBody3D
	if rb == null or not rb.is_in_group("cars") or rec.get("down", false):
		return
	var v := rb.linear_velocity
	if v.length() < 7.0:
		return
	rec["down"] = true
	(rec.src as Dictionary)["down"] = true      # lampa zustane porazena i po znovunacteni okoli
	var zero := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -50, 0))
	(rec.mm_pole as MultiMeshInstance3D).multimesh.set_instance_transform(rec.pole, zero)
	for idx in rec.arms:
		(rec.mm_arm as MultiMeshInstance3D).multimesh.set_instance_transform(idx, zero)
	for idx in rec.heads:
		(rec.mm_head as MultiMeshInstance3D).multimesh.set_instance_transform(idx, zero)
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
	get_tree().create_timer(25.0).timeout.connect(func():
		if is_instance_valid(pole):
			pole.queue_free())
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
