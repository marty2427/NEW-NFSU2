extends Node3D
## Testovaci mapa: velke parkoviste + mestska ctvrt s ulicemi.
## Nocni atmosfera ve stylu poulicnich zavodu: mokry asfalt, lampy, neony, mlha.

const SPAWN := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(232.0, 0.6, 0.0))

var car: Car
var camera: ChaseCamera
var hud: HUD
var city: CityBuilder


func _ready() -> void:
	_build_environment()
	city = CityBuilder.new()
	city.name = "Mapa"
	add_child(city)
	city.build()
	_spawn_player()
	Graphics.apply()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snapshot="):
			add_child(load("res://scripts/dev/snapshot.gd").new())
	for arg in OS.get_cmdline_user_args():
		if arg == "--autotest" or arg.begins_with("--speedtest="):
			add_child(load("res://scripts/dev/autotest.gd").new())


# ---------------------------------------------------------------------
#  Hrac
# ---------------------------------------------------------------------

func _spawn_player() -> void:
	car = Car.new()
	car.name = "AutoHrace"
	var cars := CarTuning.list_cars()
	car.car_id = cars[0] if not cars.is_empty() else "octavia"
	car.is_player = true
	add_child(car)
	car.global_transform = SPAWN
	car.add_child(PlayerController.new())
	car.exploded.connect(_on_car_exploded)

	camera = ChaseCamera.new()
	camera.name = "Kamera"
	camera.target = car
	add_child(camera)
	camera.global_position = SPAWN.origin + SPAWN.basis * Vector3(0, 2, 7)

	hud = HUD.new()
	hud.car = car
	add_child(hud)
	hud.show_message(car.t.nazev, 3.0)


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
	car.teleport(Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), xf.origin + Vector3.UP * 0.6))
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
#  Prostredi: nocni obloha s mestem, mlha, mesic
# ---------------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/hdri/kloppenheim_07_puresky_2k.hdr")
	sky_mat.energy_multiplier = 0.4
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0, deg_to_rad(40.0), 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 2.4
	env.ambient_light_sky_contribution = 1.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.2
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

	var moon := DirectionalLight3D.new()
	moon.name = "Mesic"
	moon.light_color = Color(0.6, 0.7, 1.0)
	moon.light_energy = 0.35
	moon.shadow_enabled = true
	moon.directional_shadow_max_distance = 140.0
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	moon.rotation_degrees = Vector3(-55, 30, 0)
	add_child(moon)
