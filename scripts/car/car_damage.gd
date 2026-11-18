class_name CarDamage
extends Node
## Demolice auta (faze 2):
##  1. promackliny - karoserie se v miste narazu promackne (posunou se vrcholy siti, natoci se normaly),
##  2. skla - kazde okno zvlast nejdriv praskne, pri dalsim narazu se rozbije a vysypou se strepy,
##  3. dily - dvere, kapota, kufr, narazniky a blatniky se nejdriv uvolni (plandaji na pantech)
##     a pri dalsim poskozeni odpadnou; pri vybuchu odleti vsechno.
## Car._on_impact vola hit(). Data pro promackliny (poloha vrcholu v mrizce) se pocitaji ve vlakne
## hned po postaveni auta, takze start auta nezdrzuji.

const CELL := 0.25            # bunka mrizky vrcholu (m)
const MAX_DENT := 0.32        # nejvetsi promacknuti jednoho mista (m)
const REBUILD_GAP := 0.1      # s - jak casto nejvys se jedna sit znovu sestavi
const PART_KEYS := ["kapota", "kufr", "dvere_lp", "dvere_pp", "dvere_lz", "dvere_pz",
	"naraznik_predni", "naraznik_zadni", "blatnik_l", "blatnik_p"]

var car: Car
var model: CarModel
var dents_ready := false
var dent_count := 0
var last_rebuild_ms := 0.0
var max_rebuild_ms := 0.0
var vertex_total := 0

var _meshes: Array = []       # deformovatelne site (viz _collect_meshes)
var _windows: Array = []      # okna (viz _split_glass)
var _parts: Array = []        # dily na pantech (viz _setup_parts)
var _task := -1
var _dent_task := -1          # vypocet promacklin bezi ve vlakne
var _queue: Array = []        # promackliny cekajici na vypocet
var _prev_vel := Vector3.ZERO
var _time := 0.0

static var _crack_tex: ImageTexture


func setup(c: Car) -> void:
	car = c
	crack_texture()
	model = c.model
	_split_glass()
	_collect_meshes()
	_setup_parts()
	_task = WorkerThreadPool.add_task(_build_grids, false, "promackliny")


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	_finish_dents()


func _finish_dents() -> void:
	if _dent_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_dent_task)
		_dent_task = -1


# ---------------------------------------------------------------------
#  Naraz
# ---------------------------------------------------------------------

## Naraz v bode pos (globalne) rychlosti dv (m/s).
func hit(pos: Vector3, dv: float) -> void:
	if model == null or not is_instance_valid(model):
		return
	var prah: float = car.t.prah_poskozeni
	var s := dv - prah * 0.6
	if s <= 0.0:
		return
	var tough := maxf(car.t.odolnost, 0.3)
	var lp := model.global_transform.affine_inverse() * pos
	var box := model.body_aabb
	var c := box.get_center()
	var dir := c - lp
	dir.y *= 0.35
	if lp.y > box.end.y - 0.2:
		dir = Vector3.DOWN          # naraz shora (prevraceni) promackne strechu
	if dir.length() < 0.01:
		dir = Vector3.DOWN
	dir = dir.normalized()
	# bod narazu na povrch karoserie (kontakt je na kolizni krabici)
	var pc := lp.clamp(box.position, box.end)
	var depth := clampf(s * 0.016, 0.015, 0.22) / sqrt(tough)
	var radius := clampf(0.38 + s * 0.035, 0.38, 1.15)
	_dent(pc, dir, radius, depth)
	var strength := s / tough
	_hit_windows(pc, strength)
	_hit_parts(pc, strength)


func _dent(c: Vector3, dir: Vector3, r: float, depth: float) -> void:
	_queue.append([c, dir, r, depth])


## Ve vlakne: vsechny cekajici promackliny.
func _run_dents(jobs: Array) -> void:
	for job: Array in jobs:
		_apply_dent(job[0], job[1], job[2], job[3])


