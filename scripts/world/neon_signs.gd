class_name NeonSigns
extends Node3D
## Neonove cedule mesta: vymyslene podniky, ruzna neonova pisma a typy cedul
## (svitici trubice, ramovane cedule, svisle hotelove cedule, sipky, billboardy).
## Nektere cedule blikaji nebo maji bezici svetlo - stara se o to _process.

const FONT_FILES := {
	"monoton": "res://assets/fonts/Monoton-Regular.ttf",
	"tilt": "res://assets/fonts/TiltNeon.ttf",
	"neonderthaw": "res://assets/fonts/Neonderthaw-Regular.ttf",
	"pacifico": "res://assets/fonts/Pacifico-Regular.ttf",
	"bebas": "res://assets/fonts/BebasNeue-Regular.ttf",
	"bungee": "res://assets/fonts/Bungee-Regular.ttf",
	"bungeeshade": "res://assets/fonts/BungeeShade-Regular.ttf",
	"righteous": "res://assets/fonts/Righteous-Regular.ttf",
	"audiowide": "res://assets/fonts/Audiowide-Regular.ttf",
	"kaushan": "res://assets/fonts/KaushanScript-Regular.ttf",
	"stencil": "res://assets/fonts/SairaStencilOne-Regular.ttf",
	"russo": "res://assets/fonts/RussoOne-Regular.ttf",
}
## Priblizna sirka znaku vuci velikosti pisma (pro ramecky)
const FONT_WIDTH := {
	"monoton": 0.78, "tilt": 0.55, "neonderthaw": 0.42, "pacifico": 0.55, "bebas": 0.4,
	"bungee": 0.72, "bungeeshade": 0.78, "righteous": 0.58, "audiowide": 0.68,
	"kaushan": 0.5, "stencil": 0.55, "russo": 0.62,
}

## Vymyslene podniky: [nazev, podtitul, pismo, styl]
const SHOPS := [
	["Noční Kometa", "BAR", "neonderthaw", "script"],
	["Pivnice U Pístu", "OD 1998", "righteous", "box"],
	["TURBO KEBAB", "NONSTOP", "bungee", "tube"],
	["Ramen Raketa", "POLÉVKY", "righteous", "tube"],
	["Pizza Vesuv", "ROZVOZ", "pacifico", "script"],
	["BISTRO KOSMOS", "", "audiowide", "box"],
	["Kafe Meteor", "ESPRESSO", "kaushan", "script"],
	["BURGER BUNKR", "OPEN", "stencil", "box"],
	["NUDLE NONSTOP", "", "bebas", "tube"],
	["Mléčný bar Luna", "", "neonderthaw", "script"],
	["Donut Drift", "KOBLIHY", "pacifico", "script"],
	["HERNA ŠTĚSTÍ", "AUTOMATY", "bungeeshade", "box"],
	["KINO ORBIT", "", "monoton", "tube"],
	["DISKO PULZ", "PÁ–SO", "monoton", "tube"],
	["Karaoke Král", "", "kaushan", "script"],
	["BOWLING STRIKE", "", "righteous", "tube"],
	["ARKÁDY 2000", "RETRO HRY", "audiowide", "box"],
	["KLUB ATOM", "", "monoton", "tube"],
	["PNEU DRIFT", "PNEUSERVIS", "stencil", "box"],
	["LAKOVNA CHROM", "AIRBRUSH", "russo", "box"],
	["NITRO GARÁŽ", "TUNING", "stencil", "box"],
	["AUTOSERVIS BLESK", "", "russo", "tube"],
	["MYČKA TURBO", "24 H", "bebas", "tube"],
	["VENTIL & VAČKA", "DÍLY", "righteous", "box"],
	["Tetování Drak", "", "kaushan", "script"],
	["Salon Venuše", "", "pacifico", "script"],
	["TAXI NEON", "", "bungee", "tube"],
	["LÉKÁRNA", "", "tilt", "box"],
	["ZASTAVÁRNA", "", "tilt", "box"],
	["SMĚNÁRNA", "EXCHANGE", "tilt", "box"],
	["Čajovna Mlha", "", "neonderthaw", "script"],
	["RYCHLÉ OBĚDY", "", "bebas", "tube"],
]
## Svisle cedule (hotely, vecerky)
const BLADES := [["HOTEL", "bebas"], ["MOTEL", "tilt"], ["VEČERKA", "bebas"], ["BAR", "monoton"],
	["KLUB", "bungee"], ["ORION", "tilt"], ["PŮLNOC", "bebas"], ["24/7", "audiowide"]]
