class_name Tachometer
extends Control
## Pristrojovka ve stylu novejsich zavodnich her (kreslena v kodu): bez tezkeho cifernik-kotouce,
## jen tenky oblouk s drobnymi dilky, svitici "ocas" za rucickou, velka rychlost uprostred,
## rychlostni stupen v sikmem ramecku a nitro jako rada sikmych dilku. Cislice jsou rovne.

const START_DEG := 142.0       # 0 ot./min vlevo dole
const SWEEP_DEG := 256.0       # po smeru hodinovych rucicek az vpravo dolu
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
	custom_minimum_size = Vector2(500, 460)
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


## Sikmy obdelnik (rovnobeznik): stred, rozmer, sklon v pixelech.
func _slanted(center: Vector2, sz: Vector2, slant: float, col: Color, filled := true, width := 2.0) -> void:
	var h := sz * 0.5
	var pts := PackedVector2Array([
		center + Vector2(-h.x + slant * 0.5, -h.y), center + Vector2(h.x + slant * 0.5, -h.y),
		center + Vector2(h.x - slant * 0.5, h.y), center + Vector2(-h.x - slant * 0.5, h.y)])
	if filled:
		draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		draw_polyline(pts, col, width, true)


func _draw() -> void:
	if car == null or not is_instance_valid(car) or car.get("t") == null:
		return
	var redline: float = car.t.max_otacky
	var max_rpm := ceilf(redline / 1000.0 + 0.4) * 1000.0
	var frac := clampf(_rpm / max_rpm, 0.0, 1.0)
	var red_frac := redline / max_rpm
	var nitro: float = car.nitro
	var nitro_on: bool = car.nitro_active
	var gear_text: String = car.gear_label()
	var gear_max: int = car.t.pocet_rychlosti
	var cur_gear: int = car.gear
	var near_red := frac >= red_frac * 0.97
	var blink := fmod(Time.get_ticks_msec() / 80.0, 2.0) < 1.0

	var c := Vector2(size.x - 250.0, size.y - 250.0)
	var r := 178.0

	# --- Jemne ztmaveni pozadi (jen kvuli citelnosti, zadny kotouc) ---
	for i in 9:
		draw_circle(c, r + 34.0 - i * 20.0, Color(0.0, 0.01, 0.03, 0.085))

	var col := C_ACCENT.lerp(C_HOT, smoothstep(0.62, 0.97, frac / red_frac))
	if near_red:
		col = C_RED if blink else Color.WHITE

	# --- Svitici "ocas" za rucickou ---
	var a_now := _ang(frac)
	var slices := 26
	var step := deg_to_rad(1.9)
	for i in slices:
		var a1 := a_now - i * step
		var a0 := maxf(a1 - step, _ang(0.0))
		if a1 <= _ang(0.0):
			break
		var k := 1.0 - float(i) / slices
		var d0 := _dir(a0)
		var d1 := _dir(a1)
		draw_colored_polygon(PackedVector2Array([c + d0 * (r - 34.0), c + d1 * (r - 34.0), c + d1 * (r - 3.0), c + d0 * (r - 3.0)]), Color(col, 0.42 * k * k))

	# --- Tenky oblouk: zaklad, cervene pole, rozsvicena cast ---
	draw_arc(c, r, _ang(0.0), _ang(red_frac), 96, Color(1, 1, 1, 0.3), 2.0, true)
	draw_arc(c, r, _ang(red_frac), _ang(1.0), 24, Color(C_RED, 0.95), 4.0, true)
	if frac > 0.003:
		draw_arc(c, r, _ang(0.0), a_now, 96, Color(col, 0.22), 10.0, true)
		draw_arc(c, r, _ang(0.0), a_now, 96, col, 3.5, true)

	# --- Dilky po 250 ot./min a rovne cislice ---
	var n := int(max_rpm / 1000.0)
	for i in n * 4 + 1:
		var f := float(i) / float(n * 4)
		var d := _dir(_ang(f))
		var major := i % 4 == 0
		var red := f > red_frac - 0.001
		var lit := f <= frac + 0.001
		var tcol := C_RED if red else C_TEXT
		var alpha := (1.0 if lit else 0.42) if not red else 0.95
		if major:
			draw_line(c + d * (r - 20.0), c + d * (r - 4.0), Color(tcol, alpha), 3.0, true)
			var near_now := absf(_rpm / 1000.0 - float(i / 4)) < 0.5
			_centered(c + d * (r - 41.0), str(i / 4), 29 if near_now else 25, Color(tcol, 1.0 if near_now or red else 0.7), font_bold)
		else:
			draw_line(c + d * (r - 11.0), c + d * (r - 4.0), Color(tcol, alpha * 0.8), 1.6, true)

	# --- Rucicka: uzky klin ---
	var nd := _dir(a_now)
	var perp := Vector2(-nd.y, nd.x)
	var n0 := c + nd * (r - 52.0)
	var n1 := c + nd * (r + 10.0)
	draw_line(n0, n1, Color(col, 0.3), 10.0, true)
	draw_colored_polygon(PackedVector2Array([n0 + perp * 1.2, n1 + perp * 3.2, n1 - perp * 3.2, n0 - perp * 1.2]), Color.WHITE)

	# --- Stred: velka rychlost ---
	_digits(c + Vector2(0, -8), "%d" % int(round(_speed)), 104, Color.WHITE, font_bold)
	_centered(c + Vector2(0, 56), "K M / H", 18, Color(C_TEXT, 0.72), font_medium, false)
	_centered(c + Vector2(0, -78), "×1000  RPM", 13, Color(C_TEXT, 0.5), font_medium, false)

	# --- Rychlostni stupen v sikmem ramecku (zelene = prerad) ---
	var shift := cur_gear > 0 and cur_gear < gear_max and _rpm > redline * 0.9
	var gpos := c + Vector2(0, r - 52.0)
	var gsize := Vector2(74, 58)
	if shift:
		_slanted(gpos, gsize + Vector2(10, 10), 14.0, Color(C_GREEN, 0.25))
		_slanted(gpos, gsize, 14.0, Color(C_GREEN, 0.96))
		_centered(gpos + Vector2(0, 1), gear_text, 46, Color(0.02, 0.08, 0.04), font_bold, false)
	else:
		_slanted(gpos, gsize, 14.0, Color(0.02, 0.03, 0.06, 0.78))
		_slanted(gpos, gsize, 14.0, Color(C_ACCENT.lerp(Color.WHITE, _gear_flash), 0.85), false, 2.2)
		_centered(gpos + Vector2(0, 1), gear_text, 46, Color.WHITE, font_bold)
	_centered(gpos + Vector2(-66, 0), "GEAR", 13, Color(C_TEXT, 0.55), font_medium, false)

	# --- Nitro: rada sikmych dilku pod pristrojem (dobiji se i driftem) ---
	var segs := 14
	var seg_w := 19.0
	var gap_w := 5.0
	var total_w := segs * seg_w + (segs - 1) * gap_w
	var npos := c + Vector2(-total_w * 0.5 + 20.0, r + 22.0)
	var ncol := C_N2O.lerp(Color(0.85, 0.97, 1.0), _n2o_glow)
	for i in segs:
		var center := npos + Vector2(i * (seg_w + gap_w) + seg_w * 0.5, 0)
		var filled := (float(i) + 0.5) / segs <= nitro
		if filled:
			if nitro_on:
				_slanted(center, Vector2(seg_w + 6, 20), 7.0, Color(ncol, 0.25))
			_slanted(center, Vector2(seg_w, 13), 7.0, ncol)
		else:
			_slanted(center, Vector2(seg_w, 13), 7.0, Color(1, 1, 1, 0.16))
	_centered(npos + Vector2(-34, 0), "N2O", 18, Color.WHITE if nitro_on else Color(0.6, 0.82, 1.0), font_bold)