func _apply_dent(c: Vector3, dir: Vector3, r: float, depth: float) -> void:
	dent_count += 1
	for rec: Dictionary in _meshes:
		if not rec.alive or rec.inner or not (rec.aabb as AABB).grow(r).has_point(c):
			continue
		var to_mesh: Basis = rec.to_mesh
		var n_to_car: Basis = rec.n_to_car
		var n_to_mesh: Basis = rec.n_to_mesh
		var changed := false
		for sf: Dictionary in rec.surfaces:
			var grid: Dictionary = sf.grid
			var pos: PackedVector3Array = sf.pos
			var orig: PackedVector3Array = sf.orig
			var arrays: Array = sf.arrays
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var has_n: bool = arrays[Mesh.ARRAY_NORMAL] != null
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if has_n else PackedVector3Array()
			var lo := Vector3i(floori((c.x - r) / CELL), floori((c.y - r) / CELL), floori((c.z - r) / CELL))
			var hi := Vector3i(floori((c.x + r) / CELL), floori((c.y + r) / CELL), floori((c.z + r) / CELL))
			var touched := false
			for gx in range(lo.x, hi.x + 1):
				for gy in range(lo.y, hi.y + 1):
					for gz in range(lo.z, hi.z + 1):
						var list: Variant = grid.get(Vector3i(gx, gy, gz))
						if list == null:
							continue
						for i: int in list:
							var p := pos[i]
							var d := p.distance_to(c)
							if d >= r:
								continue
							var q := 1.0 - d * d / (r * r)
							var wob := 1.0 + 0.35 * sin(p.x * 17.0 + p.z * 5.0) * sin(p.y * 19.0 + p.z * 13.0)
							var h := depth * q * q * wob
							var np := p + dir * h
							var off := np - orig[i]
							if off.length() > MAX_DENT:
								np = orig[i] + off.normalized() * MAX_DENT
							var moved := np - p
							if moved.length_squared() < 1e-10:
								continue
							pos[i] = np
							verts[i] += to_mesh * moved
							touched = true
							if has_n:
								# normala se nakloni podle sklonu promackliny (jinak by promacklina nebyla videt)
								var n := (n_to_car * norms[i]).normalized()
								var dh := -4.0 * depth * wob * d * q / (r * r)
								var grad := (p - c) / maxf(d, 0.001) * dh * dir.dot(n)
								var gt := grad - n * n.dot(grad)
								if gt.length() > 1.2:
									gt = gt.normalized() * 1.2
								norms[i] = (n_to_mesh * (n - gt)).normalized()
			if touched:
				sf.pos = pos
				arrays[Mesh.ARRAY_VERTEX] = verts
				if has_n:
					arrays[Mesh.ARRAY_NORMAL] = norms
				changed = true
		if changed:
			rec.dirty = true


func _process(delta: float) -> void:
	_time += delta
	if not dents_ready and _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		dents_ready = true
	if _dent_task >= 0:
		if not WorkerThreadPool.is_task_completed(_dent_task):
			return
		_finish_dents()
	if dents_ready and not _queue.is_empty():
		var jobs := _queue
		_queue = []
		_dent_task = WorkerThreadPool.add_task(_run_dents.bind(jobs), false, "promacklina")
		return
	for rec: Dictionary in _meshes:
		if rec.dirty and rec.alive and _time - float(rec.built) > REBUILD_GAP:
			_rebuild(rec)


func _rebuild(rec: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var mi: MeshInstance3D = rec.mi
	rec.dirty = false
	rec.built = _time
	if not is_instance_valid(mi):
		rec.alive = false
		return
	var am: ArrayMesh = rec.own
	if am == null:
		am = ArrayMesh.new()
		rec.own = am
	else:
		am.clear_surfaces()
	var k := 0
	for sf: Dictionary in rec.surfaces:
		am.add_surface_from_arrays(sf.prim, sf.arrays)
		am.surface_set_material(k, sf.mat)
		k += 1
	if mi.mesh != am:
		var over: Array = []
		for s in mi.get_surface_override_material_count():
			over.append(mi.get_surface_override_material(s))
		mi.mesh = am
		for s in mini(over.size(), am.get_surface_count()):
			mi.set_surface_override_material(s, over[s])
	last_rebuild_ms = (Time.get_ticks_usec() - t0) / 1000.0
	max_rebuild_ms = maxf(max_rebuild_ms, last_rebuild_ms)


# ---------------------------------------------------------------------
#  Priprava siti
# ---------------------------------------------------------------------

func _in_wheel(n: Node) -> bool:
	for w in model.wheels:
		if w.is_ancestor_of(n):
			return true
	return false


static func _clean(arrays: Array) -> Array:
	for k in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3, Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS]:
		arrays[k] = null
	return arrays


var _inner_box := AABB()


