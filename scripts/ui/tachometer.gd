class_name Tachometer
extends Control
## Otackomer inspirovany NFSU2, v modernim provedeni (kresleny v kodu):
## kourove pruhledny cifernik, sikme cislice, svitici oblouk otacek s rucickou,
## vpravo rychlostni stupen se sipkou pro preraeni a velka rychlost,
## nahore vpravo modry oblouk N2O, vlevo dole maly budik turba.

const START_DEG := 100.0       # 0 ot./min dole
const SWEEP_DEG := 245.0       # po smeru hodinovych rucicek az nahoru vpravo
const C_TICK := Color(0.92, 0.95, 1.0)
const C_CYAN := Color(0.2, 0.85, 1.0)
const C_PINK := Color(1.0, 0.25, 0.7)
const C_RED := Color(1.0, 0.15, 0.12)
const C_ORANGE := Color(1.0, 0.55, 0.15)
const C_GREEN := Color(0.3, 1.0, 0.35)
const C_N2O := Color(0.25, 0.6, 1.0)

var car: Node  # Car nebo GevpCar
var font: Font
var font_italic: FontVariation
var _rpm := 0.0
var _speed := 0.0
var _boost := 0.0
var _gear_flash := 0.0
var _last_gear := 1
var _n2o_glow := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(480, 440)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	font = load("res://assets/fonts/RussoOne-Regular.ttf")
	font_italic = FontVariation.new()
	font_italic.base_font = font
	font_italic.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.22, 1), Vector2.ZERO)


func _process(delta: float) -> void:
	if car and is_instance_valid(car) and car.get("t"):
		var rpm_now: float = car.rpm
		var spd: float = car.speed_kmh
		var thr: float = car.in_throttle
		var redline: float = car.t.max_otacky
		_rpm = lerpf(_rpm, rpm_now, 1.0 - exp(-18.0 * delta))
		_speed = lerpf(_speed, spd, 1.0 - exp(-12.0 * delta))
		var target_boost := thr * clampf((rpm_now / redline - 0.3) / 0.5, 0.0, 1.0) * 26.0 - (1.0 - thr) * 18.0
		_boost = lerpf(_boost, target_boost, 1.0 - exp(-5.0 * delta))
		var g: int = car.gear
		if g != _last_gear:
			_last_gear = g
			_gear_flash = 1.0
		var on: bool = car.nitro_active
		_n2o_glow = lerpf(_n2o_glow, 1.0 if on else 0.0, 1.0 - exp(-10.0 * delta))
	_gear_flash = maxf(0.0, _gear_flash - delta * 2.5)
	queue_redraw()


func _ang(frac: float) -> float:
	return deg_to_rad(START_DEG + SWEEP_DEG * clampf(frac, 0.0, 1.0))


func _dir(a: float) -> Vector2:
	return Vector2(cos(a), sin(a))


func _text(pos: Vector2, txt: String, fsize: int, col: Color, f: Font = null, align := HORIZONTAL_ALIGNMENT_CENTER, width := 200.0) -> void:
	var fnt := f if f else font
	var off := -width * 0.5 if align == HORIZONTAL_ALIGNMENT_CENTER else (-width if align == HORIZONTAL_ALIGNMENT_RIGHT else 0.0)
	# Stin pro citelnost i na svetlem pozadi (den)
	draw_string(fnt, pos + Vector2(off + 2, 2), txt, align, width, fsize, Color(0, 0, 0, 0.55 * col.a))
	draw_string(fnt, pos + Vector2(off, 0), txt, align, width, fsize, col)


