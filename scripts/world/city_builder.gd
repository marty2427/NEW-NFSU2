class_name CityBuilder
extends Node3D
## Generator testovaci mapy: mestska ctvrt s mrizkou ulic a velke parkoviste.
## Vse se stavi v kodu z textur a modelu v assets/.

const GRID := 90.0          # vzdalenost os ulic
const ROAD_HALF := 8.0      # polovina sirky vozovky
const SIDEWALK := 4.5       # sirka chodniku
const CURB := 0.15          # vyska obrubniku
const LINES := [-180.0, -90.0, 0.0, 90.0, 180.0]
const LOT_RECT := Rect2(196.0, -110.0, 210.0, 220.0)   # parkoviste (x, z, sirka, hloubka)

const SIGNS := ["RAMEN 24/7", "MOTEL", "NITRO GARAGE", "PIXEL BAR", "KARAOKE", "TURBO WASH",
	"NOODLES", "ARCADE", "PIZZA", "TATTOO", "CLUB NEON", "HOTEL", "SUSHI", "CASINO", "DINER",
	"AUTO PARTS", "TIRES", "BURGER", "DISCO", "KEBAB", "HERNA", "VEČERKA", "PIVNICE", "POTRAVINY",
	"NONSTOP", "BAR", "CINEMA", "PHARMACY", "TAXI", "LOUNGE"]
const NEON := [Color(1.0, 0.15, 0.75), Color(0.1, 0.85, 1.0), Color(1.0, 0.5, 0.1),
	Color(0.6, 0.25, 1.0), Color(0.2, 1.0, 0.45), Color(1.0, 0.2, 0.2)]
const FACADES := ["concrete_tile_facade", "exterior_wall_cladding", "red_brick"]

var rng := RandomNumberGenerator.new()
var _mats := {}
var _lamp_positions: Array[Transform3D] = []
var _building_shader: Shader


func build() -> void:
	rng.seed = 2427
	_building_shader = load("res://shaders/building.gdshader")
	_build_ground()
	_build_city_blocks()
	_build_outer_ring()
	_build_parking_lot()
	_build_street_lamps()
	_build_street_props()


# ---------------------------------------------------------------------
#  Materialy a pomocne funkce
# ---------------------------------------------------------------------