func _collect_meshes() -> void:
	vertex_total = 0
	_inner_box = model.body_aabb.grow(-0.22)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not (mi.mesh is ArrayMesh) or _in_wheel(mi):
			continue
		var xf := CarModel.xform_to(mi, model)
		var surfaces: Array = []
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays := _clean(mi.mesh.surface_get_arrays(s))
			vertex_total += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			surfaces.append({"arrays": arrays, "mat": mi.mesh.surface_get_material(s), "prim": Mesh.PRIMITIVE_TRIANGLES,
				"pos": PackedVector3Array(), "orig": PackedVector3Array(), "grid": {}})
		if surfaces.size() != mi.mesh.get_surface_count():
			continue      # site s jinym typem ploch (cary, body) se nepromackavaji
		_meshes.append({"mi": mi, "xf": xf, "to_mesh": xf.basis.inverse(), "n_to_car": xf.basis.inverse().transposed(),
			"n_to_mesh": xf.basis.transposed(), "surfaces": surfaces, "aabb": AABB(), "dirty": false, "built": -1.0,
			"own": null, "alive": true, "inner": false})


## Ve vlakne: poloha kazdeho vrcholu v souradnicich auta a mrizka pro rychle hledani.
func _build_grids() -> void:
	for rec: Dictionary in _meshes:
		var xf: Transform3D = rec.xf
		var lo := Vector3(INF, INF, INF)
		var hi := -lo
		for sf: Dictionary in rec.surfaces:
			var v: PackedVector3Array = (sf.arrays as Array)[Mesh.ARRAY_VERTEX]
			var pos := PackedVector3Array()
			pos.resize(v.size())
			var grid := {}
			for i in v.size():
				var p := xf * v[i]
				pos[i] = p
				lo = lo.min(p)
				hi = hi.max(p)
				var key := Vector3i(floori(p.x / CELL), floori(p.y / CELL), floori(p.z / CELL))
				var list: Variant = grid.get(key)
				if list == null:
					grid[key] = [i]
				else:
					(list as Array).append(i)
			sf.pos = pos
			sf.orig = pos.duplicate()
			sf.grid = grid
		if lo.x <= hi.x:
			rec.aabb = AABB(lo, hi - lo)
			# dily schovane uvnitr karoserie (motor, sedadla, palubni deska) se nepromackavaji
			rec.inner = _inner_box.encloses(rec.aabb)


# ---------------------------------------------------------------------
#  Skla
# ---------------------------------------------------------------------

const _NOT_GLASS := ["light", "lamp", "svetl", "lens", "signal", "blink", "indicator", "mirror", "chrome",
	"reflect", "head", "tail", "fog", "gauge", "dash"]


func _is_glass(mat: Material, mi: MeshInstance3D, s: int) -> bool:
	if mat == null:
		return false
	var sklo: Variant = CarModel._shared.get("sklo")
	var kryt: Variant = CarModel._shared.get("svetlo_kryt")
	if mat == sklo:
		return true
	if mat == kryt:
		return true       # kryty svetel: okny se stanou jen velke kusy (viz _split_glass)
	if mat == model.tail_mat or mat == model.head_mat or mat == model.paint:
		return false
	var name_ := (String(mi.name) + "|" + mat.resource_name + "|" + (mi.mesh.surface_get_material(s).resource_name if mi.mesh.surface_get_material(s) else "")).to_lower()
	for bad in _NOT_GLASS:
		if name_.contains(bad):
			return false
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		if bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and bm.albedo_color.a < 0.97:
			return true
	for good in ["glass", "window", "windshield", "sklo", "vidrio", "glas"]:
		if name_.contains(good):
			return true
	return false


