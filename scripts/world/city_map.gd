class_name CityMap
extends RefCounted
## Plan mesta: krizovatky (uzly) a ulice (zatocene lomene cary) nactene z data/mesto.json.
## Plan generuje skript tools/generuj_mesto.py (reka, dalnice, bulvary, stare mesto, mrizka...).
## Souradnice jsou v metrech v rovine (x, z); zem je rovna (y = 0).

const SIDEWALK := 4.5
const PATH := "res://data/mesto.json"
const CELL := 200.0          # mrizka pro rychle hledani ulic v okoli

var radius := 2750.0
var nodes := PackedVector2Array()                 # krizovatky
var edge_a := PackedInt32Array()                  # ulice: krizovatka "od"
var edge_b := PackedInt32Array()                  # ulice: krizovatka "do"
var edge_class := PackedStringArray()             # dalnice, bulvar, obvod, nabrezi, trida, ulice, ulicka
var edge_district := PackedStringArray()          # stare, mesto, jih, mrizka, predmesti, prumysl
var polylines: Array[PackedVector2Array] = []     # osa kazde ulice (od -> do)
var half_width := PackedFloat32Array()
var node_edges: Array = []     # pro kazdou krizovatku pole {e, out (Vector2 smer ven), ang, w, start}, serazene podle uhlu
var trim := PackedFloat32Array()   # o kolik se ulice u krizovatky zkrati (plocha krizovatky)
var side_types := {}           # "ulice:strana" -> typ plochy (strana +1 = vpravo ve smeru od->do)
var lots: Array = []           # {typ, ulice: [[e, vpred, strana]], stred: Vector2, plocha}
var circuits: Array = []       # {nazev, ulice: [[e, vpred]], delka}
var river := PackedVector2Array()
var _cells := {}               # Vector2i -> PackedInt32Array indexu ulic


func _init() -> void:
	var text := FileAccess.get_file_as_string(PATH)
	var data: Dictionary = JSON.parse_string(text)
	radius = data.polomer
	for p in data.uzly:
		nodes.append(Vector2(p[0], p[1]))
	for s in data.ulice:
		edge_a.append(int(s.a))
		edge_b.append(int(s.b))
		edge_class.append(s.trida)
		edge_district.append(s.ctvrt)
		half_width.append(float(s.w))
		var pl := PackedVector2Array()
		for p in s.body:
			pl.append(Vector2(p[0], p[1]))
		polylines.append(pl)
	for p in data.reka:
		river.append(Vector2(p[0], p[1]))
	for lot in data.plochy:
		var entry := {"typ": lot.typ, "ulice": [], "stred": Vector2(lot.stred[0], lot.stred[1]), "plocha": float(lot.plocha)}
		for item in lot.ulice:
			entry.ulice.append([int(item[0]), bool(item[1]), int(item[2])])
			side_types["%d:%d" % [int(item[0]), int(item[2])]] = lot.typ
		lots.append(entry)
	for c in data.okruhy:
		var entry := {"nazev": c.nazev, "ulice": [], "delka": float(c.delka)}
		for item in c.ulice:
			entry.ulice.append([int(item[0]), bool(item[1])])
		circuits.append(entry)

	node_edges.resize(nodes.size())
	for i in nodes.size():
		node_edges[i] = []
	for e in polylines.size():
		var pl := polylines[e]
		_add_node_edge(edge_a[e], e, (pl[1] - pl[0]).normalized(), true)
		_add_node_edge(edge_b[e], e, (pl[pl.size() - 2] - pl[pl.size() - 1]).normalized(), false)
		# prostorova mrizka
		var seen := {}
		for p in pl:
			var cell := Vector2i(int(floor(p.x / CELL)), int(floor(p.y / CELL)))
			if not seen.has(cell):
				seen[cell] = true
				if not _cells.has(cell):
					_cells[cell] = PackedInt32Array()
				_cells[cell].append(e)
	trim.resize(nodes.size())
	for id in nodes.size():
		var arr: Array = node_edges[id]
		arr.sort_custom(func(a, b): return a.ang < b.ang)
		# Zkraceni ulic u krizovatky, aby se vozovky neprekryvaly
		var d := 3.0
		for k in arr.size():
			var a: Dictionary = arr[k]
			var b: Dictionary = arr[(k + 1) % arr.size()]
			var theta := fposmod(b.ang - a.ang, TAU)
			if arr.size() == 1:
				continue
			if theta < PI * 0.95:
				d = maxf(d, maxf(a.w, b.w) / tan(theta * 0.5) + 1.0)
		trim[id] = minf(d, 34.0)