func pbr(tex_name: String, scale: float, tint := Color.WHITE, rough_mult := 1.0) -> StandardMaterial3D:
	var key := "%s_%.3f_%s_%.2f" % [tex_name, scale, tint.to_html(), rough_mult]
	if _mats.has(key):
		return _mats[key]
	var base := "res://assets/textures/%s/%s_" % [tex_name, tex_name]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(base + "diff.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(base + "nor.jpg")
	m.roughness_texture = load(base + "rough.jpg")
	m.roughness = rough_mult
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mats[key] = m
	return m


func simple(color: Color, metallic := 0.0, roughness := 0.8, emission := 0.0) -> StandardMaterial3D:
	var key := "s_%s_%.2f_%.2f_%.1f" % [color.to_html(), metallic, roughness, emission]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_mats[key] = m
	return m


func static_box(size: Vector3, xform: Transform3D, mat: Material, parent: Node = self, collide := true) -> Node3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	if not collide:
		parent.add_child(mi)
		mi.transform = xform
		return mi
	var body := StaticBody3D.new()
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	body.transform = xform
	return body


func mesh_at(mesh: Mesh, mat: Material, pos: Vector3, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos
	return mi


func noise_texture(freq: float, size: int, seed_value: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = freq
	n.fractal_octaves = 4
	var tex := NoiseTexture2D.new()
	tex.noise = n
	tex.width = size
	tex.height = size
	tex.seamless = true
	tex.generate_mipmaps = true
	return tex


## Neonovy napis (vymysleny, zadne skutecne znacky).
func neon_text(text: String, pos: Vector3, yaw_deg: float, pixel: float, color: Color, font_size := 160, with_light := true) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel
	label.modulate = Color(color.r * 1.8, color.g * 1.8, color.b * 1.8)
	label.outline_modulate = Color(color.r, color.g, color.b, 0.55)
	label.outline_size = 16
	label.shaded = false
	label.double_sided = false
	label.position = pos
	label.rotation_degrees = Vector3(0, yaw_deg, 0)
	add_child(label)
	if with_light:
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 2.5
		light.omni_range = 12.0
		light.distance_fade_enabled = true
		light.distance_fade_begin = 120.0
		light.distance_fade_length = 30.0
		light.position = pos + Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Vector3(0, -1.0, 1.5)
		add_child(light)


# ---------------------------------------------------------------------
#  Zem (asfalt se znacenim)
# ---------------------------------------------------------------------

func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Zem"
	add_child(body)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1400, 2, 1400)
	cs.shape = shape
	cs.position = Vector3(0, -1, 0)
	body.add_child(cs)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/city_ground.gdshader")
	mat.set_shader_parameter("asphalt_albedo", load("res://assets/textures/asphalt_02/asphalt_02_diff.jpg"))
	mat.set_shader_parameter("asphalt_normal", load("res://assets/textures/asphalt_02/asphalt_02_nor.jpg"))
	mat.set_shader_parameter("asphalt_rough", load("res://assets/textures/asphalt_02/asphalt_02_rough.jpg"))
	mat.set_shader_parameter("puddle_noise", noise_texture(0.02, 512, 7))
	mat.set_shader_parameter("grid", GRID)
	mat.set_shader_parameter("road_half", ROAD_HALF)
	mat.set_shader_parameter("city_rect", Vector4(LINES[0], LINES[0], LINES[-1], LINES[-1]))
	mat.set_shader_parameter("lot_rect", Vector4(LOT_RECT.position.x, LOT_RECT.position.y, LOT_RECT.end.x, LOT_RECT.end.y))
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400, 1400)
	var mi := mesh_at(plane, mat, Vector3.ZERO, body)
	mi.name = "Asfalt"


# ---------------------------------------------------------------------
#  Mestske bloky
# ---------------------------------------------------------------------

func _build_city_blocks() -> void:
	var holder := Node3D.new()
	holder.name = "Mesto"
	add_child(holder)
	var walk_mat := pbr("concrete_pavement", 0.35, Color(0.85, 0.85, 0.9))
	for ix in LINES.size() - 1:
		for iz in LINES.size() - 1:
			var x0: float = LINES[ix] + ROAD_HALF
			var x1: float = LINES[ix + 1] - ROAD_HALF
			var z0: float = LINES[iz] + ROAD_HALF
			var z1: float = LINES[iz + 1] - ROAD_HALF
			var block := Rect2(x0, z0, x1 - x0, z1 - z0)
			# Chodnik s obrubnikem
			static_box(Vector3(block.size.x, CURB, block.size.y), Transform3D(Basis(), Vector3(block.get_center().x, CURB * 0.5, block.get_center().y)), walk_mat, holder)
			var inner := block.grow(-SIDEWALK)
			var center_dist := Vector2(inner.get_center()).length()
			_fill_block(holder, inner, center_dist)


func _fill_block(holder: Node3D, inner: Rect2, center_dist: float) -> void:
	# Rozdeleni bloku na 2-3 x 2 parcely
	var nx := 2 + int(rng.randf() < 0.4)
	var nz := 2
	var gap := 2.0
	var cw := (inner.size.x - gap * (nx - 1)) / nx
	var cd := (inner.size.y - gap * (nz - 1)) / nz
	for i in nx:
		for j in nz:
			var x := inner.position.x + i * (cw + gap)
			var z := inner.position.y + j * (cd + gap)
			var tall := clampf(1.0 - center_dist / 260.0, 0.15, 1.0)
			var h := rng.randf_range(14.0, 30.0) + rng.randf() * 85.0 * tall * tall
			building(holder, Rect2(x, z, cw, cd), h)


## Jedna budova s fasadou, vylohami, napisy a neonem na strese.
func building(holder: Node3D, lot: Rect2, height: float) -> void:
	var size := Vector3(lot.size.x, height, lot.size.y)
	var center := Vector3(lot.get_center().x, CURB + height * 0.5, lot.get_center().y)
	var facade: String = FACADES[rng.randi() % FACADES.size()]
	var mat := ShaderMaterial.new()
	mat.shader = _building_shader
	mat.set_shader_parameter("wall_albedo", load("res://assets/textures/%s/%s_diff.jpg" % [facade, facade]))
	mat.set_shader_parameter("wall_normal", load("res://assets/textures/%s/%s_nor.jpg" % [facade, facade]))
	var tints := [Color(1, 1, 1), Color(0.75, 0.78, 0.85), Color(0.9, 0.82, 0.75), Color(0.6, 0.62, 0.7)]
	mat.set_shader_parameter("wall_tint", tints[rng.randi() % tints.size()])
	mat.set_shader_parameter("wall_scale", 0.22 if facade != "red_brick" else 0.35)
	mat.set_shader_parameter("seed", rng.randf() * 100.0)
	mat.set_shader_parameter("lit_ratio", rng.randf_range(0.25, 0.55))
	mat.set_shader_parameter("cell", Vector2(rng.randf_range(2.6, 3.8), rng.randf_range(3.2, 3.8)))
	var shop_cols := [Color(1.0, 0.8, 0.55), Color(0.8, 0.9, 1.0), Color(1.0, 0.65, 0.4)]
	mat.set_shader_parameter("shop_color", shop_cols[rng.randi() % shop_cols.size()])
	var body := static_box(size, Transform3D(Basis(), center), mat, holder)
	body.name = "Budova"

	# Strecha: tmava, s neonovym okrajem
	var roof := simple(Color(0.06, 0.06, 0.07), 0.0, 0.9)
	static_box(Vector3(size.x - 0.2, 0.3, size.z - 0.2), Transform3D(Basis(), Vector3(0, height * 0.5 + 0.15, 0)), roof, body, false)
	if rng.randf() < 0.6:
		var c: Color = NEON[rng.randi() % NEON.size()]
		var rim := BoxMesh.new()
		rim.size = Vector3(size.x + 0.25, 0.22, size.z + 0.25)
		mesh_at(rim, simple(c, 0.0, 0.3, 5.0), Vector3(0, height * 0.5 - rng.randf_range(0.4, 2.0), 0), body)

	# Napisy obchodu nad vylohami (na stranach k ulici)
	var sides := [
		[Vector3(0, 0, -size.z * 0.5 - 0.06), 180.0, size.x],
		[Vector3(0, 0, size.z * 0.5 + 0.06), 0.0, size.x],
		[Vector3(-size.x * 0.5 - 0.06, 0, 0), -90.0, size.z],
		[Vector3(size.x * 0.5 + 0.06, 0, 0), 90.0, size.z],
	]
	for s in sides:
		if rng.randf() < 0.55:
			var c: Color = NEON[rng.randi() % NEON.size()]
			var along: float = s[2]
			var off := rng.randf_range(-along * 0.3, along * 0.3)
			var dir := Basis(Vector3.UP, deg_to_rad(s[1]))
			var pos: Vector3 = center + s[0] + dir * Vector3(off, 0, 0)
			pos.y = CURB + 5.4
			neon_text(SIGNS[rng.randi() % SIGNS.size()], pos, s[1], 0.022, c, 150, rng.randf() < 0.25)
	# Velka reklama na strese nekterych budov
	if height < 45.0 and rng.randf() < 0.3:
		var c: Color = NEON[rng.randi() % NEON.size()]
		var yaw: float = [0.0, 90.0, 180.0, -90.0][rng.randi() % 4]
		var frame_pos := center + Vector3(0, height * 0.5 + 4.0, 0)
		static_box(Vector3(12, 5, 0.4), Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), frame_pos), simple(Color(0.03, 0.03, 0.04), 0.4, 0.5), self, false)
		neon_text(SIGNS[rng.randi() % SIGNS.size()], frame_pos + Basis(Vector3.UP, deg_to_rad(yaw)) * Vector3(0, 0, 0.25), yaw, 0.045, c, 160, true)