## Sklo kazde site se rozdeli na jednotliva okna (souvisle kusy), aby kazde mohlo prasknout zvlast.
func _split_glass() -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if not (mi.mesh is ArrayMesh) or _in_wheel(mi) or String(mi.name).begins_with("Okno"):
			continue
		var glass: Array[int] = []
		for s in mi.mesh.get_surface_count():
			if mi.mesh.surface_get_primitive_type(s) == Mesh.PRIMITIVE_TRIANGLES and _is_glass(mi.get_active_material(s), mi, s):
				glass.append(s)
		if glass.is_empty():
			continue
		var xf := CarModel.xform_to(mi, model)
		var scale_f := xf.basis.get_scale().x
		var keep := ArrayMesh.new()
		var keep_over: Array = []
		for s in mi.mesh.get_surface_count():
			var arrays := _clean(mi.mesh.surface_get_arrays(s))
			var active := mi.get_active_material(s)
			if s in glass:
				var small := PackedInt32Array()
				var only_big: bool = active == CarModel._shared.get("svetlo_kryt")
				for comp: PackedInt32Array in _components(arrays, xf):
					var sub := _compact(arrays, comp)
					if only_big:
						var cb := xf * _aabb_of_arrays(sub)
						var cd := [cb.size.x, cb.size.y, cb.size.z]
						cd.sort()
						if float(cd[1]) * float(cd[2]) < 0.12:
							small.append_array(comp)
							continue
					var am := ArrayMesh.new()
					am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sub)
					am.surface_set_material(0, active)
					var w := MeshInstance3D.new()
					w.name = "Okno%d" % _windows.size()
					w.mesh = am
					w.cast_shadow = mi.cast_shadow
					mi.get_parent().add_child(w)
					w.transform = mi.transform
					var box := xf * am.get_aabb()
					var dims := [box.size.x, box.size.y, box.size.z]
					dims.sort()
					_windows.append({"mi": w, "center": box.get_center(), "box": box, "area": float(dims[1]) * float(dims[2]),
						"state": 0, "acc": 0.0, "scale": scale_f})
				if not small.is_empty():
					var rest := arrays.duplicate()
					rest[Mesh.ARRAY_INDEX] = small
					keep.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, rest)
					keep.surface_set_material(keep.get_surface_count() - 1, mi.mesh.surface_get_material(s))
					keep_over.append(mi.get_surface_override_material(s))
			else:
				var prim: Mesh.PrimitiveType = mi.mesh.surface_get_primitive_type(s)
				keep.add_surface_from_arrays(prim, arrays)
				keep.surface_set_material(keep.get_surface_count() - 1, mi.mesh.surface_get_material(s))
				keep_over.append(mi.get_surface_override_material(s))
		mi.mesh = keep if keep.get_surface_count() > 0 else null
		for k in keep_over.size():
			mi.set_surface_override_material(k, keep_over[k])
	# predni a zadni sklo (nejvetsi plochy) jsou lepena - vydrzi vic
	var areas: Array = []
	for w: Dictionary in _windows:
		areas.append(w.area)
	areas.sort()
	var big: float = areas[maxi(areas.size() - 2, 0)] if not areas.is_empty() else INF
	for w: Dictionary in _windows:
		w.tough = 1.7 if float(w.area) >= big * 0.999 else 1.0


static func _aabb_of_arrays(arrays: Array) -> AABB:
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if v.is_empty():
		return AABB()
	var box := AABB(v[0], Vector3.ZERO)
	for p in v:
		box = box.expand(p)
	return box


## Souvisle kusy site (trojuhelniky spojene hranou nebo stejnou polohou vrcholu) -> seznamy indexu.
## Kdyz je kusu moc (sklo z mnoha drobnych dilku), spoji se podle polohy do vetsich celku.
static func _components(arrays: Array, xf: Transform3D) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		idx.resize(verts.size())
		for i in verts.size():
			idx[i] = i
	var n := verts.size()
	var parent := PackedInt32Array()
	parent.resize(n)
	for i in n:
		parent[i] = i
	var seen := {}
	for i in n:
		var k := Vector3i(((xf * verts[i]) / 0.002).round())
		if seen.has(k):
			CarModel._union(parent, i, seen[k])
		else:
			seen[k] = i
	for t in range(0, idx.size() - 2, 3):
		CarModel._union(parent, idx[t], idx[t + 1])
		CarModel._union(parent, idx[t], idx[t + 2])
	var groups := {}
	var centers := {}
	for t in range(0, idx.size() - 2, 3):
		var r := CarModel._root(parent, idx[t])
		if not groups.has(r):
			groups[r] = PackedInt32Array()
			centers[r] = xf * verts[idx[t]]
		var l: PackedInt32Array = groups[r]
		l.append(idx[t])
		l.append(idx[t + 1])
		l.append(idx[t + 2])
		groups[r] = l
	if groups.size() <= 14:
		return groups.values()
	# moc kusu: spojit podle polohy (bunky 0,7 m)
	var merged := {}
	for r in groups:
		var cpos: Vector3 = centers[r]
		var key := Vector3i((cpos / 0.7).floor())
		var l: PackedInt32Array = merged.get(key, PackedInt32Array())
		l.append_array(groups[r])
		merged[key] = l
	return merged.values()


