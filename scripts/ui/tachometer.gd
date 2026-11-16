class_name Tachometer
extends Control
## Moderni digitalni pristrojovka (kreslena v kodu): tenky svitici oblouk otacek,
## rovne ciste cislice, uprostred velka rychlost, dole rychlostni stupen,
## vpravo modry sloupec N2O. Zadne sikme pismo.

const START_DEG := 135.0       # 0 ot./min vlevo dole
const SWEEP_DEG := 270.0       # po smeru hodinovych rucicek az vpravo dolu
const C_TEXT := Color(0.94, 0.96, 1.0)
const C_ACCENT := Color(0.15, 0.85, 1.0)
const C_HOT := Color(1.0, 0.25, 0.55)
const C_RED := Color(1.0, 0.18, 0.2)
const C_GREEN := Color(0.35, 1.0, 0.45)
const C_N2O := Color(0.2, 0.55, 1.0)
const CAP := 0.69              # vyska cislic pisma Oxanium (podil velikosti)

var car: Node  # Car nebo GevpCar
var font_bold: FontVariation
var font_medium: FontVariation
var _rpm := 0.0
var _speed := 0.0
var _gear_flash := 0.0
var _last_gear := 1
var _n2o_glow := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(460, 440)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var base: Font = load("res://assets/fonts/Oxanium.ttf")
	font_bold = FontVariation.new()
	font_bold.base_font = base
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	font_bold.variation_opentype = {wght: 740}
	font_medium = FontVariation.new()
	font_medium.base_font = base
	font_medium.variation_opentype = {wght: 600}


func _process(delta: float) -> void:
	if car and is_instance_valid(car) and car.get("t"):
		var rpm_now: float = car.rpm
		var spd: float = car.speed_kmh
		_rpm = lerpf(_rpm, rpm_now, 1.0 - exp(-18.0 * delta))
		_speed = lerpf(_speed, spd, 1.0 - exp(-14.0 * delta))
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


## Text vystredeny presne na bod (vodorovne i svisle podle vysky cislic).
func _centered(center: Vector2, txt: String, fsize: int, col: Color, f: Font, shadow := true) -> void:
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var pos := Vector2(center.x - w * 0.5, center.y + fsize * CAP * 0.5)
	if shadow:
		draw_string(f, pos + Vector2(0, 2), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color(0, 0, 0, 0.5 * col.a))
	draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)


## Cislo s pevnou sirkou cislic (pri zmene hodnoty neposkakuje).
func _digits(center: Vector2, txt: String, fsize: int, col: Color, f: Font) -> void:
	var cell := f.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var x := center.x - cell * txt.length() * 0.5
	for i in txt.length():
		_centered(Vector2(x + cell * (i + 0.5), center.y), txt[i], fsize, col, f)