# ---------------------------------------------------------------------
#  Okraj mesta (budovy kolem, at ulice nekonci do prazdna)
# ---------------------------------------------------------------------

func _build_outer_ring() -> void:
	var holder := Node3D.new()
	holder.name = "Okraj"
	add_child(holder)
	var walk_mat := pbr("concrete_pavement", 0.35, Color(0.85, 0.85, 0.9))
	var edge: float = LINES[-1] + ROAD_HALF          # 188
	var outer := edge + SIDEWALK + 45.0
	# Chodniky + budovy na severu, jihu a zapade
	var strips := [
		Rect2(-outer, -outer, outer * 2.0, outer - edge),       # sever (z < -188)
		Rect2(-outer, edge, outer * 2.0, outer - edge),         # jih (z > 188)
		Rect2(-outer, -edge, outer - edge, edge * 2.0),         # zapad (x < -188)
	]
	for r in strips:
		static_box(Vector3(r.size.x, CURB, r.size.y), Transform3D(Basis(), Vector3(r.get_center().x, CURB * 0.5, r.get_center().y)), walk_mat, holder)
	# Budovy podel okraje
	for side in 3:
		var along := -edge
		while along < edge:
			var w := rng.randf_range(18.0, 34.0)
			w = minf(w, edge - along)
			if w < 8.0:
				break
			var d := rng.randf_range(22.0, 38.0)
			var lot: Rect2
			match side:
				0: lot = Rect2(along, -edge - SIDEWALK - d, w, d)
				1: lot = Rect2(along, edge + SIDEWALK, w, d)
				_: lot = Rect2(-edge - SIDEWALK - d, along, d, w)
			building(holder, lot, rng.randf_range(16.0, 55.0))
			along += w + 2.0
	# Vychod: budovy kolem parkoviste (nad a pod nim)
	for zr in [[-edge, LOT_RECT.position.y - 8.0], [LOT_RECT.end.y + 8.0, edge]]:
		static_box(Vector3(outer - edge, CURB, zr[1] - zr[0]), Transform3D(Basis(), Vector3((edge + outer) * 0.5, CURB * 0.5, (zr[0] + zr[1]) * 0.5)), walk_mat, holder)
		var z: float = zr[0]
		while z < zr[1] - 8.0:
			var w := minf(rng.randf_range(18.0, 30.0), zr[1] - z)
			building(holder, Rect2(edge + SIDEWALK, z, rng.randf_range(24.0, 36.0), w), rng.randf_range(16.0, 40.0))
			z += w + 2.0


