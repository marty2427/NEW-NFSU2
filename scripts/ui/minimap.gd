class_name Minimap
extends Control
## Kulata minimapa: ulice v okoli auta (natocena podle smeru jizdy), reka, zvyrazneny okruh,
## dalsi prujezdni bod okruhu a start. Kresli se jen ulice z okoli (mesto je obrovske).

const RADIUS := 104.0
const VIEW_M := 320.0          # kolik metru je videt od auta k okraji mapy
const C_ROAD := Color(0.82, 0.86, 0.95, 0.5)
const C_MAIN := Color(0.95, 0.96, 1.0, 0.8)
const C_HIGHWAY := Color(1.0, 0.7, 0.25, 0.9)
const C_MAGISTRALA := Color(1.0, 0.35, 0.4, 0.9)
const C_RIVER := Color(0.15, 0.4, 0.8, 0.75)
const C_CIRCUIT := Color(0.15, 0.85, 1.0, 0.95)
const C_NEXT := Color(0.35, 1.0, 0.45)

var car: Node3D
var circuit: Circuit
var city_map: CityMap


func _ready() -> void:
	custom_minimum_size = Vector2(RADIUS * 2 + 16, RADIUS * 2 + 16)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


## Usecka orezana kruhem mapy (vraci prazdne pole, kdyz je cela venku).
static func clip(a: Vector2, b: Vector2, r: float) -> PackedVector2Array:
	var d := b - a
	var qa := d.length_squared()
	if qa < 0.0001:
		return PackedVector2Array()
	var qb := 2.0 * a.dot(d)
	var qc := a.length_squared() - r * r
	var disc := qb * qb - 4.0 * qa * qc
	if disc <= 0.0:
		return PackedVector2Array()
	var s := sqrt(disc)
	var t0 := maxf((-qb - s) / (2.0 * qa), 0.0)
	var t1 := minf((-qb + s) / (2.0 * qa), 1.0)
	if t0 >= t1:
		return PackedVector2Array()
	return PackedVector2Array([a + d * t0, a + d * t1])


func _line(pl: PackedVector2Array, origin: Vector2, right: Vector2, fwd: Vector2, scale_px: float, col: Color, width: float) -> void:
	var c := size * 0.5
	var prev := Vector2.ZERO
	for i in pl.size():
		var rel := pl[i] - origin
		var p := Vector2(rel.dot(right), -rel.dot(fwd)) * scale_px
		if i > 0:
			var seg := clip(prev, p, RADIUS)
			if seg.size() == 2:
				draw_line(c + seg[0], c + seg[1], col, width, true)
		prev = p


func _draw() -> void:
	if car == null or not is_instance_valid(car) or city_map == null:
		return
	var c := size * 0.5
	var scale_px := RADIUS / VIEW_M
	var fwd3: Vector3 = -car.global_basis.z
	var fwd := Vector2(fwd3.x, fwd3.z)
	if fwd.length() < 0.01:
		fwd = Vector2(0, -1)
	fwd = fwd.normalized()
	var right := Vector2(-fwd.y, fwd.x)
	var origin := Vector2(car.global_position.x, car.global_position.z)

	draw_circle(c, RADIUS + 5.0, Color(0.025, 0.03, 0.055, 0.66))
	_line(city_map.river, origin, right, fwd, scale_px, C_RIVER, 120.0 * scale_px)
	# Ulice: nejdriv obycejne, pak hlavni tahy, nakonec okruh navrch
	var near := city_map.edges_near(origin, VIEW_M + 40.0)
	for pass_index in 3:
		for e in near:
			var on_circuit: bool = circuit != null and circuit.edge_set.has(e)
			var cls := city_map.edge_class[e]
			var main := cls != "ulice" and cls != "ulicka" and cls != "trida"
			var layer := 2 if on_circuit else (1 if main else 0)
			if layer != pass_index:
				continue
			var col := C_CIRCUIT if on_circuit else (C_HIGHWAY if cls == "dalnice" else (C_MAGISTRALA if cls == "magistrala" else (C_MAIN if main else C_ROAD)))
			var width := 5.0 if on_circuit else (4.5 if main else 3.0)
			_line(city_map.polylines[e], origin, right, fwd, scale_px, col, width)

	if circuit:
		# Start / cil
		var srel := Vector2(circuit.start_xf.origin.x, circuit.start_xf.origin.z) - origin
		var sp := Vector2(srel.dot(right), -srel.dot(fwd)) * scale_px
		if sp.length() < RADIUS - 6.0:
			draw_circle(c + sp, 6.0, Color.WHITE)
			draw_circle(c + sp, 3.5, Color(0.05, 0.05, 0.08))
		# Dalsi prujezdni bod (na okraji mapy, kdyz je daleko)
		var idx := circuit.next_cp if circuit.running else 1
		var cp := circuit.checkpoints[idx % circuit.checkpoints.size()]
		var crel := Vector2(cp.x, cp.z) - origin
		var p2 := Vector2(crel.dot(right), -crel.dot(fwd)) * scale_px
		if p2.length() > RADIUS - 4.0:
			p2 = p2.normalized() * (RADIUS - 4.0)
		draw_circle(c + p2, 8.0, Color(C_NEXT, 0.3))
		draw_circle(c + p2, 5.0, C_NEXT)

	# Okraj, sever a auto uprostred
	draw_arc(c, RADIUS + 5.0, 0.0, TAU, 96, Color(1, 1, 1, 0.22), 2.0, true)
	var north := Vector2(Vector2(0, -1).dot(right), -Vector2(0, -1).dot(fwd)) * (RADIUS - 2.0)
	draw_circle(c + north, 7.0, Color(0.9, 0.2, 0.25))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -11), c + Vector2(7.5, 8), c + Vector2(0, 4), c + Vector2(-7.5, 8)]), Color(1.0, 0.85, 0.2))
	draw_polyline(PackedVector2Array([c + Vector2(0, -11), c + Vector2(7.5, 8), c + Vector2(0, 4), c + Vector2(-7.5, 8), c + Vector2(0, -11)]), Color(0, 0, 0, 0.7), 1.5, true)
