extends Node3D
## Testovaci mapa: velke parkoviste + mestska ctvrt s ulicemi.
## Ve dne (vyvoj) nebo v noci s neonovou atmosferou (F8). Varianta rizeni F7.

const SPAWN := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(232.0, 0.6, 0.0))

var car: RigidBody3D   # Car nebo GevpCar (podle varianty rizeni F7)
var camera: ChaseCamera
var hud: HUD
var city: CityBuilder
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var _sky_day: Sky
var _sky_night: Sky


func _ready() -> void:
	_build_environment()
	city = CityBuilder.new()
	city.name = "Mapa"
	add_child(city)
	city.build()
	_spawn_player()
	_apply_daylight(Hra.daylight)
	Hra.daylight_changed.connect(_apply_daylight)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snapshot="):
			add_child(load("res://scripts/dev/snapshot.gd").new())
		if arg.begins_with("--profil="):
			Hra.profile = arg.substr(9)
			_respawn_here(car.car_id)
		if arg == "--noc":
			Hra.toggle_daylight()
	for arg in OS.get_cmdline_user_args():
		if arg == "--autotest" or arg.begins_with("--speedtest=") or arg.begins_with("--handlingtest="):
			add_child(load("res://scripts/dev/autotest.gd").new())


# ---------------------------------------------------------------------
#  Hrac
# ---------------------------------------------------------------------

func _spawn_player() -> void:
	camera = ChaseCamera.new()
	camera.name = "Kamera"
	add_child(camera)
	camera.global_position = SPAWN.origin + SPAWN.basis * Vector3(0, 2, 7)
	hud = HUD.new()
	add_child(hud)
	var cars := CarTuning.list_cars()
	spawn_car(cars[0] if not cars.is_empty() else "octavia", SPAWN)
	hud.show_message(car.t.nazev, 3.0)


## Vytvori auto hrace podle zvolene varianty rizeni (nase fyzika nebo Easy Vehicle Physics).
func spawn_car(id: String, xform: Transform3D) -> void:
	if car and is_instance_valid(car):
		remove_child(car)
		car.queue_free()
	if Hra.profile == "gevp":
		car = GevpCar.create(id, true)
	else:
		var c := Car.new()
		c.name = "AutoHrace"
		c.car_id = id
		c.is_player = true
		car = c
	car.transform = xform
	add_child(car)
	car.add_child(PlayerController.new())
	car.exploded.connect(_on_car_exploded)
	camera.target = car
	hud.car = car


func _respawn_here(id: String) -> void:
	var xf := car.global_transform
	var fwd := -xf.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	spawn_car(id, Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), xf.origin + Vector3.UP * 0.6))


func _unhandled_input(event: InputEvent) -> void:
	var cars := CarTuning.list_cars()
	for i in 3:
		if event.is_action_pressed("auto_%d" % (i + 1)) and i < cars.size():
			_respawn_here(cars[i])
			hud.show_message(car.t.nazev, 2.0)
	if event.is_action_pressed("nacist_ladeni"):
		_respawn_here(car.car_id)
		hud.show_message("auta.cfg znovu načten", 1.5)
	if event.is_action_pressed("varianta_rizeni"):
		Hra.next_profile()
		_respawn_here(car.car_id)
		hud.show_message("Řízení: " + Hra.profile_name(), 2.5)
	if event.is_action_pressed("den_noc"):
		Hra.toggle_daylight()
		hud.show_message("Den" if Hra.daylight else "Noc", 1.5)
	if event.is_action_pressed("test_poskozeni"):
		car.apply_damage(25.0)


func _on_car_exploded(c: Node) -> void:
	hud.show_message("AUTO ZNIČENO!", 3.0)
	await get_tree().create_timer(4.0).timeout
	if not is_instance_valid(c) or c != car:
		return
	spawn_car(c.car_id, SPAWN)
	hud.show_message("Nové auto připraveno", 2.0)