## Podmnozina site jen s pouzitymi vrcholy.
static func _compact(arrays: Array, tri: PackedInt32Array) -> Array:
	var remap := {}
	var order := PackedInt32Array()
	var new_idx := PackedInt32Array()
	new_idx.resize(tri.size())
	for k in tri.size():
		var i := tri[k]
		if not remap.has(i):
			remap[i] = order.size()
			order.append(i)
		new_idx[k] = remap[i]
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for a in Mesh.ARRAY_MAX:
		var src: Variant = arrays[a]
		if src == null or a == Mesh.ARRAY_INDEX:
			continue
		var stride := 4 if a == Mesh.ARRAY_TANGENT else 1
		var dst: Variant
		match typeof(src):
			TYPE_PACKED_VECTOR3_ARRAY:
				var d := PackedVector3Array()
				for i in order:
					d.append((src as PackedVector3Array)[i])
				dst = d
			TYPE_PACKED_VECTOR2_ARRAY:
				var d := PackedVector2Array()
				for i in order:
					d.append((src as PackedVector2Array)[i])
				dst = d
			TYPE_PACKED_COLOR_ARRAY:
				var d := PackedColorArray()
				for i in order:
					d.append((src as PackedColorArray)[i])
				dst = d
			TYPE_PACKED_FLOAT32_ARRAY:
				var d := PackedFloat32Array()
				for i in order:
					for j in stride:
						d.append((src as PackedFloat32Array)[i * stride + j])
				dst = d
			_:
				dst = null
		out[a] = dst
	out[Mesh.ARRAY_INDEX] = new_idx
	return out


func _hit_windows(c: Vector3, strength: float) -> void:
	for w: Dictionary in _windows:
		if w.state >= 2 or not is_instance_valid(w.mi):
			continue
		var box: AABB = w.box
		var d := c.distance_to(c.clamp(box.position, box.end))
		var f := clampf(1.0 - d / (1.0 + strength * 0.05), 0.0, 1.0)
		if f <= 0.0:
			continue
		w.acc = float(w.acc) + strength * f
		var tough: float = w.tough
		if float(w.acc) > 15.0 * tough:
			_shatter(w)
		elif float(w.acc) > 4.0 * tough and int(w.state) == 0:
			_crack(w)


func _crack(w: Dictionary) -> void:
	w.state = 1
	var mi: MeshInstance3D = w.mi
	var m := StandardMaterial3D.new()
	m.albedo_texture = crack_texture()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.06
	m.metallic = 0.25
	m.metallic_specular = 0.9
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * float(w.scale) / 1.1
	m.uv1_offset = Vector3(randf(), randf(), randf())
	mi.material_override = m


func _shatter(w: Dictionary) -> void:
	if int(w.state) >= 2:
		return
	w.state = 2
	var mi: MeshInstance3D = w.mi
	if not is_instance_valid(mi) or not mi.visible:
		return
	mi.visible = false
	var box: AABB = w.box
	var gpos := model.global_transform * box.get_center()
	FX.spawn_glass(car.get_parent(), gpos, model.global_basis * box.size, car.linear_velocity)
	if car.has_signal("glass_broken"):
		car.glass_broken.emit(car, gpos)


func crack_all() -> void:
	for w: Dictionary in _windows:
		if int(w.state) == 0 and is_instance_valid(w.mi):
			_crack(w)


func windows_state() -> Vector3i:
	var r := Vector3i.ZERO
	for w: Dictionary in _windows:
		if int(w.state) <= 2:
			r[int(w.state)] += 1
	return r


