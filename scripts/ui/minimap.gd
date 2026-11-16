class_name Minimap
extends Control
## Kulata minimapa: ulice v okoli auta (natocena podle smeru jizdy), zvyrazneny okruh,
## dalsi prujezdni bod okruhu a start.

const RADIUS := 104.0
const VIEW_M := 300.0          # kolik metru je videt od auta k okraji mapy
const C_ROAD := Color(0.82, 0.86, 0.95, 0.55)
const C_CIRCUIT := Color(0.15, 0.85, 1.0, 0.95)
const C_NEXT := Color(0.35, 1.0, 0.45)

var car: Node3D
var circuit: Circuit
var city_map: CityMap:
	set(value):
		city_map = value
		_prepare()

var _circuit_edges := {}
var _font: Font


func _ready() -> void:
	custom_minimum_size = Vector2(RADIUS * 2 + 16, RADIUS * 2 + 16)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = load("res://assets/fonts/Oxanium.ttf")


func _prepare() -> void:
	_circuit_edges.clear()
	if city_map == null:
		return
	var n := CityMap.CIRCUIT.size()
	for k in n:
		_circuit_edges[city_map.find_edge(CityMap.CIRCUIT[k], CityMap.CIRCUIT[(k + 1) % n])] = true


func _process(_delta: float) -> void:
	queue_redraw()


## Usecka orezana kruhem mapy (vraci prazdne pole, kdyz je cela venku).
func _clip(a: Vector2, b: Vector2, r: float) -> PackedVector2Array:
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

	draw_circle(c, RADIUS + 5.0, Color(0.025, 0.03, 0.055, 0.62))
	# Ulice: nejdriv obycejne, pak okruh navrch
	for pass_index in 2:
		for e in city_map.polylines.size():
			var on_circuit: bool = _circuit_edges.has(e)
			if on_circuit != (pass_index == 1):
				continue
			var pl := city_map.polylines[e]
			var width := (5.0 if city_map.half_width[e] > 9.0 else 3.5) if not on_circuit else 5.0
			var col := C_CIRCUIT if on_circuit else C_ROAD
			var prev := Vector2.ZERO
			for i in pl.size():
				var rel := pl[i] - origin
				var p := Vector2(rel.dot(right), -rel.dot(fwd)) * scale_px
				if i > 0:
					var seg := _clip(prev, p, RADIUS)
					if seg.size() == 2:
						draw_line(c + seg[0], c + seg[1], col, width, true)
				prev = p

	if circuit:
		# Start / cil
		var srel := Vector2(circuit.start_xf.origin.x, circuit.start_xf.origin.z) - origin
		var sp := Vector2(srel.dot(right), -srel.dot(fwd)) * scale_px
		if sp.length() < RADIUS - 6.0:
			draw_circle(c + sp, 6.0, Color.WHITE)
			draw_circle(c + sp, 3.5, Color(0.05, 0.05, 0.08))
		# Dalsi prujezdni bod (na okraji mapy, kdyz je daleko)
		var idx := circuit.next_cp if circuit.running else 1
		var cp := circuit.checkpoints[idx]
		var crel := Vector2(cp.x, cp.z) - origin
		var p2 := Vector2(crel.dot(right), -crel.dot(fwd)) * scale_px
		if p2.length() > RADIUS - 4.0:
			p2 = p2.normalized() * (RADIUS - 4.0)
		draw_circle(c + p2, 8.0, Color(C_NEXT, 0.3))
		draw_circle(c + p2, 5.0, C_NEXT)

	# Okraj a auto uprostred
	draw_arc(c, RADIUS + 5.0, 0.0, TAU, 96, Color(1, 1, 1, 0.22), 2.0, true)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -11), c + Vector2(7.5, 8), c + Vector2(0, 4), c + Vector2(-7.5, 8)]), Color(1.0, 0.85, 0.2))
	draw_polyline(PackedVector2Array([c + Vector2(0, -11), c + Vector2(7.5, 8), c + Vector2(0, 4), c + Vector2(-7.5, 8), c + Vector2(0, -11)]), Color(0, 0, 0, 0.7), 1.5, true)
