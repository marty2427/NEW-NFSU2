class_name Tachometer
extends Control
## Kulaty otackomer s tachometrem, rychlostnim stupnem a nitrem (kresleny v kodu).

const START_ANGLE := deg_to_rad(135.0)   # vlevo dole
const SWEEP := deg_to_rad(270.0)         # po smeru hodinovych rucicek
const C_CYAN := Color(0.15, 0.9, 1.0)
const C_PINK := Color(1.0, 0.2, 0.75)
const C_RED := Color(1.0, 0.15, 0.15)
const C_WHITE := Color(1, 1, 1)

var car: Car
var font: Font
var _rpm_shown := 0.0
var _speed_shown := 0.0
var _gear_flash := 0.0
var _last_gear := 1


func _ready() -> void:
	custom_minimum_size = Vector2(380, 430)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "DejaVu Sans", "Sans-Serif"])
	sf.font_weight = 700
	font = sf


func _process(delta: float) -> void:
	if car and is_instance_valid(car) and car.t:
		_rpm_shown = lerpf(_rpm_shown, car.rpm, 1.0 - exp(-18.0 * delta))
		_speed_shown = lerpf(_speed_shown, car.speed_kmh, 1.0 - exp(-12.0 * delta))
		if car.gear != _last_gear:
			_last_gear = car.gear
			_gear_flash = 1.0
	_gear_flash = maxf(0.0, _gear_flash - delta * 3.0)
	queue_redraw()


func _angle(frac: float) -> float:
	return START_ANGLE + SWEEP * clampf(frac, 0.0, 1.0)


func _draw() -> void:
	if car == null or not is_instance_valid(car) or car.t == null:
		return
	var c := Vector2(size.x * 0.5, size.x * 0.5)
	var r := size.x * 0.5 - 26.0
	var redline := car.t.max_otacky
	var max_rpm := ceilf(redline / 1000.0 + 0.5) * 1000.0
	var frac := _rpm_shown / max_rpm
	var red_frac := redline / max_rpm

	# Pozadi
	draw_circle(c, r + 10.0, Color(0.02, 0.02, 0.05, 0.62))
	draw_arc(c, r + 10.0, 0.0, TAU, 96, Color(0.3, 0.35, 0.5, 0.5), 2.0, true)
	draw_arc(c, r * 0.62, 0.0, TAU, 64, Color(1, 1, 1, 0.06), 1.5, true)

	# Cervene pole
	draw_arc(c, r - 6.0, _angle(red_frac), _angle(1.0), 32, Color(C_RED, 0.55), 10.0, true)

	# Ryski a cisla
	var steps := int(max_rpm / 1000.0)
	for i in steps * 2 + 1:
		var f := float(i) / float(steps * 2)
		var a := _angle(f)
		var dir := Vector2(cos(a), sin(a))
		var major := i % 2 == 0
		var col := C_RED if f >= red_frac - 0.001 else Color(0.85, 0.9, 1.0, 0.9)
		draw_line(c + dir * (r - (18.0 if major else 11.0)), c + dir * (r - 2.0), col, 3.0 if major else 1.5, true)
		if major:
			var txt := str(i / 2)
			var tp := c + dir * (r - 36.0)
			draw_string(font, tp + Vector2(-8, 8), txt, HORIZONTAL_ALIGNMENT_CENTER, 16, 20, col)
	draw_string(font, c + Vector2(-60, -18), "x1000 rpm", HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color(0.7, 0.75, 0.9, 0.7))

	# Svitici oblouk otacek
	var fill_col := C_CYAN.lerp(C_PINK, smoothstep(0.55, 0.85, frac / red_frac))
	if frac >= red_frac * 0.97:
		fill_col = C_RED if fmod(Time.get_ticks_msec() / 80.0, 2.0) < 1.0 else C_WHITE
	if frac > 0.001:
		draw_arc(c, r + 4.0, _angle(0.0), _angle(frac), 64, Color(fill_col, 0.25), 14.0, true)
		draw_arc(c, r + 4.0, _angle(0.0), _angle(frac), 64, fill_col, 4.0, true)

	# Rucicka
	var na := _angle(frac)
	var nd := Vector2(cos(na), sin(na))
	draw_line(c - nd * 16.0, c + nd * (r - 8.0), Color(1.0, 0.3, 0.3, 0.35), 9.0, true)
	draw_line(c - nd * 16.0, c + nd * (r - 8.0), Color(1.0, 0.35, 0.3), 3.0, true)
	draw_circle(c, 9.0, Color(0.1, 0.1, 0.14))
	draw_arc(c, 9.0, 0.0, TAU, 24, Color(1.0, 0.35, 0.3), 2.0, true)

	# Rychlost
	var speed_txt := "%d" % int(round(_speed_shown))
	draw_string(font, c + Vector2(-110, 58), speed_txt, HORIZONTAL_ALIGNMENT_CENTER, 220, 64, C_WHITE)
	draw_string(font, c + Vector2(-60, 84), "km/h", HORIZONTAL_ALIGNMENT_CENTER, 120, 18, Color(C_CYAN, 0.9))

	# Rychlostni stupen
	var gear_box := Rect2(c + Vector2(-24, -86), Vector2(48, 52))
	var gcol := C_WHITE.lerp(C_PINK, _gear_flash)
	draw_rect(gear_box, Color(0.0, 0.0, 0.0, 0.5))
	draw_rect(gear_box, Color(gcol, 0.8), false, 2.0)
	draw_string(font, gear_box.position + Vector2(0, 42), car.gear_label(), HORIZONTAL_ALIGNMENT_CENTER, 48, 40, gcol)

	# Nitro: segmentovany oblouk dole uprostred
	var segs := 12
	var n_start := deg_to_rad(60.0)
	var n_end := deg_to_rad(120.0)
	var gap := deg_to_rad(1.2)
	for i in segs:
		var a0 := lerpf(n_end, n_start, float(i) / segs) - gap
		var a1 := lerpf(n_end, n_start, float(i + 1) / segs) + gap
		var filled := (float(i) + 0.5) / segs <= car.nitro
		var col := Color(0.2, 0.25, 0.35, 0.6)
		if filled:
			col = C_WHITE if car.nitro_active else C_CYAN
		draw_arc(c, r + 22.0, a0, a1, 6, col, 9.0, true)
	draw_string(font, c + Vector2(-50, r + 50.0), "NITRO", HORIZONTAL_ALIGNMENT_CENTER, 100, 15, Color(C_CYAN, 0.9))
