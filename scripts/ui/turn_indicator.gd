class_name TurnIndicator
extends Control
## Ukazatel pristi zatacky na okruhu (nahore uprostred): velka zahnuta sipka a vzdalenost.
## Cim bliz, tim vetsi a jasnejsi; tesne pred krizovatkou blika.

var circuit: Circuit
var font: Font
var _shown := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = load("res://assets/fonts/Oxanium.ttf")
	custom_minimum_size = Vector2(260, 190)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if circuit == null or not is_instance_valid(circuit):
		return
	var info := circuit.next_turn()
	if info.is_empty() or info.dist > 600.0:
		return
	var d: float = info.dist
	var turn: float = info.turn
	var near := clampf(1.0 - d / 600.0, 0.0, 1.0)
	var blink := d < 70.0 and fmod(Time.get_ticks_msec() / 160.0, 2.0) < 1.0
	var col := Color(1.0, 0.78, 0.15).lerp(Color(1.0, 0.3, 0.2), smoothstep(0.6, 1.0, near))
	if blink:
		col = Color.WHITE
	var c := Vector2(size.x * 0.5, 80.0)
	var sc := 0.8 + 0.35 * near
	var side := 1.0 if turn > 0.0 else -1.0
	var sharp := clampf(absf(turn) / 120.0, 0.35, 1.0)
	# podklad
	draw_circle(c, 70.0 * sc, Color(0.0, 0.02, 0.06, 0.55))
	draw_arc(c, 70.0 * sc, 0.0, TAU, 48, Color(col, 0.8), 3.0, true)
	# zahnuta sipka: kmen nahoru, pak oblouk do strany
	var pts := PackedVector2Array()
	var base := c + Vector2(-side * 18.0, 42.0) * sc
	pts.append(base)
	var bend := base + Vector2(0, -38.0) * sc
	pts.append(bend)
	var steps := 10
	var r := 26.0 * sc
	var center := bend + Vector2(side * r, 0)
	var a_end := PI * 0.5 * (0.6 + 0.9 * sharp)
	for i in range(1, steps + 1):
		var a := a_end * float(i) / steps
		pts.append(center + Vector2(-side * cos(a), -sin(a)) * r)
	draw_polyline(pts, Color(0, 0, 0, 0.6), 17.0 * sc, true)
	draw_polyline(pts, col, 12.0 * sc, true)
	var tip := pts[pts.size() - 1]
	var dirv := (tip - pts[pts.size() - 2]).normalized()
	var perp := Vector2(-dirv.y, dirv.x)
	var head := PackedVector2Array([tip + dirv * 20.0 * sc, tip + perp * 15.0 * sc, tip - perp * 15.0 * sc])
	draw_colored_polygon(head, col)
	head.append(head[0])
	draw_polyline(head, col, 1.5, true)
	# vzdalenost
	var txt := "%d m" % int(round(d / 10.0) * 10.0) if d >= 20.0 else "TEĎ"
	var fs := 30
	var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(c.x - w * 0.5 + 2, c.y + 70.0 * sc + 44 + 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6))
	draw_string(font, Vector2(c.x - w * 0.5, c.y + 70.0 * sc + 44), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