func _add_node_edge(node: int, e: int, out: Vector2, start: bool) -> void:
	node_edges[node].append({"e": e, "out": out, "ang": fposmod(atan2(out.y, out.x), TAU), "w": half_width[e], "start": start})


## Smer "vpravo" od smeru jizdy d (pri pohledu shora, sever nahore).
static func right_of(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x)


## Typ plochy na dane strane ulice: "" = bezny blok s domy, "trenink" / "plocha" / "namesti" = volna
## plocha bez zdi, "reka" = voda (zed zustava).
func side_type(e: int, side: int) -> String:
	return side_types.get("%d:%d" % [e, side], "")


## Volna plocha, na kterou se da z ulice vjet (bez domu, bez zdi, bez obrubniku).
func is_open(e: int, side: int) -> bool:
	var t := side_type(e, side)
	return t != "" and t != "reka"


## Ulice v okoli bodu (indexy), pro minimapu apod.
func edges_near(p: Vector2, dist: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var seen := {}
	for gx in range(int(floor((p.x - dist) / CELL)), int(floor((p.x + dist) / CELL)) + 1):
		for gz in range(int(floor((p.y - dist) / CELL)), int(floor((p.y + dist) / CELL)) + 1):
			var list: PackedInt32Array = _cells.get(Vector2i(gx, gz), PackedInt32Array())
			for e in list:
				if not seen.has(e):
					seen[e] = true
					out.append(e)
	return out


## Nejblizsi ulice k bodu: {e, dist, point, dir}.
func nearest_edge(p: Vector2, search := 400.0) -> Dictionary:
	var best := {"e": -1, "dist": 1e9, "point": p, "dir": Vector2.RIGHT}
	for e in edges_near(p, search):
		var pl := polylines[e]
		for i in pl.size() - 1:
			var q := Geometry2D.get_closest_point_to_segment(p, pl[i], pl[i + 1])
			var d := p.distance_to(q)
			if d < best.dist:
				best = {"e": e, "dist": d, "point": q, "dir": (pl[i + 1] - pl[i]).normalized()}
	return best


## Index ulice e v serazenem seznamu krizovatky.
func _slot(node: int, e: int) -> int:
	var arr: Array = node_edges[node]
	for k in arr.size():
		if arr[k].e == e:
			return k
	return -1


## Roh bloku u krizovatky: prusecik okraju (ve vzdalenosti extra za vozovkou) dvou sousednich ulic.
## k = index ulice v serazenem seznamu; roh lezi mezi ulici k (jeji prava strana) a k+1 (jeji leva strana).
func corner(node: int, k: int, extra: float) -> Vector2:
	var arr: Array = node_edges[node]
	var n := nodes[node]
	var a: Dictionary = arr[posmod(k, arr.size())]
	var b: Dictionary = arr[posmod(k + 1, arr.size())]
	var pa: Vector2 = n + right_of(a.out) * (a.w + extra)
	var pb: Vector2 = n - right_of(b.out) * (b.w + extra)
	var cross: float = a.out.cross(b.out)
	if absf(cross) < 0.08 or arr.size() == 1:
		return (pa + pb) * 0.5
	# pa + a.out * s = pb + b.out * t
	var s: float = (pb - pa).cross(b.out) / cross
	return pa + a.out * s


## Uhel (0..TAU), ktery sviraji ulice k a k+1 u krizovatky (mereno po smeru razeni).
func corner_angle(node: int, k: int) -> float:
	var arr: Array = node_edges[node]
	if arr.size() < 2:
		return TAU
	var a: Dictionary = arr[posmod(k, arr.size())]
	var b: Dictionary = arr[posmod(k + 1, arr.size())]
	var theta := fposmod(b.ang - a.ang, TAU)
	return theta if theta > 0.0001 else TAU


## Osa ulice zkracena u obou krizovatek (kde zacina a konci vozovka).
func trimmed(e: int) -> PackedVector2Array:
	return cut_polyline(polylines[e], trim[edge_a[e]], trim[edge_b[e]])


static func polyline_length(pl: PackedVector2Array) -> float:
	var total := 0.0
	for i in pl.size() - 1:
		total += pl[i].distance_to(pl[i + 1])
	return total


static func cut_polyline(pl: PackedVector2Array, start: float, end: float) -> PackedVector2Array:
	var total := polyline_length(pl)
	var from := start
	var to := total - end
	var out := PackedVector2Array()
	var acc := 0.0
	for i in pl.size() - 1:
		var a := pl[i]
		var b := pl[i + 1]
		var seg := a.distance_to(b)
		if acc + seg > from and acc < to and seg > 0.0001:
			var t0 := clampf((from - acc) / seg, 0.0, 1.0)
			var t1 := clampf((to - acc) / seg, 0.0, 1.0)
			if out.is_empty():
				out.append(a.lerp(b, t0))
			if t1 - t0 > 0.0005:
				out.append(a.lerp(b, t1))
		acc += seg
	return out


## Bod a smer ve vzdalenosti dist od zacatku lomene cary.
static func point_at(pl: PackedVector2Array, dist: float) -> Array:
	var acc := 0.0
	for i in pl.size() - 1:
		var seg := pl[i].distance_to(pl[i + 1])
		if acc + seg >= dist or i == pl.size() - 2:
			var dir := (pl[i + 1] - pl[i]) / maxf(seg, 0.0001)
			return [pl[i] + dir * clampf(dist - acc, 0.0, seg), dir]
		acc += seg
	return [pl[0], Vector2.RIGHT]


## Cara rovnobezna s osou ve vzdalenosti dist (+ = vpravo), s ostrymi spoji v lomech.
static func offset_polyline(pl: PackedVector2Array, dist: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pl.size()
	for i in n:
		var d_prev := (pl[i] - pl[i - 1]).normalized() if i > 0 else (pl[1] - pl[0]).normalized()
		var d_next := (pl[i + 1] - pl[i]).normalized() if i < n - 1 else d_prev
		var miter := (right_of(d_prev) + right_of(d_next)).normalized()
		var scale := 1.0 / maxf(miter.dot(right_of(d_prev)), 0.5)
		out.append(pl[i] + miter * dist * scale)
	return out


## Okraj bloku podel ulice (cara domu): od rohu u prvni krizovatky po roh u druhe.
## side: +1 = vpravo ve smeru od->do, -1 = vlevo. extra = vzdalenost za okrajem vozovky.
func block_line(e: int, side: int, extra: float) -> PackedVector2Array:
	var a := edge_a[e]
	var b := edge_b[e]
	var ka := _slot(a, e)
	var kb := _slot(b, e)
	var pl := polylines[e]
	var off := offset_polyline(pl, side * (half_width[e] + extra))
	var out := PackedVector2Array()
	# U krizovatky "od": prava strana = roh (k, k+1), leva = roh (k-1, k)
	var first := corner(a, ka if side > 0 else ka - 1, extra)
	var last := corner(b, kb - 1 if side > 0 else kb, extra)
	out.append(first)
	# Body podel ulice; ty, ktere by lezely "pred" rohem (uvnitr krizovatky), se vynechaji
	var dir_a := (pl[1] - pl[0]).normalized()
	var dir_b := (pl[pl.size() - 1] - pl[pl.size() - 2]).normalized()
	var from := (first - pl[0]).dot(dir_a)
	var to := (last - pl[pl.size() - 1]).dot(dir_b)
	var total := polyline_length(pl)
	var acc := 0.0
	for i in range(1, pl.size() - 1):
		acc += pl[i].distance_to(pl[i - 1])
		if acc > from + 2.0 and acc < total + to - 2.0:
			out.append(off[i])
	out.append(last)
	return out


## Osa okruhu jako jedna uzavrena lomena cara (bez opakovani prvniho bodu).
func circuit_polyline(index: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for item in circuits[index].ulice:
		var pl := polylines[item[0]].duplicate()
		if not item[1]:
			pl.reverse()
		for i in pl.size() - 1:
			out.append(pl[i])
	return out


## Obrys volne plochy (extra = o kolik za okrajem vozovky; zaporne = presah do vozovky).
func lot_polygon(lot: Dictionary, extra: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for item in lot.ulice:
		var line := block_line(item[0], item[2], extra)
		if not item[1]:
			line.reverse()
		for i in line.size() - 1:
			if out.is_empty() or out[out.size() - 1].distance_to(line[i]) > 0.05:
				out.append(line[i])
	if out.size() > 2 and out[0].distance_to(out[out.size() - 1]) < 0.05:
		out.remove_at(out.size() - 1)
	return out


static func to3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)