## Prasknuti: textura s paprskovitymi prasklinami (opakovatelna, vygeneruje se jednou).
static func crack_texture() -> ImageTexture:
	if _crack_tex:
		return _crack_tex
	var size := 512
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.035, 0.045, 0.055, 0.78))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var crack := Color(0.82, 0.88, 0.94, 1.0)
	for center_i in 4:
		var c := Vector2(rng.randf() * size, rng.randf() * size)
		var rays := rng.randi_range(9, 14)
		var ends: Array[Vector2] = []
		for k in rays:
			var ang := TAU * (k + rng.randf_range(-0.3, 0.3)) / rays
			var p := c
			var length := rng.randf_range(90.0, 250.0)
			var travelled := 0.0
			while travelled < length:
				var step := rng.randf_range(10.0, 26.0)
				ang += rng.randf_range(-0.35, 0.35)
				var q := p + Vector2.from_angle(ang) * step
				_line(img, p, q, crack, 1.0 if travelled > length * 0.5 else 1.6)
				# odbocky
				if rng.randf() < 0.18:
					var b_ang := ang + rng.randf_range(-1.1, 1.1)
					_line(img, q, q + Vector2.from_angle(b_ang) * rng.randf_range(15.0, 45.0), crack, 0.8)
				p = q
				travelled += step
				if ends.size() < rays * 3 and travelled < 70.0:
					ends.append(q)
		# soustredne praskliny kolem stredu
		for ring in 2:
			var rr := rng.randf_range(18.0, 60.0) * (ring + 1)
			var a0 := rng.randf() * TAU
			var steps := 18
			for i in steps:
				if rng.randf() < 0.3:
					continue
				var a1 := a0 + TAU * i / steps
				var a2 := a0 + TAU * (i + 1) / steps
				_line(img, c + Vector2.from_angle(a1) * rr * rng.randf_range(0.9, 1.1), c + Vector2.from_angle(a2) * rr * rng.randf_range(0.9, 1.1), crack, 0.8)
		# rozdrcene misto uprostred
		for i in 60:
			var q := c + Vector2(rng.randf_range(-9, 9), rng.randf_range(-9, 9))
			_line(img, q, q + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6)), crack, 0.7)
	img.generate_mipmaps()
	_crack_tex = ImageTexture.create_from_image(img)
	return _crack_tex


static func _line(img: Image, a: Vector2, b: Vector2, col: Color, width: float) -> void:
	var size := img.get_width()
	var n := int(a.distance_to(b) * 2.0) + 1
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		var x := posmod(int(p.x), size)
		var y := posmod(int(p.y), size)
		img.set_pixel(x, y, col)
		if width > 1.2:
			img.set_pixel(posmod(x + 1, size), y, col)
			img.set_pixel(x, posmod(y + 1, size), col)


# ---------------------------------------------------------------------
#  Dily na pantech
# ---------------------------------------------------------------------

func _node_aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for n in [node] + node.find_children("*", "MeshInstance3D", true, false):
		if n is MeshInstance3D and (n as MeshInstance3D).mesh:
			var a := CarModel.xform_to(n, model) * (n as MeshInstance3D).mesh.get_aabb()
			box = a if first else box.merge(a)
			first = false
	return box if not first else AABB(CarModel.xform_to(node, model).origin, Vector3.ONE * 0.1)


func _setup_parts() -> void:
	for key: String in PART_KEYS:
		var node: Node3D = model.parts.get(key)
		if node == null or not is_instance_valid(node) or not model.is_ancestor_of(node):
			continue
		var box := _node_aabb(node)
		var cx := box.get_center().x
		var hinge: Vector3
		var axis: Vector3
		var sgn := 1.0
		var max_deg := 50.0
		var rest_deg := 10.0
		if key == "kapota":
			hinge = Vector3(cx, box.end.y, box.end.z)
			axis = Vector3.RIGHT
			max_deg = 55.0
		elif key == "kufr":
			hinge = Vector3(cx, box.end.y, box.position.z)
			axis = Vector3.RIGHT
			sgn = -1.0
			max_deg = 60.0
		elif key.begins_with("dvere"):
			var outer_x := box.position.x if cx < 0.0 else box.end.x
			hinge = Vector3(outer_x, box.get_center().y, box.position.z)
			axis = Vector3.UP
			sgn = -1.0 if cx < 0.0 else 1.0
			max_deg = 68.0
			rest_deg = 16.0
		elif key.begins_with("naraznik"):
			var right_end := randf() < 0.5
			hinge = Vector3(box.end.x if right_end else box.position.x, box.get_center().y, box.get_center().z)
			axis = Vector3.BACK
			sgn = 1.0 if right_end else -1.0
			max_deg = 24.0
			rest_deg = 8.0
		else:
			hinge = Vector3(cx, box.end.y, box.get_center().z)
			axis = Vector3.BACK
			sgn = 1.0 if cx > 0.0 else -1.0
			max_deg = 20.0
			rest_deg = 6.0
		var parent_xf := CarModel.xform_to(node.get_parent(), model)
		var inv := parent_xf.affine_inverse()
		_parts.append({"key": key, "node": node, "box": box, "state": 0, "acc": 0.0,
			"pivot": inv * hinge, "axis": (inv.basis * axis).normalized(), "sign": sgn,
			"max": deg_to_rad(max_deg), "rest": deg_to_rad(rest_deg), "angle": 0.0, "vel": 0.0,
			"base": node.transform})