# ---------------------------------------------------------------------
#  Parkoviste
# ---------------------------------------------------------------------

func _build_parking_lot() -> void:
	var holder := Node3D.new()
	holder.name = "Parkoviste"
	add_child(holder)
	var r := LOT_RECT
	var concrete := pbr("concrete_floor_worn_001", 0.4, Color(0.75, 0.75, 0.78))
	# Obvodova zed (na zapade s vjezdy z ulic)
	var wall_h := 1.2
	static_box(Vector3(r.size.x, wall_h, 0.8), Transform3D(Basis(), Vector3(r.get_center().x, wall_h * 0.5, r.position.y)), concrete, holder)
	static_box(Vector3(r.size.x, wall_h, 0.8), Transform3D(Basis(), Vector3(r.get_center().x, wall_h * 0.5, r.end.y)), concrete, holder)
	static_box(Vector3(0.8, wall_h, r.size.y), Transform3D(Basis(), Vector3(r.end.x, wall_h * 0.5, r.get_center().y)), concrete, holder)
	# Zapadni strana: chodnik s vjezdy u ulic z = -90, 0, 90
	var walk_mat := pbr("concrete_pavement", 0.35, Color(0.85, 0.85, 0.9))
	var edge: float = LINES[-1] + ROAD_HALF
	var openings := [-90.0, 0.0, 90.0]
	var z := r.position.y
	for o in openings + [r.end.y + ROAD_HALF]:
		var z_end: float = o - ROAD_HALF
		if z_end > z:
			static_box(Vector3(r.position.x - edge, CURB, z_end - z), Transform3D(Basis(), Vector3((edge + r.position.x) * 0.5, CURB * 0.5, (z + z_end) * 0.5)), walk_mat, holder)
		z = o + ROAD_HALF
	# Neonove pruhy na zdech
	for wz in [r.position.y, r.end.y]:
		var strip := BoxMesh.new()
		strip.size = Vector3(r.size.x, 0.08, 0.85)
		mesh_at(strip, simple(NEON[1], 0.0, 0.3, 3.0), Vector3(r.get_center().x, wall_h + 0.04, wz), holder)

	# Sklad s rolovacimi vraty na vychode
	var shutter := pbr("painted_metal_shutter", 0.25, Color(0.6, 0.65, 0.75))
	var wh := Vector3(18, 12, 120)
	static_box(wh, Transform3D(Basis(), Vector3(r.end.x - wh.x * 0.5 - 1.0, wh.y * 0.5, r.get_center().y)), pbr("container_side", 0.12, Color(0.35, 0.38, 0.45)), holder)
	for i in 5:
		var door_z := r.get_center().y - 40.0 + i * 20.0
		static_box(Vector3(0.2, 5, 8), Transform3D(Basis(), Vector3(r.end.x - wh.x - 1.1, 2.5, door_z)), shutter, holder, false)
		var lamp := BoxMesh.new()
		lamp.size = Vector3(0.6, 0.15, 1.2)
		mesh_at(lamp, simple(Color(1.0, 0.85, 0.6), 0.0, 0.3, 8.0), Vector3(r.end.x - wh.x - 1.5, 5.6, door_z), holder)
		var l := SpotLight3D.new()
		l.light_color = Color(1.0, 0.85, 0.6)
		l.light_energy = 10.0
		l.spot_range = 12.0
		l.spot_angle = 60.0
		l.position = Vector3(r.end.x - wh.x - 1.8, 5.5, door_z)
		l.rotation_degrees = Vector3(-90, 0, 0)
		holder.add_child(l)
	neon_text("NITRO GARAGE", Vector3(r.end.x - wh.x - 1.2, 9.0, r.get_center().y), -90.0, 0.06, NEON[0], 220, true)

	# Velky napis NEON WRECK
	var sign_pos := Vector3(r.get_center().x - 20.0, 10.0, r.position.y + 6.0)
	static_box(Vector3(30, 7, 0.5), Transform3D(Basis(), sign_pos + Vector3(0, 0, -0.4)), simple(Color(0.03, 0.03, 0.05), 0.5, 0.4), holder)
	for lx in [-11.0, 11.0]:
		static_box(Vector3(0.6, sign_pos.y - 3.5, 0.6), Transform3D(Basis(), Vector3(sign_pos.x + lx, (sign_pos.y - 3.5) * 0.5, sign_pos.z - 0.4)), simple(Color(0.15, 0.15, 0.17), 0.8, 0.4), holder)
	neon_text("NEON WRECK", sign_pos, 0.0, 0.07, NEON[0], 260, true)

	# Rampy
	var ramp_mat := pbr("concrete_floor_worn_001", 0.4, Color(0.6, 0.6, 0.65))
	var stripe := simple(Color(1.0, 0.75, 0.0), 0.0, 0.4, 3.0)
	var ramps := [
		[Vector3(r.get_center().x - 30.0, 0, r.get_center().y + 10.0), 0.0, 12.0, 2.2, 8.0],
		[Vector3(r.get_center().x + 25.0, 0, r.get_center().y - 30.0), 90.0, 18.0, 3.6, 10.0],
		[Vector3(r.get_center().x + 10.0, 0, r.get_center().y + 60.0), -90.0, 10.0, 1.5, 7.0],
	]
	for rp in ramps:
		var length: float = rp[2]
		var height: float = rp[3]
		var width: float = rp[4]
		var prism := PrismMesh.new()
		prism.left_to_right = 1.0
		prism.size = Vector3(length, height, width)
		var body := StaticBody3D.new()
		body.name = "Rampa"
		holder.add_child(body)
		body.position = (rp[0] as Vector3) + Vector3(0, height * 0.5, 0)
		body.rotation_degrees = Vector3(0, 90.0 + float(rp[1]), 0)
		mesh_at(prism, ramp_mat, Vector3.ZERO, body)
		var cs := CollisionShape3D.new()
		cs.shape = prism.create_convex_shape()
		body.add_child(cs)
		var edge_mesh := BoxMesh.new()
		edge_mesh.size = Vector3(0.2, 0.1, width)
		mesh_at(edge_mesh, stripe, Vector3(length * 0.5 - 0.1, height * 0.5 + 0.02, 0), body)

	# Kontejnery
	var cont_tints := [Color(0.7, 0.2, 0.15), Color(0.15, 0.35, 0.65), Color(0.2, 0.5, 0.3), Color(0.75, 0.55, 0.15)]
	for c in [[Vector3(r.position.x + 40, 0, r.position.y + 20), 0.2], [Vector3(r.position.x + 46, 0, r.position.y + 24), 0.05],
			[Vector3(r.position.x + 43, 2.6, r.position.y + 22), 0.12], [Vector3(r.end.x - 50, 0, r.end.y - 20), -0.4],
			[Vector3(r.position.x + 70, 0, r.end.y - 15), 1.5]]:
		var tint: Color = cont_tints[rng.randi() % cont_tints.size()]
		static_box(Vector3(2.5, 2.6, 6.1), Transform3D(Basis(Vector3.UP, c[1]), (c[0] as Vector3) + Vector3(0, 1.3, 0)), pbr("container_side", 0.33, tint), holder)

	# Betonove zabrany (model) - slalom a hrazeni
	for i in 10:
		place_prop("concrete_road_barrier", Vector3(r.position.x + 60 + i * 9.0, 0, r.get_center().y - 60 + (3.0 if i % 2 == 0 else -3.0)), rng.randf_range(-0.3, 0.3), false)
	# Sudy a bedny (fyzicke, daji se odstrcit)
	for i in 14:
		place_prop("Barrel_01", Vector3(r.position.x + 120 + rng.randf_range(-12, 12), 0, r.get_center().y + 40 + rng.randf_range(-12, 12)), rng.randf() * TAU, true, 40.0)
	for i in 8:
		place_prop("wooden_crate_01", Vector3(r.position.x + 30 + rng.randf_range(-6, 6), 0, r.get_center().y - 20 + rng.randf_range(-6, 6)), rng.randf() * TAU, true, 15.0)

	# Vysoke lampy na parkovisti
	for ix in 4:
		for iz in 4:
			var p := Vector3(r.position.x + 30 + ix * 48.0, 0, r.position.y + 30 + iz * 53.0)
			_lamp_positions.append(Transform3D(Basis(), p))