func _draw() -> void:
	if car == null or not is_instance_valid(car) or car.get("t") == null:
		return
	var redline: float = car.t.max_otacky
	var max_rpm := ceilf(redline / 1000.0 + 0.4) * 1000.0
	var frac := _rpm / max_rpm
	var red_frac := redline / max_rpm
	var nitro: float = car.nitro
	var nitro_on: bool = car.nitro_active
	var gear_text: String = car.gear_label()
	var gear_max: int = car.t.pocet_rychlosti
	var cur_gear: int = car.gear

	var c := Vector2(size.x - 205.0, size.y - 200.0)
	var r := 168.0

	# --- Cifernik: kourove sklo s jemnym prechodem ---
	for i in 6:
		var k := float(i) / 5.0
		draw_circle(c, r + 8.0 - k * 22.0, Color(0.02, 0.03, 0.07, 0.16 + k * 0.08))
	draw_arc(c, r + 8.0, 0.0, TAU, 128, Color(0.55, 0.7, 1.0, 0.45), 2.5, true)
	draw_arc(c, r + 12.0, 0.0, TAU, 128, Color(0.55, 0.7, 1.0, 0.12), 6.0, true)
	draw_circle(c, r * 0.36, Color(0.0, 0.0, 0.0, 0.22))
	draw_arc(c, r * 0.36, 0.0, TAU, 64, Color(1, 1, 1, 0.08), 2.0, true)

	# --- Cervene pole ---
	draw_arc(c, r - 4.0, _ang(red_frac), _ang(1.0), 32, Color(C_RED, 0.85), 9.0, true)

	# --- Svitici oblouk otacek ---
	if frac > 0.002:
		var col := C_CYAN.lerp(C_PINK, smoothstep(0.55, 0.9, frac / red_frac))
		if frac >= red_frac * 0.98:
			col = C_RED if fmod(Time.get_ticks_msec() / 70.0, 2.0) < 1.0 else Color.WHITE
		var steps := 24
		for i in steps:
			var a0 := lerpf(_ang(0.0), _ang(frac), float(i) / steps)
			var a1 := lerpf(_ang(0.0), _ang(frac), float(i + 1) / steps)
			var fade := 0.25 + 0.75 * float(i) / steps
			draw_arc(c, r - 18.0, a0, a1 + 0.01, 4, Color(col, 0.18 * fade), 16.0, true)
			draw_arc(c, r - 18.0, a0, a1 + 0.01, 4, Color(col, 0.9 * fade), 4.0, true)

	# --- Ryski a sikme cislice ---
	var n := int(max_rpm / 1000.0)
	for i in n * 2 + 1:
		var f := float(i) / float(n * 2)
		var a := _ang(f)
		var d := _dir(a)
		var major := i % 2 == 0
		var col := C_RED if f > red_frac + 0.001 else C_TICK
		draw_line(c + d * (r - (24.0 if major else 13.0)), c + d * (r - 3.0), col, 4.0 if major else 2.0, true)
		if major:
			_text(c + d * (r - 46.0) + Vector2(0, 11), str(i / 2), 30, col, font_italic, HORIZONTAL_ALIGNMENT_CENTER, 60.0)
	_text(c + Vector2(-58, 52), "x1000 RPM", 13, Color(0.75, 0.82, 1.0, 0.7), font, HORIZONTAL_ALIGNMENT_CENTER, 120.0)

	# --- Rucicka ---
	var nd := _dir(_ang(frac))
	draw_line(c - nd * 22.0, c + nd * (r - 10.0), Color(1, 1, 1, 0.22), 11.0, true)
	draw_line(c - nd * 22.0, c + nd * (r - 10.0), Color(0.95, 0.97, 1.0), 4.0, true)
	draw_circle(c, 13.0, Color(0.12, 0.13, 0.18))
	draw_arc(c, 13.0, 0.0, TAU, 32, Color(0.85, 0.9, 1.0, 0.9), 2.5, true)

	# --- Vpravo: rychlostni stupen se sipkou pro preraeni ---
	var gpos := c + Vector2(62, -12)
	var gcol := C_ORANGE.lerp(Color.WHITE, _gear_flash)
	_text(gpos + Vector2(34, 22), gear_text, 62, gcol, font_italic, HORIZONTAL_ALIGNMENT_CENTER, 90.0)
	var shift := cur_gear > 0 and cur_gear < gear_max and _rpm > redline * 0.9
	var arrow := gpos + Vector2(-8, -6)
	var acol := C_GREEN if shift else Color(C_GREEN, 0.18)
	draw_colored_polygon(PackedVector2Array([arrow + Vector2(0, -16), arrow + Vector2(13, 6), arrow + Vector2(-13, 6)]), acol)
	draw_line(c + Vector2(38, 18), c + Vector2(r - 12, 18), Color(1, 1, 1, 0.18), 2.0, true)

	# --- Velka rychlost ---
	_text(c + Vector2(r - 8, 92), "%d" % int(round(_speed)), 78, Color.WHITE, font_italic, HORIZONTAL_ALIGNMENT_RIGHT, 220.0)
	_text(c + Vector2(r - 12, 122), "KM/H", 22, Color(0.85, 0.9, 1.0, 0.9), font_italic, HORIZONTAL_ALIGNMENT_RIGHT, 120.0)

	# --- N2O: modry segmentovany oblouk nahore vpravo (dobiji se i driftem) ---
	var n_start := deg_to_rad(282.0)
	var n_end := deg_to_rad(352.0)
	var segs := 14
	for i in segs:
		var a0 := lerpf(n_start, n_end, float(i) / segs) + 0.012
		var a1 := lerpf(n_start, n_end, float(i + 1) / segs) - 0.012
		var filled := (float(i) + 0.5) / segs <= nitro
		var col := Color(0.15, 0.2, 0.3, 0.55)
		if filled:
			col = C_N2O.lerp(Color(0.85, 0.95, 1.0), _n2o_glow)
			draw_arc(c, r + 26.0, a0, a1, 6, Color(col, 0.25), 20.0, true)
		draw_arc(c, r + 26.0, a0, a1, 6, col, 11.0, true)
	var label_a := deg_to_rad(272.0)
	draw_set_transform(c + _dir(label_a) * (r + 26.0), label_a + PI * 0.5, Vector2.ONE)
	draw_string(font_italic, Vector2(-26, 8), "N2O", HORIZONTAL_ALIGNMENT_CENTER, 52, 20, Color.WHITE if nitro_on else Color(0.7, 0.85, 1.0, 0.95))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# --- Maly budik turba vlevo dole ---
	var bc := c + Vector2(-r * 0.98, r * 0.62)
	var br := 56.0
	draw_circle(bc, br + 5.0, Color(0.02, 0.03, 0.07, 0.6))
	draw_arc(bc, br + 5.0, 0.0, TAU, 64, Color(0.55, 0.7, 1.0, 0.4), 2.0, true)
	var b_start := deg_to_rad(135.0)
	var b_sweep := deg_to_rad(270.0)
	draw_arc(bc, br - 4.0, b_start + b_sweep * 0.8, b_start + b_sweep, 12, Color(C_RED, 0.85), 6.0, true)
	draw_arc(bc, br - 4.0, b_start, b_start + b_sweep * 0.12, 8, Color(C_RED, 0.6), 6.0, true)
	for i in 7:
		var ba := b_start + b_sweep * float(i) / 6.0
		draw_line(bc + _dir(ba) * (br - 13.0), bc + _dir(ba) * (br - 2.0), C_TICK, 2.0, true)
	var bn := _dir(b_start + b_sweep * clampf((_boost + 30.0) / 60.0, 0.0, 1.0))
	draw_line(bc - bn * 8.0, bc + bn * (br - 8.0), Color(0.95, 0.97, 1.0), 3.0, true)
	draw_circle(bc, 6.0, Color(0.15, 0.16, 0.2))
	_text(bc + Vector2(0, 30), "TURBO", 12, Color(0.75, 0.82, 1.0, 0.75), font, HORIZONTAL_ALIGNMENT_CENTER, 80.0)