func _hit_parts(c: Vector3, strength: float) -> void:
	for p: Dictionary in _parts:
		if int(p.state) >= 2:
			continue
		var box: AABB = p.box
		var d := c.distance_to(c.clamp(box.position, box.end))
		var f := clampf(1.0 - d / 1.3, 0.0, 1.0)
		if f <= 0.0:
			continue
		p.acc = float(p.acc) + strength * f
		p.vel = float(p.vel) + strength * f * 0.4 * (1.0 if randf() < 0.7 else -1.0)
		if float(p.acc) > 28.0:
			_detach(p, 2.0 + strength * 0.15)
		elif float(p.acc) > 10.0 and int(p.state) == 0:
			p.state = 1


func _detach(p: Dictionary, speed: float) -> void:
	if int(p.state) >= 2:
		return
	p.state = 2
	var node: Node3D = p.node
	if not is_instance_valid(node) or not model.is_ancestor_of(node):
		return
	node.transform = _hinge_xf(p, float(p.angle))
	_finish_dents()
	for rec: Dictionary in _meshes:
		if is_instance_valid(rec.mi) and (node == rec.mi or node.is_ancestor_of(rec.mi)):
			if rec.dirty:
				_rebuild(rec)
			rec.alive = false
	for w: Dictionary in _windows:
		if is_instance_valid(w.mi) and node.is_ancestor_of(w.mi):
			w.state = 3
	car.detach_part(node, speed)
	model.parts.erase(p.key)
	car.part_detached.emit(car, String(p.key))


func _hinge_xf(p: Dictionary, angle: float) -> Transform3D:
	var pivot: Vector3 = p.pivot
	var axis: Vector3 = p.axis
	var rot := Transform3D(Basis(axis, angle * float(p.sign)), Vector3.ZERO)
	return Transform3D(Basis(), pivot) * rot * Transform3D(Basis(), -pivot) * (p.base as Transform3D)


func _physics_process(delta: float) -> void:
	if car == null or not is_instance_valid(model):
		return
	var acc_g := (car.linear_velocity - _prev_vel) / maxf(delta, 0.001)
	_prev_vel = car.linear_velocity
	var acc := model.global_basis.inverse() * acc_g
	var spd := car.linear_velocity.length()
	for p: Dictionary in _parts:
		if int(p.state) != 1:
			continue
		var node: Node3D = p.node
		if not is_instance_valid(node):
			continue
		var key: String = p.key
		# setrvacnost: kapota a kufr podle brzdeni/zrychleni, dvere podle zataceni, narazniky podle hrbolu
		var drive := 0.0
		if key == "kapota":
			drive = acc.z * 0.35
		elif key == "kufr":
			drive = -acc.z * 0.35
		elif key.begins_with("dvere"):
			drive = -acc.x * 0.3 * float(p.sign)
		else:
			drive = absf(acc.y - 9.8 * 0.0) * 0.05
		drive += randf_range(-1.0, 1.0) * spd * 0.35
		var a: float = p.angle
		var v: float = p.vel
		v += (-18.0 * (a - float(p.rest)) - 2.5 * v + drive) * delta
		a += v * delta
		if a < 0.0:
			a = 0.0
			v = absf(v) * 0.35
		elif a > float(p.max):
			a = float(p.max)
			v = -absf(v) * 0.35
		p.angle = a
		p.vel = v
		node.transform = _hinge_xf(p, a)


## Vybuch: vsechna skla se rozbiji, dily odletí, karoserie se promackne na vice mistech.
func explode_all() -> void:
	for w: Dictionary in _windows:
		_shatter(w)
	for p: Dictionary in _parts:
		_detach(p, 7.0)
	var box := model.body_aabb
	for i in 6:
		var c := Vector3(randf_range(box.position.x, box.end.x), randf_range(box.get_center().y, box.end.y), randf_range(box.position.z, box.end.z))
		_dent(c, (box.get_center() - c).normalized(), 0.8, 0.12)


func parts_state() -> Vector3i:
	var r := Vector3i.ZERO
	for p: Dictionary in _parts:
		r[mini(int(p.state), 2)] += 1
	return r