## Umisti model rekvizity z assets/props. dynamic = fyzicky objekt, ktery jde odstrcit.
func place_prop(prop: String, pos: Vector3, yaw: float, dynamic: bool, mass := 30.0) -> Node3D:
	var scene := load("res://assets/props/%s/%s_1k.gltf" % [prop, prop]) as PackedScene
	if scene == null:
		return null
	var inst := scene.instantiate() as Node3D
	# Nektere modely obsahuji vedle sebe dve varianty (nova/rezava) - nechame jen jednu
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name)
		if nm.contains("aged") or nm.contains("rust"):
			mi.get_parent().remove_child(mi)
			mi.free()
	var aabb := AABB()
	var first := true
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh:
			var a: AABB = CarModel.xform_to(m, inst) * m.mesh.get_aabb()
			aabb = a if first else aabb.merge(a)
			first = false
	var body: CollisionObject3D
	if dynamic:
		var rb := RigidBody3D.new()
		rb.mass = mass
		rb.add_to_group("props")
		body = rb
	else:
		body = StaticBody3D.new()
	body.name = prop
	body.add_child(inst)
	inst.position = -Vector3(aabb.get_center().x, 0, aabb.get_center().z)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = aabb.size.max(Vector3.ONE * 0.05)
	cs.shape = shape
	cs.position = Vector3(0, aabb.get_center().y, 0)
	body.add_child(cs)
	add_child(body)
	body.position = pos + Vector3(0, 0.02, 0)
	body.rotation.y = yaw
	return body