# ---------------------------------------------------------------------
#  Prostredi: nocni obloha s mestem, mlha, mesic
# ---------------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/hdri/kloppenheim_07_puresky_2k.hdr")
	sky_mat.energy_multiplier = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0, deg_to_rad(40.0), 0)
	# Rovnomerne nocni osvetleni "mestskou zari", aby nic nebylo uplne cerne
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.4, 0.56)
	env.ambient_light_energy = 1.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.45
	env.tonemap_white = 8.0

	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_strength = 1.0
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.4
	env.glow_hdr_scale = 1.5
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 1.0)
	env.set_glow_level(2, 1.0)
	env.set_glow_level(3, 0.8)
	env.set_glow_level(4, 0.5)
	env.set_glow_level(5, 0.25)

	env.ssr_fade_in = 0.1
	env.ssr_fade_out = 2.0
	env.ssr_depth_tolerance = 0.4

	env.ssao_radius = 1.2
	env.ssao_intensity = 1.4

	env.sdfgi_use_occlusion = true
	env.sdfgi_read_sky_light = true
	env.sdfgi_energy = 1.2
	env.sdfgi_bounce_feedback = 0.5

	env.volumetric_fog_density = 0.0065
	env.volumetric_fog_albedo = Color(0.75, 0.78, 0.9)
	env.volumetric_fog_emission = Color(0.025, 0.02, 0.045)
	env.volumetric_fog_emission_energy = 1.0
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_length = 200.0
	env.volumetric_fog_gi_inject = 1.0
	env.volumetric_fog_sky_affect = 0.15

	env.fog_light_color = Color(0.2, 0.17, 0.3)
	env.fog_density = 0.004
	env.fog_sky_affect = 0.3

	env.adjustment_enabled = true
	env.adjustment_brightness = 1.05
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.2

	var we := WorldEnvironment.new()
	we.name = "Prostredi"
	we.environment = env
	we.add_to_group("world_env")
	add_child(we)
	world_env = we
	_sky_night = sky

	# Denni obloha (pro vyvoj - je videt vsechno)
	var day_mat := ProceduralSkyMaterial.new()
	day_mat.sky_top_color = Color(0.28, 0.48, 0.82)
	day_mat.sky_horizon_color = Color(0.68, 0.76, 0.86)
	day_mat.ground_bottom_color = Color(0.22, 0.22, 0.24)
	day_mat.ground_horizon_color = Color(0.6, 0.64, 0.7)
	day_mat.sun_angle_max = 20.0
	_sky_day = Sky.new()
	_sky_day.sky_material = day_mat

	sun = DirectionalLight3D.new()
	sun.name = "Slunce"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 160.0
	add_child(sun)


## Den = jasne slunce a modra obloha (vyvoj), noc = neonova atmosfera (F8).
func _apply_daylight(day: bool) -> void:
	var env := world_env.environment
	if day:
		env.sky = _sky_day
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_energy = 1.0
		env.ambient_light_sky_contribution = 1.0
		env.tonemap_exposure = 1.0
		env.tonemap_white = 6.0
		env.glow_intensity = 0.25
		env.glow_hdr_threshold = 1.6
		env.volumetric_fog_density = 0.0015
		env.volumetric_fog_albedo = Color(0.85, 0.9, 1.0)
		env.volumetric_fog_emission = Color(0, 0, 0)
		env.fog_light_color = Color(0.7, 0.78, 0.9)
		env.fog_density = 0.0012
		env.adjustment_brightness = 1.0
		env.adjustment_saturation = 1.1
		sun.light_color = Color(1.0, 0.96, 0.9)
		sun.light_energy = 1.7
		sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
		sun.rotation_degrees = Vector3(-48, -35, 0)
	else:
		env.sky = _sky_night
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.36, 0.4, 0.56)
		env.ambient_light_energy = 1.5
		env.tonemap_exposure = 1.45
		env.tonemap_white = 8.0
		env.glow_intensity = 0.45
		env.glow_hdr_threshold = 1.4
		env.volumetric_fog_density = 0.0065
		env.volumetric_fog_albedo = Color(0.75, 0.78, 0.9)
		env.volumetric_fog_emission = Color(0.025, 0.02, 0.045)
		env.fog_light_color = Color(0.2, 0.17, 0.3)
		env.fog_density = 0.004
		env.adjustment_brightness = 1.05
		env.adjustment_saturation = 1.2
		sun.light_color = Color(0.6, 0.7, 1.0)
		sun.light_energy = 0.35
		sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
		sun.rotation_degrees = Vector3(-55, 30, 0)
	# Poulicni lampy sviti jen v noci (ve dne by jen zbytecne braly vykon)
	for node in get_tree().get_nodes_in_group("street_lights"):
		(node as Light3D).visible = not day
	if city and city.ground_material:
		city.ground_material.set_shader_parameter("wetness", 0.45 if day else 0.85)
	Graphics.apply()
