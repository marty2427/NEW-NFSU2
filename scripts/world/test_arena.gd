extends Node3D
## Testovaci arena pro fazi 1: nocni parkoviste mezi budovami,
## mokry asfalt, neony, rampy, prekazky a jedno auto hrace.

const ARENA := 90.0  # polovina velikosti areny v metrech
const SPAWN := Transform3D(Basis(), Vector3(0, 1.2, 40))

const NEON_COLORS := [
	Color(1.0, 0.15, 0.8),   # ruzova
	Color(0.1, 0.85, 1.0),   # azurova
	Color(1.0, 0.55, 0.1),   # oranzova
	Color(0.55, 0.2, 1.0),   # fialova
]

var car: Car
var camera: ChaseCamera
var hud: HUD
var _rng := RandomNumberGenerator.new()
var _mat_cache := {}


func _ready() -> void:
	_rng.seed = 2427
	_build_environment()
	_build_ground()
	_build_walls()
	_build_buildings()
	_build_lamps()
	_build_obstacles()
	_build_props()
	_build_signs()
	_spawn_player()
	if "--autotest" in OS.get_cmdline_user_args():
		var tester: Node = load("res://scripts/dev/autotest.gd").new()
		add_child(tester)


# ---------------------------------------------------------------------
#  Hrac
# ---------------------------------------------------------------------

func _spawn_player() -> void:
	car = Car.new()
	car.name = "AutoHrace"
	car.car_id = "ulicni"
	car.is_player = true
	add_child(car)
	car.global_transform = SPAWN
	car.add_child(PlayerController.new())
	car.exploded.connect(_on_car_exploded)

	camera = ChaseCamera.new()
	camera.name = "Kamera"
	camera.target = car
	add_child(camera)
	camera.global_position = SPAWN.origin + Vector3(0, 3, 8)

	hud = HUD.new()
	hud.car = car
	add_child(hud)
	hud.show_message("NEON WRECK - testovací aréna", 3.0)


func _unhandled_input(event: InputEvent) -> void:
	var cars := CarTuning.list_cars()
	for i in 3:
		if event.is_action_pressed("auto_%d" % (i + 1)) and i < cars.size():
			_change_car(cars[i])
	if event.is_action_pressed("nacist_ladeni"):
		_change_car(car.car_id)
		hud.show_message("auta.cfg znovu načten", 1.5)
	if event.is_action_pressed("test_poskozeni"):
		car.apply_damage(25.0)


func _change_car(id: String) -> void:
	var xf := car.global_transform
	var fwd := -xf.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	car.setup(id)
	car.teleport(Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), xf.origin + Vector3.UP * 0.8))
	hud.show_message(car.t.nazev, 2.0)


func _on_car_exploded(c: Car) -> void:
	hud.show_message("AUTO ZNIČENO!", 3.0)
	await get_tree().create_timer(4.0).timeout
	if not is_instance_valid(c):
		return
	c.setup(c.car_id)
	c.teleport(SPAWN)
	hud.show_message("Nové auto připraveno", 2.0)


# ---------------------------------------------------------------------
#  Prostredi: obloha, mlha, svetlo mesice
# ---------------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.01, 0.012, 0.035)
	sky_mat.sky_horizon_color = Color(0.22, 0.08, 0.26)
	sky_mat.ground_bottom_color = Color(0.0, 0.0, 0.0)
	sky_mat.ground_horizon_color = Color(0.1, 0.04, 0.12)
	sky_mat.sky_energy_multiplier = 0.6
	sky_mat.ground_energy_multiplier = 0.3
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.tonemap_white = 6.0

	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_strength = 1.05
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.8)
	env.set_glow_level(4, 0.5)
	env.set_glow_level(5, 0.3)

	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.3

	env.ssao_radius = 1.4
	env.ssao_intensity = 1.6

	env.sdfgi_use_occlusion = true
	env.sdfgi_read_sky_light = true
	env.sdfgi_energy = 1.0
	env.sdfgi_bounce_feedback = 0.6

	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.7, 0.7, 0.85)
	env.volumetric_fog_emission = Color(0.03, 0.012, 0.05)
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_length = 140.0
	env.volumetric_fog_gi_inject = 1.0
	env.volumetric_fog_sky_affect = 0.25

	env.fog_light_color = Color(0.18, 0.08, 0.25)
	env.fog_density = 0.006

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.15

	var we := WorldEnvironment.new()
	we.name = "Prostredi"
	we.environment = env
	we.add_to_group("world_env")
	add_child(we)

	var moon := DirectionalLight3D.new()
	moon.name = "Mesic"
	moon.light_color = Color(0.55, 0.62, 1.0)
	moon.light_energy = 0.35
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 160.0
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	moon.rotation_degrees = Vector3(-48, 35, 0)
	add_child(moon)
	Graphics.apply()


