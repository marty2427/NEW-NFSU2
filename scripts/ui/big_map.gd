class_name BigMap
extends Control
## Velka mapa celeho mesta (klavesa TAB): reka, ulice podle dulezitosti, volne plochy,
## zvyrazneny okruh a poloha auta. Sever je nahore.

const C_BG := Color(0.03, 0.035, 0.06, 0.9)

var car: Node3D
var circuit: Circuit:
	set(value):
		circuit = value
		if _layer:
			_layer.queue_redraw()
var city_map: CityMap
var _layer: Control      # ulice (prekresli se jen pri zmene)
var _marker: Control     # auto (prekresluje se porad)
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = load("res://assets/fonts/Oxanium.ttf")
	_layer = Control.new()
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.draw.connect(_draw_map)
	add_child(_layer)
	_marker = Control.new()
	_marker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_marker)
	add_child(_marker)
	resized.connect(func(): _layer.queue_redraw())
	visible = false


func toggle() -> void:
	visible = not visible
	if visible:
		_layer.queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		_marker.queue_redraw()


var _center := Vector2.ZERO
var _extent := 1.0


## Stred a velikost mapy podle vsech silnic (mesto i kopce).
func _fit() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for pl in city_map.polylines:
		for p in pl:
			lo = lo.min(p)
			hi = hi.max(p)
	_center = (lo + hi) * 0.5
	_extent = maxf(hi.x - lo.x, hi.y - lo.y) * 0.5 * 1.04


func _scale() -> float:
	return minf(size.x, size.y) * 0.47 / _extent


func _to_screen(p: Vector2) -> Vector2:
	return size * 0.5 + (p - _center) * _scale()


func _draw_map() -> void:
	if city_map == null:
		return
	if _extent <= 1.0:
		_fit()
	var r := minf(size.x, size.y) * 0.49
	var panel := Rect2(size * 0.5 - Vector2(r * 1.18, r), Vector2(r * 2.36, r * 2.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_BG
	sb.set_corner_radius_all(18)
	sb.border_color = Color(1, 1, 1, 0.22)
	sb.set_border_width_all(2)
	_layer.draw_style_box(sb, panel)
	var sc := _scale()
	# Volne plochy a voda
	for lot: Dictionary in city_map.lots:
		var poly := PackedVector2Array()
		for item in lot.ulice:
			var pl := city_map.polylines[item[0]].duplicate()
			if not item[1]:
				pl.reverse()
			for i in pl.size() - 1:
				poly.append(_to_screen(pl[i]))
		var col := Color(0.12, 0.32, 0.62) if lot.typ == "reka" else (Color(0.5, 0.45, 0.15, 0.8) if lot.typ == "trenink" else Color(0.25, 0.33, 0.27, 0.8))
		if Geometry2D.triangulate_polygon(poly).size() > 0:
			_layer.draw_colored_polygon(poly, col)
	# Ulice podle dulezitosti
	var styles := {"magistrala": [Color(1.0, 0.35, 0.4), 3.4], "horska": [Color(0.6, 0.95, 0.6), 2.4], "ulicka": [Color(0.6, 0.6, 0.7, 0.55), 1.0], "ulice": [Color(0.66, 0.68, 0.76, 0.6), 1.2], "trida": [Color(0.7, 0.68, 0.64, 0.7), 1.5],
		"obvod": [Color(0.85, 0.86, 0.92), 2.2], "nabrezi": [Color(0.7, 0.82, 1.0), 2.2], "bulvar": [Color(0.96, 0.96, 1.0), 2.6], "dalnice": [Color(1.0, 0.68, 0.25), 3.4]}
	for order in ["ulicka", "ulice", "trida", "obvod", "nabrezi", "horska", "bulvar", "dalnice", "magistrala"]:
		var st: Array = styles[order]
		for e in city_map.polylines.size():
			if city_map.edge_class[e] != order:
				continue
			var pts := PackedVector2Array()
			for p in city_map.polylines[e]:
				pts.append(_to_screen(p))
			_layer.draw_polyline(pts, st[0], maxf(st[1] * sc * 30.0, 1.0), true)
	# Okruh
	if circuit:
		for e: int in circuit.edge_set:
			var pts := PackedVector2Array()
			for p in city_map.polylines[e]:
				pts.append(_to_screen(p))
			_layer.draw_polyline(pts, Color(0.15, 0.85, 1.0), maxf(3.2 * sc * 30.0, 2.5), true)
		var sp := _to_screen(Vector2(circuit.start_xf.origin.x, circuit.start_xf.origin.z))
		_layer.draw_circle(sp, 8.0, Color.WHITE)
		_layer.draw_circle(sp, 5.0, Color(0.05, 0.05, 0.08))
		_layer.draw_string(_font, Vector2(size.x * 0.5 - 300, size.y * 0.5 - r + 44), "OKRUH: %s  ·  %.1f km" % [circuit.title, circuit.length / 1000.0],
			HORIZONTAL_ALIGNMENT_CENTER, 600, 26, Color(0.15, 0.85, 1.0))
	_layer.draw_string(_font, Vector2(size.x * 0.5 - 300, size.y * 0.5 + r - 26), "TAB zavřít  ·  O další okruh  ·  T na start  ·  P tréninková plocha",
		HORIZONTAL_ALIGNMENT_CENTER, 600, 18, Color(0.85, 0.88, 0.95, 0.8))
	_layer.draw_string(_font, Vector2(size.x * 0.5 - 20, size.y * 0.5 - r + 20), "S", HORIZONTAL_ALIGNMENT_CENTER, 40, 18, Color(0.9, 0.3, 0.3))


func _draw_marker() -> void:
	if car == null or not is_instance_valid(car) or city_map == null:
		return
	var p := _to_screen(Vector2(car.global_position.x, car.global_position.z))
	var fwd3: Vector3 = -car.global_basis.z
	var ang := atan2(fwd3.x, -fwd3.z)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 200.0)
	_marker.draw_circle(p, 16.0 + pulse * 6.0, Color(1.0, 0.85, 0.2, 0.25))
	_marker.draw_set_transform(p, ang, Vector2.ONE)
	_marker.draw_colored_polygon(PackedVector2Array([Vector2(0, -14), Vector2(9, 10), Vector2(0, 5), Vector2(-9, 10)]), Color(1.0, 0.85, 0.2))
	_marker.draw_polyline(PackedVector2Array([Vector2(0, -14), Vector2(9, 10), Vector2(0, 5), Vector2(-9, 10), Vector2(0, -14)]), Color(0, 0, 0, 0.8), 1.5, true)
	_marker.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