# ---------------------------------------------------------------------
#  Poulicni lampy (sodikove oranzove + bile), jedno MultiMesh pro vsechny
# ---------------------------------------------------------------------

func _build_street_lamps() -> void:
	# Pozice podel ulic, na obou stranach, mimo krizovatky
	var off := ROAD_HALF + 0.8
	for line in LINES:
		for seg in LINES.size() - 1:
			var a: float = LINES[seg] + ROAD_HALF + SIDEWALK + 6.0
			var b: float = LINES[seg + 1] - ROAD_HALF - SIDEWALK - 6.0
			for k in 2:
				var t := lerpf(a, b, (k + 0.5) / 2.0)
				for side in [-1.0, 1.0]:
					# Ulice ve smeru Z (x = line) - rameno miri k ose ulice
					_lamp_positions.append(Transform3D(Basis(Vector3.UP, -PI * 0.5 if side < 0 else PI * 0.5), Vector3(line + side * off, CURB, t + side * 12.0)))
					# Ulice ve smeru X (z = line)
					_lamp_positions.append(Transform3D(Basis(Vector3.UP, PI if side < 0 else 0.0), Vector3(t + side * 12.0, CURB, line + side * off)))

	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.09
	pole_mesh.bottom_radius = 0.15
	pole_mesh.height = 9.0
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.12, 0.12, 2.4)
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.45, 0.16, 0.9)
	var glow_mesh := BoxMesh.new()
	glow_mesh.size = Vector3(0.38, 0.03, 0.8)
	var metal := simple(Color(0.22, 0.23, 0.25), 0.85, 0.35)
	var mm_pole := _multimesh(pole_mesh, metal)
	var mm_arm := _multimesh(arm_mesh, metal)
	var mm_head := _multimesh(head_mesh, metal)
	var warm := Color(1.0, 0.68, 0.38)
	var cool := Color(0.75, 0.88, 1.0)
	var mm_glow_warm := _multimesh(glow_mesh, simple(warm, 0.0, 0.3, 5.0))
	var mm_glow_cool := _multimesh(glow_mesh, simple(cool, 0.0, 0.3, 5.0))
	var poles: Array[Transform3D] = []
	var arms: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	var glows_w: Array[Transform3D] = []
	var glows_c: Array[Transform3D] = []
	var lights := Node3D.new()
	lights.name = "SvetlaLamp"
	add_child(lights)
	var i := 0
	for xf in _lamp_positions:
		var tall := xf.origin.y < 0.05  # lampy na parkovisti jsou vyssi
		var h := 13.0 if tall else 9.0
		var s := h / 9.0
		poles.append(Transform3D(xf.basis.scaled(Vector3(s, s, s)), xf.origin + Vector3(0, h * 0.5, 0)))
		var heads_local := [Vector3(0, h, -1.9)] if not tall else [Vector3(0, h, -1.9), Vector3(0, h, 1.9)]
		var is_warm := (i % 5) != 0
		for hl in heads_local:
			var arm_pos: Vector3 = xf * Vector3(0, h - 0.1, (hl as Vector3).z * 0.55)
			arms.append(Transform3D(xf.basis, arm_pos))
			var head_pos: Vector3 = xf * (hl as Vector3)
			heads.append(Transform3D(xf.basis, head_pos))
			var glow_xf := Transform3D(xf.basis, head_pos - Vector3(0, 0.08, 0))
			if is_warm:
				glows_w.append(glow_xf)
			else:
				glows_c.append(glow_xf)
			var spot := SpotLight3D.new()
			spot.light_color = warm if is_warm else cool
			spot.light_energy = 16.0 if not tall else 22.0
			spot.spot_range = h * 2.0
			spot.spot_angle = 58.0
			spot.spot_attenuation = 0.7
			spot.light_volumetric_fog_energy = 1.2
			spot.light_specular = 0.8
			spot.distance_fade_enabled = true
			spot.distance_fade_begin = 130.0
			spot.distance_fade_length = 40.0
			spot.position = head_pos - Vector3(0, 0.2, 0)
			spot.rotation_degrees = Vector3(-90, 0, 0)
			spot.add_to_group("street_lights")
			lights.add_child(spot)
		# Kolize sloupu
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.18
		shape.height = h
		cs.shape = shape
		body.add_child(cs)
		lights.add_child(body)
		body.position = xf.origin + Vector3(0, h * 0.5, 0)
		i += 1
	_fill_multimesh(mm_pole, poles)
	_fill_multimesh(mm_arm, arms)
	_fill_multimesh(mm_head, heads)
	_fill_multimesh(mm_glow_warm, glows_w)
	_fill_multimesh(mm_glow_cool, glows_c)


func _multimesh(mesh: Mesh, mat: Material) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
	return mmi


func _fill_multimesh(mmi: MultiMeshInstance3D, xforms: Array[Transform3D]) -> void:
	mmi.multimesh.instance_count = xforms.size()
	for i in xforms.size():
		mmi.multimesh.set_instance_transform(i, xforms[i])


# ---------------------------------------------------------------------
#  Drobnosti na chodnicich
# ---------------------------------------------------------------------

func _build_street_props() -> void:
	for line in LINES:
		for seg in LINES.size() - 1:
			var a: float = LINES[seg] + ROAD_HALF + SIDEWALK + 4.0
			var b: float = LINES[seg + 1] - ROAD_HALF - SIDEWALK - 4.0
			if rng.randf() < 0.5:
				var t := rng.randf_range(a, b)
				place_prop("metal_trash_can", Vector3(line + ROAD_HALF + 2.0, CURB, t), rng.randf() * TAU, true, 20.0)
			if rng.randf() < 0.4:
				var t2 := rng.randf_range(a, b)
				place_prop("fire_hydrant", Vector3(t2, CURB, line - ROAD_HALF - 1.2), 0.0, false)