## Billboardy na strechach: [radek 1, radek 2, pismo 1, pismo 2]
const BILLBOARDS := [
	["NEON WRECK", "noční závody bez pravidel", "monoton", "neonderthaw"],
	["VOLT", "energie na celou noc", "bungee", "pacifico"],
	["RÁDIO NEON 99,9", "jen rychlé písničky", "audiowide", "kaushan"],
	["PNEU DRIFT", "drží i v dešti", "stencil", "pacifico"],
	["TURBO KEBAB", "vždycky horký", "bungee", "kaushan"],
	["HOTEL ORION", "pokoje od 499 Kč", "tilt", "neonderthaw"],
	["KINO ORBIT", "půlnoční premiéry", "monoton", "kaushan"],
	["LAKOVNA CHROM", "lesk, který vydrží", "russo", "pacifico"],
]
const ARROWS := ["PARKOVIŠTĚ", "VJEZD", "MYČKA", "GARÁŽ", "OPEN"]

const PALETTE := [
	Color(1.0, 0.15, 0.7), Color(0.1, 0.85, 1.0), Color(1.0, 0.5, 0.08), Color(0.65, 0.25, 1.0),
	Color(0.2, 1.0, 0.45), Color(1.0, 0.2, 0.2), Color(1.0, 0.9, 0.2), Color(0.3, 0.5, 1.0),
]

var rng := RandomNumberGenerator.new()
var lights_ratio := 0.3
var _fonts := {}
var _mats := {}
var _flicker: Array = []   # [label, zakladni barva, svetlo, casovac, stav]
var _chase: Array = []     # [label, texty, index, casovac]
var _used_shops := {}


func font(key: String) -> Font:
	if not _fonts.has(key):
		_fonts[key] = load(FONT_FILES.get(key, FONT_FILES["russo"]))
	return _fonts[key]


func _color() -> Color:
	return PALETTE[rng.randi() % PALETTE.size()]


func _accent(c: Color) -> Color:
	var a := _color()
	while a.is_equal_approx(c):
		a = _color()
	return a


func _emissive(c: Color, energy: float) -> StandardMaterial3D:
	var key := "%s_%.1f" % [c.to_html(), energy]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
		_mats[key] = m
	return _mats[key]


func _dark() -> StandardMaterial3D:
	if not _mats.has("dark"):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.03, 0.03, 0.045)
		m.metallic = 0.5
		m.roughness = 0.35
		_mats["dark"] = m
	return _mats["dark"]


func _label(text: String, font_key: String, size: int, pixel: float, c: Color, glow := 1.8) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font(font_key)
	l.font_size = size
	l.pixel_size = pixel
	l.modulate = Color(c.r * glow, c.g * glow, c.b * glow)
	l.outline_modulate = Color(c.r, c.g, c.b, 0.5)
	l.outline_size = maxi(8, size / 9)
	l.shaded = false
	l.double_sided = false
	return l


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


## Neonovy ramecek z trubic kolem obdelniku (v rovine XY).
func _frame(parent: Node3D, w: float, h: float, c: Color, z := 0.0, thick := 0.06) -> void:
	var m := _emissive(c, 4.0)
	_box(parent, Vector3(w + thick, thick, thick), Vector3(0, h * 0.5, z), m)
	_box(parent, Vector3(w + thick, thick, thick), Vector3(0, -h * 0.5, z), m)
	_box(parent, Vector3(thick, h, thick), Vector3(-w * 0.5, 0, z), m)
	_box(parent, Vector3(thick, h, thick), Vector3(w * 0.5, 0, z), m)


func _text_width(text: String, font_key: String, size: int, pixel: float) -> float:
	return text.length() * size * pixel * float(FONT_WIDTH.get(font_key, 0.6))


func _root(pos: Vector3, yaw_deg: float) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.position = pos
	n.rotation_degrees = Vector3(0, yaw_deg, 0)
	return n


func _light(parent: Node3D, c: Color, pos: Vector3, energy := 2.5, rng_range := 12.0) -> OmniLight3D:
	if rng.randf() > lights_ratio:
		return null
	var light := OmniLight3D.new()
	light.light_color = c
	light.light_energy = energy
	light.omni_range = rng_range
	light.distance_fade_enabled = true
	light.distance_fade_begin = 110.0
	light.distance_fade_length = 30.0
	light.position = pos
	parent.add_child(light)
	return light


func _maybe_flicker(label: Label3D, light: OmniLight3D, chance: float) -> void:
	if rng.randf() < chance:
		_flicker.append([label, label.modulate, light, rng.randf_range(1.0, 6.0), true])


# ---------------------------------------------------------------------
#  Verejne funkce
# ---------------------------------------------------------------------