# ---------------------------------------------------------------------
#  Pomocne funkce
# ---------------------------------------------------------------------

func _material(key: String, color: Color, metallic := 0.0, roughness := 0.8, emission := 0.0) -> StandardMaterial3D:
	var k := "%s_%s_%.2f_%.2f_%.1f" % [key, color.to_html(), metallic, roughness, emission]
	if _mat_cache.has(k):
		return _mat_cache[k]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	_mat_cache[k] = m
	return m


func _static_box(size: Vector3, xform: Transform3D, mat: Material, parent: Node = self) -> StaticBody3D:
	var body := StaticBody3D.new()
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	parent.add_child(body)
	body.global_transform = xform
	return body


func _mesh(mesh: Mesh, mat: Material, pos: Vector3, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos
	return mi


func _noise_texture(freq: float, size: int, seed_value: int) -> NoiseTexture2D:
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


# ---------------------------------------------------------------------
#  Zem
# ---------------------------------------------------------------------

func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Zem"
	add_child(body)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(800, 2, 800)
	cs.shape = shape
	cs.position = Vector3(0, -1, 0)
	body.add_child(cs)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/asphalt.gdshader")
	mat.set_shader_parameter("noise_big", _noise_texture(0.012, 512, 7))
	mat.set_shader_parameter("noise_fine", _noise_texture(0.08, 512, 11))
	var plane := PlaneMesh.new()
	plane.size = Vector2(800, 800)
	plane.subdivide_width = 0
	plane.subdivide_depth = 0
	var mi := _mesh(plane, mat, Vector3.ZERO, body)
	mi.name = "Asfalt"

	# Vodorovne car y parkoviste (lehce svitici, at jsou videt v noci)
	var line_mat := _material("line", Color(0.85, 0.85, 0.8), 0.0, 0.5, 0.15)
	for i in range(-6, 7):
		var line := BoxMesh.new()
		line.size = Vector3(0.18, 0.01, 6.0)
		_mesh(line, line_mat, Vector3(i * 4.0, 0.005, -70.0), body)
		_mesh(line, line_mat, Vector3(i * 4.0, 0.005, 70.0), body)
	# Stredova prerusovana cara
	var dash := BoxMesh.new()
	dash.size = Vector3(0.22, 0.01, 3.0)
	var yellow := _material("dash", Color(1.0, 0.75, 0.1), 0.0, 0.5, 0.25)
	for i in range(-12, 13):
		_mesh(dash, yellow, Vector3(-30.0, 0.005, i * 6.0), body)
		_mesh(dash, yellow, Vector3(30.0, 0.005, i * 6.0), body)


# ---------------------------------------------------------------------
#  Steny areny s neonovym pruhem
# ---------------------------------------------------------------------

func _build_walls() -> void:
	var concrete := _material("concrete", Color(0.32, 0.32, 0.34), 0.0, 0.9)
	var walls := [
		[Vector3(0, 0, -ARENA), Vector3(ARENA * 2 + 2, 1.3, 1.0), 0],
		[Vector3(0, 0, ARENA), Vector3(ARENA * 2 + 2, 1.3, 1.0), 0],
		[Vector3(-ARENA, 0, 0), Vector3(1.0, 1.3, ARENA * 2), 1],
		[Vector3(ARENA, 0, 0), Vector3(1.0, 1.3, ARENA * 2), 1],
	]
	for w in walls:
		var pos: Vector3 = w[0]
		var size: Vector3 = w[1]
		var color: Color = NEON_COLORS[w[2]]
		var body := _static_box(size, Transform3D(Basis(), pos + Vector3(0, size.y * 0.5, 0)), concrete)
		body.name = "Stena"
		var strip := BoxMesh.new()
		strip.size = Vector3(size.x + 0.02, 0.08, size.z + 0.02)
		_mesh(strip, _material("neon", color, 0.0, 0.3, 6.0), Vector3(0, size.y * 0.5 + 0.04, 0), body)


# ---------------------------------------------------------------------
#  Budovy kolem areny
# ---------------------------------------------------------------------

func _build_buildings() -> void:
	var shader: Shader = load("res://shaders/building.gdshader")
	var holder := Node3D.new()
	holder.name = "Budovy"
	add_child(holder)
	var placed := 0
	for side in 4:
		var along := -ARENA - 30.0
		while along < ARENA + 30.0:
			var w := _rng.randf_range(14.0, 30.0)
			var d := _rng.randf_range(14.0, 26.0)
			var h := _rng.randf_range(18.0, 70.0)
			var dist := ARENA + 18.0 + d * 0.5 + _rng.randf_range(0.0, 10.0)
			var pos: Vector3
			var size: Vector3
			match side:
				0: pos = Vector3(along + w * 0.5, h * 0.5, -dist); size = Vector3(w, h, d)
				1: pos = Vector3(along + w * 0.5, h * 0.5, dist); size = Vector3(w, h, d)
				2: pos = Vector3(-dist, h * 0.5, along + w * 0.5); size = Vector3(d, h, w)
				_: pos = Vector3(dist, h * 0.5, along + w * 0.5); size = Vector3(d, h, w)
			var mat := ShaderMaterial.new()
			mat.shader = shader
			mat.set_shader_parameter("seed", float(placed) * 1.37)
			mat.set_shader_parameter("lit_ratio", _rng.randf_range(0.15, 0.45))
			mat.set_shader_parameter("wall_color", Color(0.03, 0.03, 0.04).lerp(Color(0.06, 0.05, 0.07), _rng.randf()))
			var body := _static_box(size, Transform3D(Basis(), pos), mat, holder)
			body.name = "Budova%d" % placed
			# Neonovy pruh po obvodu strechy
			if _rng.randf() < 0.55:
				var c: Color = NEON_COLORS[_rng.randi() % NEON_COLORS.size()]
				var rim := BoxMesh.new()
				rim.size = Vector3(size.x + 0.3, 0.25, size.z + 0.3)
				_mesh(rim, _material("neon", c, 0.0, 0.3, 5.0), Vector3(0, size.y * 0.5 - _rng.randf_range(0.5, 3.0), 0), body)
			placed += 1
			along += w + _rng.randf_range(2.0, 8.0)


# ---------------------------------------------------------------------
#  Poulicni lampy s barevnym svetlem
# ---------------------------------------------------------------------

func _build_lamps() -> void:
	var pole_mat := _material("pole", Color(0.15, 0.15, 0.17), 0.8, 0.4)
	var positions := []
	# Po obvodu areny
	for a in [-75.0, -45.0, -15.0, 15.0, 45.0, 75.0]:
		positions.append(Vector3(a, 0, -ARENA + 4.0))
		positions.append(Vector3(a, 0, ARENA - 4.0))
		positions.append(Vector3(-ARENA + 4.0, 0, a))
		positions.append(Vector3(ARENA - 4.0, 0, a))
	# Uvnitr areny
	for p in [Vector3(-30, 0, -30), Vector3(30, 0, -30), Vector3(-30, 0, 30), Vector3(30, 0, 30),
			Vector3(0, 0, -60), Vector3(0, 0, 60), Vector3(-60, 0, 0), Vector3(60, 0, 0)]:
		positions.append(p)
	var i := 0
	for p in positions:
		var color: Color = NEON_COLORS[i % NEON_COLORS.size()]
		var lamp := Node3D.new()
		lamp.name = "Lampa%d" % i
		add_child(lamp)
		lamp.position = p
		var body := StaticBody3D.new()
		lamp.add_child(body)
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = 0.25
		shape.height = 9.0
		cs.shape = shape
		cs.position = Vector3(0, 4.5, 0)
		body.add_child(cs)
		var pole := CylinderMesh.new()
		pole.top_radius = 0.12
		pole.bottom_radius = 0.2
		pole.height = 9.0
		_mesh(pole, pole_mat, Vector3(0, 4.5, 0), lamp)
		var head := BoxMesh.new()
		head.size = Vector3(1.6, 0.18, 0.5)
		_mesh(head, _material("lamp", color, 0.0, 0.3, 8.0), Vector3(0, 9.0, 0), lamp)
		var light := OmniLight3D.new()
		light.light_color = color
		light.light_energy = 7.0
		light.omni_range = 30.0
		light.omni_attenuation = 1.2
		light.light_volumetric_fog_energy = 1.5
		light.position = Vector3(0, 8.6, 0)
		if i % 4 == 0:
			light.shadow_enabled = true
			light.add_to_group("shadow_optional")
		lamp.add_child(light)
		i += 1


# ---------------------------------------------------------------------
#  Rampy a betonove prekazky
# ---------------------------------------------------------------------

func _build_obstacles() -> void:
	var ramp_mat := _material("ramp", Color(0.25, 0.25, 0.28), 0.3, 0.6)
	var stripe := _material("stripe", Color(1.0, 0.8, 0.0), 0.0, 0.4, 2.5)
	# [pozice, otoceni (stupne), delka, vyska, sirka]
	var ramps := [
		[Vector3(0, 0, -20), 0.0, 12.0, 2.2, 8.0],
		[Vector3(45, 0, 20), 90.0, 16.0, 3.5, 9.0],
		[Vector3(-50, 0, -30), -45.0, 10.0, 1.6, 7.0],
	]
	for r in ramps:
		var pos: Vector3 = r[0]
		var length: float = r[2]
		var height: float = r[3]
		var width: float = r[4]
		var prism := PrismMesh.new()
		prism.left_to_right = 1.0
		prism.size = Vector3(length, height, width)
		var body := StaticBody3D.new()
		body.name = "Rampa"
		add_child(body)
		body.position = pos + Vector3(0, height * 0.5, 0)
		# Rampa stoupa ve smeru -Z (dopredu)
		body.rotation_degrees = Vector3(0, 90.0 + float(r[1]), 0)
		_mesh(prism, ramp_mat, Vector3.ZERO, body)
		var cs := CollisionShape3D.new()
		cs.shape = prism.create_convex_shape()
		body.add_child(cs)
		# Svitici okraj nahore
		var edge := BoxMesh.new()
		edge.size = Vector3(0.2, 0.1, width)
		_mesh(edge, stripe, Vector3(length * 0.5 - 0.1, height * 0.5 + 0.02, 0), body)

	# Betonove bloky a kontejnery
	var concrete := _material("block", Color(0.4, 0.4, 0.42), 0.0, 0.9)
	for p in [Vector3(-20, 0, 10), Vector3(20, 0, -45), Vector3(-35, 0, 55), Vector3(60, 0, -60), Vector3(-65, 0, 5)]:
		_static_box(Vector3(4, 1.0, 1.2), Transform3D(Basis(Vector3.UP, _rng.randf_range(0, PI)), p + Vector3(0, 0.5, 0)), concrete).name = "Blok"
	var container_colors := [Color(0.6, 0.12, 0.1), Color(0.1, 0.3, 0.55), Color(0.15, 0.45, 0.2), Color(0.7, 0.5, 0.1)]
	for c in [[Vector3(-70, 0, -70), 0.3], [Vector3(-62, 0, -74), 0.1], [Vector3(72, 0, 66), -0.4], [Vector3(30, 0, 70), 1.5]]:
		var mat := _material("container", container_colors[_rng.randi() % container_colors.size()], 0.6, 0.5)
		_static_box(Vector3(2.5, 2.6, 6.0), Transform3D(Basis(Vector3.UP, c[1]), c[0] + Vector3(0, 1.3, 0)), mat).name = "Kontejner"


# ---------------------------------------------------------------------
#  Pohyblive predmety (v fazi 2 budou rozbitne)
# ---------------------------------------------------------------------

func _build_props() -> void:
	var barrel_mats := [_material("barrel_r", Color(0.7, 0.08, 0.05), 0.5, 0.5), _material("barrel_b", Color(0.05, 0.25, 0.7), 0.5, 0.5)]
	var tire_mat := _material("tire", Color(0.03, 0.03, 0.03), 0.0, 0.9)
	var cone_mat := _material("cone", Color(1.0, 0.35, 0.0), 0.0, 0.6, 0.6)
	# Sudy
	for i in 10:
		var p := Vector3(_rng.randf_range(-15, 15) - 35.0, 0, _rng.randf_range(-15, 15) + 30.0)
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.4
		cyl.bottom_radius = 0.4
		cyl.height = 1.0
		var shape := CylinderShape3D.new()
		shape.radius = 0.4
		shape.height = 1.0
		_rigid(cyl, shape, barrel_mats[i % 2], p + Vector3(0, 0.5, 0), 40.0, "Sud")
	# Stohy pneumatik
	for s in 4:
		var base := Vector3(25.0 + s * 3.0, 0, -10.0 + s * 2.0)
		for level in 3:
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.45
			cyl.bottom_radius = 0.45
			cyl.height = 0.3
			var shape := CylinderShape3D.new()
			shape.radius = 0.45
			shape.height = 0.3
			_rigid(cyl, shape, tire_mat, base + Vector3(0, 0.15 + level * 0.31, 0), 15.0, "Pneumatika")
	# Kuzely - slalom
	for i in 12:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.04
		cone.bottom_radius = 0.25
		cone.height = 0.75
		var shape := CylinderShape3D.new()
		shape.radius = 0.2
		shape.height = 0.75
		_rigid(cone, shape, cone_mat, Vector3(-40.0 + i * 6.0, 0.375, -55.0 + (2.0 if i % 2 == 0 else -2.0)), 4.0, "Kuzel")


func _rigid(mesh: Mesh, shape: Shape3D, mat: Material, pos: Vector3, mass: float, node_name: String) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.name = node_name
	body.mass = mass
	body.add_to_group("props")
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	body.position = pos
	return body


# ---------------------------------------------------------------------
#  Neonove napisy (vymyslene, zadne skutecne znacky)
# ---------------------------------------------------------------------

func _build_signs() -> void:
	_neon_text("NEON WRECK", Vector3(0, 9.0, -ARENA - 4.0), 0.0, 0.06, Color(1.0, 0.2, 0.85), 260)
	_static_box(Vector3(26, 6.5, 0.4), Transform3D(Basis(), Vector3(0, 9.0, -ARENA - 4.5)), _material("frame", Color(0.03, 0.03, 0.05), 0.5, 0.4))
	for leg_x in [-10.0, 10.0]:
		_static_box(Vector3(0.5, 6.0, 0.5), Transform3D(Basis(), Vector3(leg_x, 3.0, -ARENA - 4.5)), _material("pole", Color(0.15, 0.15, 0.17), 0.8, 0.4))
	var texts := ["RAMEN 24/7", "MOTEL", "NITRO GARAGE", "PIXEL BAR", "KARAOKE", "TURBO WASH", "NOODLES", "ARCADE"]
	var spots := [
		[Vector3(-60, 14, -ARENA - 19.0), 0.0], [Vector3(55, 18, -ARENA - 19.0), 0.0],
		[Vector3(-ARENA - 19.0, 12, -40), 90.0], [Vector3(-ARENA - 19.0, 16, 45), 90.0],
		[Vector3(ARENA + 19.0, 15, -30), -90.0], [Vector3(ARENA + 19.0, 11, 50), -90.0],
		[Vector3(-30, 13, ARENA + 19.0), 180.0], [Vector3(40, 17, ARENA + 19.0), 180.0],
	]
	for i in spots.size():
		var c: Color = NEON_COLORS[(i + 1) % NEON_COLORS.size()]
		_neon_text(texts[i], spots[i][0], spots[i][1], 0.04, c, 180)


func _neon_text(text: String, pos: Vector3, yaw_deg: float, pixel: float, color: Color, font_size: int) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel
	label.modulate = Color(color.r * 3.0, color.g * 3.0, color.b * 3.0)
	label.outline_modulate = Color(color.r, color.g, color.b, 0.6)
	label.outline_size = 18
	label.shaded = false
	label.double_sided = false
	label.position = pos
	label.rotation_degrees = Vector3(0, yaw_deg, 0)
	add_child(label)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 3.0
	light.omni_range = 16.0
	light.position = pos + Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Vector3(0, 0, 2.0)
	add_child(light)
