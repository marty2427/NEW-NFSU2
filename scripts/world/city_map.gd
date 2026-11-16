class_name CityMap
extends RefCounted
## Plan mesta: silnicni sit jako graf (krizovatky + ulice), nepravidelne uhly, zatacky.
## Z planu se pocitaji osy ulic, okraje, rohy bloku, okruh i treninkova plocha.
## Souradnice: Vector2(x, z) v metrech; x = vychod, z = jih. Vse je v rovine y = 0.

const SIDEWALK := 4.5
const STREET := 8.0        # polovina sirky bezne ulice
const BOULEVARD := 11.0    # polovina sirky bulvaru (okruzni trida)

## Krizovatky
const NODES := {
	# Okruzni bulvar
	"R0": Vector2(-760, -420), "R1": Vector2(-420, -740), "R2": Vector2(120, -800),
	"R3": Vector2(620, -640), "R4": Vector2(820, -160), "R5": Vector2(740, 420),
	"R6": Vector2(340, 760), "R7": Vector2(-240, 800), "R8": Vector2(-700, 520),
	"R9": Vector2(-840, 40),
	# Vnitrni okruh
	"I0": Vector2(-360, -180), "I1": Vector2(-120, -380), "I2": Vector2(240, -380),
	"I3": Vector2(420, -60), "I4": Vector2(340, 320), "I5": Vector2(-80, 420),
	"I6": Vector2(-380, 180),
	# Centrum
	"D0": Vector2(-140, -100), "D1": Vector2(120, -140), "D2": Vector2(180, 120),
	"D3": Vector2(-80, 160), "C": Vector2(20, 10),
}

## Ulice: [od, do, polovina sirky, prohnuti]. Prohnuti = o kolik metru je stred ulice
## vyboceny (+ = smerem od stredu mesta, - = ke stredu); 0 = rovna ulice.
const EDGES := [
	# Okruzni bulvar (siroky, plynule oblouky)
	["R0", "R1", BOULEVARD, 40.0], ["R1", "R2", BOULEVARD, 35.0], ["R2", "R3", BOULEVARD, 40.0],
	["R3", "R4", BOULEVARD, 45.0], ["R4", "R5", BOULEVARD, 50.0], ["R5", "R6", BOULEVARD, 45.0],
	["R6", "R7", BOULEVARD, 40.0], ["R7", "R8", BOULEVARD, 40.0], ["R8", "R9", BOULEVARD, 40.0],
	["R9", "R0", BOULEVARD, 40.0],
	# Vnitrni okruh
	["I0", "I1", STREET, 20.0], ["I1", "I2", STREET, 0.0], ["I2", "I3", STREET, 30.0],
	["I3", "I4", STREET, 25.0], ["I4", "I5", STREET, -20.0], ["I5", "I6", STREET, 25.0],
	["I6", "I0", STREET, 15.0],
	# Paprsky mezi vnitrnim okruhem a bulvarem
	["I0", "R0", STREET, 0.0], ["I1", "R1", STREET, 0.0], ["I1", "R2", STREET, 25.0],
	["I2", "R3", STREET, 0.0], ["I3", "R4", STREET, -30.0], ["I4", "R5", STREET, 0.0],
	["I4", "R6", STREET, 25.0], ["I5", "R7", STREET, 0.0], ["I6", "R8", STREET, -20.0],
	["I6", "R9", STREET, 0.0],
	# Centrum: nepravidelny ctyruhelnik s uhloprickami
	["D0", "D1", STREET, 0.0], ["D1", "D2", STREET, 0.0], ["D2", "D3", STREET, 0.0], ["D3", "D0", STREET, 0.0],
	["D0", "C", STREET, 0.0], ["C", "D2", STREET, 0.0], ["D1", "C", STREET, 0.0], ["C", "D3", STREET, 0.0],
	# Spojky centra s vnitrnim okruhem
	["D0", "I0", STREET, 0.0], ["D1", "I1", STREET, 0.0], ["D1", "I2", STREET, 0.0],
	["D2", "I3", STREET, 0.0], ["D2", "I4", STREET, 0.0], ["D3", "I5", STREET, 0.0], ["D3", "I6", STREET, 0.0],
]

## Mestsky okruh (poradi krizovatek, uzavrena smycka)
const CIRCUIT := ["R6", "R5", "R4", "I3", "I2", "D1", "C", "D3", "I5", "I4"]
## Blok bez domu: treninkova plocha (parkoviste)
const LOT := ["I0", "I1", "D1", "D0"]

var polylines: Array[PackedVector2Array] = []    # osa kazde ulice (od -> do)
var half_width: PackedFloat32Array = []
var node_edges := {}     # krizovatka -> pole {e, out (Vector2 smer ven), ang, w}, serazene podle uhlu
var trim := {}           # krizovatka -> o kolik se ulice u krizovatky zkrati (plocha krizovatky)
var open_sides := {}     # "index_ulice:strana" -> true (strana bez domu a zdi; strana +1 = vpravo ve smeru od->do)