## Cedule obchodu nad vylohou. max_width = kolik mista je na fasade.
func shop_sign(pos: Vector3, yaw_deg: float, max_width: float) -> void:
	var info: Array = SHOPS[rng.randi() % SHOPS.size()]
	var tries := 0
	while _used_shops.get(info[0], 0) > 2 and tries < 8:
		info = SHOPS[rng.randi() % SHOPS.size()]
		tries += 1
	_used_shops[info[0]] = _used_shops.get(info[0], 0) + 1
	var text: String = info[0]
	var sub: String = info[1]
	var fk: String = info[2]
	var style: String = info[3]
	var c := _color()
	var acc := _accent(c)
	var size := 150
	var pixel := 0.02
	var w := _text_width(text, fk, size, pixel)
	if w > max_width * 0.85:
		pixel *= max_width * 0.85 / w
		w = max_width * 0.85
	var root := _root(pos, yaw_deg)
	match style:
		"box":
			var h := size * pixel * 1.25 + (0.45 if sub != "" else 0.0)
			_box(root, Vector3(w + 0.6, h, 0.18), Vector3(0, 0, -0.1), _dark())
			_frame(root, w + 0.45, h - 0.15, acc, 0.02)
			var main := _label(text, fk, size, pixel, c)
			main.position = Vector3(0, 0.18 if sub != "" else 0.0, 0.04)
			root.add_child(main)
			if sub != "":
				var s := _label(sub, "bebas", 90, pixel, acc, 1.6)
				s.position = Vector3(0, -h * 0.5 + 0.32, 0.04)
				root.add_child(s)
			_maybe_flicker(main, _light(root, c, Vector3(0, -1.2, 1.4)), 0.12)
		"script":
			var main := _label(text, fk, size + 30, pixel, c, 2.0)
			root.add_child(main)
			# Podtrzeni "tahem" pod napisem
			_box(root, Vector3(w * 0.8, 0.05, 0.05), Vector3(w * 0.05, -size * pixel * 0.55, 0.02), _emissive(acc, 4.0))
			if sub != "":
				var s := _label(sub, "bebas", 85, pixel, acc, 1.6)
				s.position = Vector3(w * 0.3, -size * pixel * 0.95, 0.02)
				root.add_child(s)
			_maybe_flicker(main, _light(root, c, Vector3(0, -1.2, 1.4)), 0.15)
		_:
			# Svitici trubice + tenky ramecek
			var main := _label(text, fk, size, pixel, c, 2.0)
			root.add_child(main)
			var h := size * pixel * 1.1
			if rng.randf() < 0.5:
				_frame(root, w + 0.5, h + (0.35 if sub != "" else 0.0), acc, -0.02, 0.045)
			if sub != "":
				var s := _label(sub, "tilt", 80, pixel, acc, 1.7)
				s.position = Vector3(0, -h * 0.62, 0.0)
				root.add_child(s)
			_maybe_flicker(main, _light(root, c, Vector3(0, -1.2, 1.4)), 0.2)


## Svisla cedule kolmo k fasade (hotel, vecerka) - je videt podel ulice.
## pos = misto na fasade, out_dir_yaw = natoceni fasady (smer ven z budovy).
func blade_sign(pos: Vector3, facade_yaw_deg: float) -> void:
	var info: Array = BLADES[rng.randi() % BLADES.size()]
	var text: String = info[0]
	var fk: String = info[1]
	var c := _color()
	var acc := _accent(c)
	var letters := "\n".join(text.split(""))
	var pixel := 0.022
	var size := 120
	var line_h := size * pixel * 1.05
	var h := line_h * text.length() + 0.6
	# Cedule trci 1.1 m z fasady, jeji plochy miri podel ulice
	var root := _root(pos, facade_yaw_deg)
	var blade := Node3D.new()
	root.add_child(blade)
	blade.position = Vector3(0, 0, 0.75)
	blade.rotation_degrees = Vector3(0, 90, 0)
	_box(blade, Vector3(1.1, h, 0.2), Vector3.ZERO, _dark())
	for side in [1.0, -1.0]:
		var face := Node3D.new()
		blade.add_child(face)
		face.position = Vector3(0, 0, 0.11 * side)
		face.rotation_degrees = Vector3(0, 0 if side > 0 else 180, 0)
		_frame(face, 0.95, h - 0.15, acc, 0.0, 0.045)
		var l := _label(letters, fk, size, pixel, c, 2.0)
		l.line_spacing = -size * 0.15
		face.add_child(l)
		if side > 0:
			_maybe_flicker(l, null, 0.15)
	# Drzak
	_box(root, Vector3(0.08, 0.08, 0.5), Vector3(0, h * 0.5 - 0.2, 0.25), _dark())
	_box(root, Vector3(0.08, 0.08, 0.5), Vector3(0, -h * 0.5 + 0.2, 0.25), _dark())
	_light(root, c, Vector3(0, 0, 1.6), 3.0, 10.0)