func _rounded_rect(rect: Rect2, radius: float, col: Color, filled := true, width := 2.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(int(radius))
	sb.anti_aliasing = true
	if filled:
		sb.bg_color = col
	else:
		sb.bg_color = Color(0, 0, 0, 0)
		sb.border_color = col
		sb.set_border_width_all(int(width))
	draw_style_box(sb, rect)


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
	var near_red := frac >= red_frac * 0.97
	var blink := fmod(Time.get_ticks_msec() / 80.0, 2.0) < 1.0

	var c := Vector2(size.x - 232.0, size.y - 218.0)
	var r := 164.0

	# --- Podklad: tmave sklo, jemny okraj ---
	draw_circle(c, r + 20.0, Color(0.025, 0.03, 0.055, 0.66))
	draw_arc(c, r + 20.0, 0.0, TAU, 128, Color(1, 1, 1, 0.10), 1.5, true)
	draw_circle(c, r - 62.0, Color(0, 0, 0, 0.25))
	draw_arc(c, r - 62.0, 0.0, TAU, 96, Color(1, 1, 1, 0.07), 1.5, true)

	# --- Draha oblouku otacek + cervene pole ---
	draw_arc(c, r, _ang(0.0), _ang(red_frac), 96, Color(1, 1, 1, 0.11), 14.0, true)
	draw_arc(c, r, _ang(red_frac), _ang(1.0), 24, Color(C_RED, 0.45), 14.0, true)

	# --- Svitici oblouk otacek ---
	var col := C_ACCENT.lerp(C_HOT, smoothstep(0.6, 0.97, frac / red_frac))
	if near_red:
		col = C_RED if blink else Color.WHITE
	if frac > 0.003:
		draw_arc(c, r, _ang(0.0), _ang(frac), 96, Color(col, 0.16), 26.0, true)
		draw_arc(c, r, _ang(0.0), _ang(frac), 96, col, 14.0, true)

	# --- Ryski a rovne cislice ---
	var n := int(max_rpm / 1000.0)
	for i in n * 2 + 1:
		var f := float(i) / float(n * 2)
		var d := _dir(_ang(f))
		var major := i % 2 == 0
		var red := f > red_frac - 0.001
		var tcol := C_RED if red else C_TEXT
		if major:
			draw_line(c + d * (r - 24.0), c + d * (r - 11.0), Color(tcol, 0.95), 2.5, true)
			_centered(c + d * (r - 44.0), str(i / 2), 27, Color(tcol, 0.95), font_bold)
		else:
			draw_line(c + d * (r - 17.0), c + d * (r - 11.0), Color(tcol, 0.45), 1.5, true)

	# --- Rucicka: tenka svetla cara od stredoveho pole k oblouku ---
	var nd := _dir(_ang(frac))
	var perp := Vector2(-nd.y, nd.x)
	var n0 := c + nd * (r - 60.0)
	var n1 := c + nd * (r + 9.0)
	draw_line(n0, n1, Color(col, 0.25), 9.0, true)
	draw_colored_polygon(PackedVector2Array([n0 + perp * 2.6, n1 + perp * 1.0, n1 - perp * 1.0, n0 - perp * 2.6]), Color.WHITE)

	# --- Stred: rychlost ---
	_digits(c + Vector2(0, -12), "%d" % int(round(_speed)), 84, Color.WHITE, font_bold)
	_centered(c + Vector2(0, 40), "K M / H", 17, Color(C_TEXT, 0.7), font_medium, false)
	_centered(c + Vector2(0, -70), "RPM  ×1000", 13, Color(C_TEXT, 0.5), font_medium, false)

	# --- Dole: rychlostni stupen (pri pretaceni sviti zelene = prerad) ---
	var shift := cur_gear > 0 and cur_gear < gear_max and _rpm > redline * 0.9
	var box := Rect2(c + Vector2(-34, r - 62.0), Vector2(68, 64))
	if shift:
		_rounded_rect(box, 12.0, Color(C_GREEN, 0.95))
		_centered(box.get_center() + Vector2(0, 1), gear_text, 46, Color(0.02, 0.08, 0.04), font_bold, false)
	else:
		_rounded_rect(box, 12.0, Color(0.03, 0.04, 0.07, 0.9))
		_rounded_rect(box, 12.0, Color(C_ACCENT.lerp(Color.WHITE, _gear_flash), 0.75 + 0.25 * _gear_flash), false, 2.0)
		_centered(box.get_center() + Vector2(0, 1), gear_text, 46, Color.WHITE, font_bold)

	# --- Vpravo: N2O jako segmentovany oblouk (plni se odspodu, dobiji se i driftem) ---
	var n_from := deg_to_rad(38.0)
	var n_to := deg_to_rad(-62.0)
	var segs := 16
	for i in segs:
		var a0 := lerpf(n_from, n_to, float(i) / segs) - 0.012
		var a1 := lerpf(n_from, n_to, float(i + 1) / segs) + 0.012
		var filled := (float(i) + 0.5) / segs <= nitro
		if filled:
			var ncol := C_N2O.lerp(Color(0.8, 0.95, 1.0), _n2o_glow)
			draw_arc(c, r + 36.0, a1, a0, 6, Color(ncol, 0.22), 18.0, true)
			draw_arc(c, r + 36.0, a1, a0, 6, ncol, 9.0, true)
		else:
			draw_arc(c, r + 36.0, a1, a0, 6, Color(1, 1, 1, 0.13), 9.0, true)
	var lab := c + _dir(deg_to_rad(47.0)) * (r + 38.0)
	_centered(lab, "N2O", 19, Color.WHITE if nitro_on else Color(0.55, 0.78, 1.0), font_bold)