func _init() -> void:
	for e in EDGES:
		polylines.append(_edge_polyline(NODES[e[0]], NODES[e[1]], e[3]))
		half_width.append(e[2])
	for id in NODES:
		node_edges[id] = []
	for i in EDGES.size():
		var pl := polylines[i]
		_add_node_edge(EDGES[i][0], i, (pl[1] - pl[0]).normalized())
		_add_node_edge(EDGES[i][1], i, (pl[pl.size() - 2] - pl[pl.size() - 1]).normalized())
	for id in NODES:
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
	# Strany ulic kolem treninkove plochy jsou otevrene
	var centroid := Vector2.ZERO
	for id in LOT:
		centroid += NODES[id] / LOT.size()
	for k in LOT.size():
		var a: String = LOT[k]
		var b: String = LOT[(k + 1) % LOT.size()]
		var ei := find_edge(a, b)
		if ei < 0:
			continue
		var pa: Vector2 = NODES[EDGES[ei][0]]
		var pb: Vector2 = NODES[EDGES[ei][1]]
		var side := 1 if right_of(pb - pa).dot(centroid - pa) > 0.0 else -1
		open_sides["%d:%d" % [ei, side]] = true


func _add_node_edge(node: String, e: int, out: Vector2) -> void:
	node_edges[node].append({"e": e, "out": out, "ang": fposmod(atan2(out.y, out.x), TAU), "w": EDGES[e][2]})


## Smer "vpravo" od smeru jizdy d (pri pohledu shora, sever nahore).
static func right_of(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x)


func _edge_polyline(a: Vector2, b: Vector2, bend: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if is_zero_approx(bend):
		out.append(a)
		out.append(b)
		return out
	var mid := (a + b) * 0.5
	var perp := right_of((b - a).normalized())
	if perp.dot(mid) < 0.0:
		perp = -perp                       # + = od stredu mesta
	var ctrl := mid + perp * bend * 2.0
	var n := clampi(int(ceil(a.distance_to(b) / 40.0)), 3, 16)
	for i in n + 1:
		var t := float(i) / n
		out.append(a * (1 - t) * (1 - t) + ctrl * 2 * (1 - t) * t + b * t * t)
	return out


func find_edge(a: String, b: String) -> int:
	for i in EDGES.size():
		if (EDGES[i][0] == a and EDGES[i][1] == b) or (EDGES[i][0] == b and EDGES[i][1] == a):
			return i
	return -1


func is_open(e: int, side: int) -> bool:
	return open_sides.has("%d:%d" % [e, side])


## Index ulice e v serazenem seznamu krizovatky.
func _slot(node: String, e: int) -> int:
	var arr: Array = node_edges[node]
	for k in arr.size():
		if arr[k].e == e:
			return k
	return -1


## Roh bloku u krizovatky: prusecik okraju (ve vzdalenosti extra za vozovkou) dvou sousednich ulic.
## k = index ulice v serazenem seznamu; roh lezi mezi ulici k (jeji prava strana) a k+1 (jeji leva strana).
func corner(node: String, k: int, extra: float) -> Vector2:
	var arr: Array = node_edges[node]
	var n: Vector2 = NODES[node]
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


## Osa ulice zkracena u obou krizovatek (kde zacina a konci vozovka).
func trimmed(e: int) -> PackedVector2Array:
	return cut_polyline(polylines[e], trim[EDGES[e][0]], trim[EDGES[e][1]])


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
		if acc + seg > from and acc < to:
			var t0 := clampf((from - acc) / seg, 0.0, 1.0)
			var t1 := clampf((to - acc) / seg, 0.0, 1.0)
			if out.is_empty():
				out.append(a.lerp(b, t0))
			out.append(a.lerp(b, t1))
		acc += seg
	return out


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
	var a: String = EDGES[e][0]
	var b: String = EDGES[e][1]
	var ka := _slot(a, e)
	var kb := _slot(b, e)
	var pl := polylines[e]
	var off := offset_polyline(pl, side * (half_width[e] + extra))
	var out := PackedVector2Array()
	# U krizovatky "od": prava strana = roh (k, k+1), leva = roh (k-1, k)
	out.append(corner(a, ka if side > 0 else ka - 1, extra))
	for i in range(1, pl.size() - 1):
		out.append(off[i])
	# U krizovatky "do" miri ulice ven opacne, takze strany jsou prohozene
	out.append(corner(b, kb - 1 if side > 0 else kb, extra))
	return out


## Osa okruhu jako jedna uzavrena lomena cara (bez opakovani prvniho bodu).
func circuit_polyline() -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in CIRCUIT.size():
		var a: String = CIRCUIT[k]
		var b: String = CIRCUIT[(k + 1) % CIRCUIT.size()]
		var e := find_edge(a, b)
		var pl := polylines[e].duplicate()
		if EDGES[e][0] != a:
			pl.reverse()
		for i in pl.size() - 1:
			out.append(pl[i])
	return out


func lot_polygon(extra: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in LOT.size():
		var a: String = LOT[k]
		var b: String = LOT[(k + 1) % LOT.size()]
		var e := find_edge(a, b)
		var pa: Vector2 = NODES[EDGES[e][0]]
		var side := 1 if is_open(e, 1) else -1
		var line := block_line(e, side, extra)
		if EDGES[e][0] != a:
			line.reverse()
		for i in line.size() - 1:
			out.append(line[i])
	return out


static func to3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)