## Sipka s bezicim svetlem (parkoviste, vjezd).
func arrow_sign(pos: Vector3, yaw_deg: float) -> void:
	var text: String = ARROWS[rng.randi() % ARROWS.size()]
	var c := _color()
	var acc := _accent(c)
	var root := _root(pos, yaw_deg)
	var pixel := 0.02
	var w := _text_width(text, "bebas", 130, pixel)
	_box(root, Vector3(w + 2.2, 1.3, 0.16), Vector3(0.6, 0, -0.1), _dark())
	_frame(root, w + 2.0, 1.15, c, 0.02, 0.04)
	var l := _label(text, "bebas", 130, pixel, c)
	l.position = Vector3(-0.2, 0, 0.04)
	root.add_child(l)
	var arrow := _label("›››", "russo", 150, pixel, acc, 2.2)
	arrow.position = Vector3(w * 0.5 + 0.7, 0.05, 0.04)
	root.add_child(arrow)
	_chase.append([arrow, ["›  ", "›› ", "›››", "   "], 0, 0.0])


## Dvouradkovy billboard s ramem zarovek na strese.
func billboard(pos: Vector3, yaw_deg: float) -> void:
	var info: Array = BILLBOARDS[rng.randi() % BILLBOARDS.size()]
	var c := _color()
	var acc := _accent(c)
	var root := _root(pos, yaw_deg)
	var w := 13.0
	var h := 5.5
	_box(root, Vector3(w, h, 0.4), Vector3(0, 0, -0.25), _dark())
	# Ram ze "zarovek"
	var bulb := _emissive(Color(1.0, 0.85, 0.55), 6.0)
	var bulb_mesh := SphereMesh.new()
	bulb_mesh.radius = 0.07
	bulb_mesh.height = 0.14
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bulb_mesh
	var spots: Array[Vector3] = []
	var n_w := 26
	var n_h := 11
	for i in n_w + 1:
		var x := -w * 0.5 + w * i / n_w
		spots.append(Vector3(x, h * 0.5, 0.0))
		spots.append(Vector3(x, -h * 0.5, 0.0))
	for j in range(1, n_h):
		var y := -h * 0.5 + h * j / n_h
		spots.append(Vector3(-w * 0.5, y, 0.0))
		spots.append(Vector3(w * 0.5, y, 0.0))
	mm.instance_count = spots.size()
	for i in spots.size():
		mm.set_instance_transform(i, Transform3D(Basis(), spots[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = bulb
	root.add_child(mmi)
	var l1 := _label(info[0], info[2], 200, 0.045 * minf(1.0, 11.0 / maxf(_text_width(info[0], info[2], 200, 0.045), 0.1)), c, 2.0)
	l1.position = Vector3(0, 0.8, 0.02)
	root.add_child(l1)
	var l2 := _label(info[1], info[3], 140, 0.03 * minf(1.0, 11.0 / maxf(_text_width(info[1], info[3], 140, 0.03), 0.1)), acc, 1.9)
	l2.position = Vector3(0, -1.4, 0.02)
	root.add_child(l2)
	_light(root, c, Vector3(0, -2.0, 3.0), 4.0, 16.0)


## Velky napis bez cedule (napr. NEON WRECK nad parkovistem).
func big_text(text: String, font_key: String, pos: Vector3, yaw_deg: float, pixel: float, c: Color, size := 220) -> void:
	var root := _root(pos, yaw_deg)
	var l := _label(text, font_key, size, pixel, c, 2.2)
	root.add_child(l)
	var light := OmniLight3D.new()
	light.light_color = c
	light.light_energy = 4.0
	light.omni_range = 18.0
	light.position = Vector3(0, -1.5, 2.5)
	root.add_child(light)


# ---------------------------------------------------------------------
#  Animace: blikani a bezici svetlo
# ---------------------------------------------------------------------

func _process(delta: float) -> void:
	for f in _flicker:
		f[3] -= delta
		if f[3] <= 0.0:
			var on: bool = not f[4]
			f[4] = on
			# Vetsinou sviti, obcas kratce zablika
			f[3] = rng.randf_range(2.0, 9.0) if on else rng.randf_range(0.04, 0.18)
			if on and rng.randf() < 0.4:
				f[3] = rng.randf_range(0.05, 0.25)  # rychla serie bliknuti
			var label := f[0] as Label3D
			var base: Color = f[1]
			label.modulate = base if on else Color(base.r * 0.12, base.g * 0.12, base.b * 0.12)
			var light := f[2] as OmniLight3D
			if light and is_instance_valid(light):
				light.visible = on
	for ch in _chase:
		ch[3] -= delta
		if ch[3] <= 0.0:
			ch[3] = 0.22
			ch[2] = (int(ch[2]) + 1) % (ch[1] as Array).size()
			(ch[0] as Label3D).text = (ch[1] as Array)[ch[2]]
