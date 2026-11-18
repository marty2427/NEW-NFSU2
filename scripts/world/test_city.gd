extends Node3D
## Velke mesto s nepravidelnymi ulicemi, mestskym okruhem a treninkovou plochou.
## Ve dne (vyvoj) nebo v noci s neonovou atmosferou (F8). Varianta rizeni F7.

var car: Car
var camera: ChaseCamera
var hud: HUD
var city: CityBuilder
var circuit: Circuit
var circuit_index := 0
var _lot_index := -1
var _testing := false      # automaticke testy jezdi i mimo mesto (na zachranne rovine)
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var _sky_day: Sky
var _sky_night: Sky


func _ready() -> void:
	# Uvodni obrazovka: stavba mesta trva nekolik vterin, hrac ma videt, ze hra bezi
	var loading := _loading_screen()
	await get_tree().process_frame
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	_build_environment()
	city = CityBuilder.new()
	city.name = "Mapa"
	add_child(city)
	city.build()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--okruh="):
			circuit_index = clampi(int(arg.substr(8)), 0, city.map.circuits.size() - 1)
	_make_circuit()
	_spawn_player()
	_apply_daylight(Hra.daylight)
	Hra.daylight_changed.connect(_apply_daylight)
	print("[START] mesto postaveno za %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	loading.queue_free()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snapshot="):
			add_child(load("res://scripts/dev/snapshot.gd").new())
		if arg.begins_with("--profil="):
			Hra.profile = arg.substr(9)
			_respawn_here(car.car_id)
		if arg == "--noc":
			Hra.toggle_daylight()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--speedtest=") or arg.begins_with("--handlingtest="):
			_testing = true
			LapRecords.enabled = false
		if arg == "--autotest" or arg.begins_with("--speedtest=") or arg.begins_with("--handlingtest=") or arg.begins_with("--lap=") or arg.begins_with("--walltest="):
			add_child(load("res://scripts/dev/autotest.gd").new())
		if arg.begins_with("--demotest="):
			_testing = true
			LapRecords.enabled = false
			add_child.call_deferred(load("res://scripts/dev/demo_test.gd").new())


func _loading_screen() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	layer.add_child(box)
	for item in [["NEON WRECK", 96, Color(0.15, 0.85, 1.0)], ["stavím město…  (10 až 20 vteřin)", 30, Color(0.9, 0.92, 1.0)]]:
		var label := Label.new()
		label.text = item[0]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", load("res://assets/fonts/RussoOne-Regular.ttf"))
		label.add_theme_font_size_override("font_size", item[1])
		label.add_theme_color_override("font_color", item[2])
		box.add_child(label)
	return layer


func _make_circuit() -> void:
	if circuit:
		circuit.queue_free()
	circuit = Circuit.new()
	circuit.name = "Okruh"
	add_child(circuit)
	circuit.setup(city.map, circuit_index)
	if hud:
		hud.circuit = circuit
	if car and is_instance_valid(car):
		circuit.car = car


# ---------------------------------------------------------------------
#  Hrac
# ---------------------------------------------------------------------

func _spawn_player() -> void:
	camera = ChaseCamera.new()
	camera.name = "Kamera"
	add_child(camera)
	var spawn := circuit.grid_transform()
	camera.global_position = spawn.origin + spawn.basis * Vector3(0, 2, 7)
	hud = HUD.new()
	add_child(hud)
	hud.circuit = circuit
	hud.city_map = city.map
	var cars := CarTuning.list_cars()
	spawn_car(cars[0] if not cars.is_empty() else "octavia", spawn)
	hud.show_message(car.t.nazev, 3.0)


## Vytvori auto hrace podle zvolene varianty rizeni (nase fyzika nebo Easy Vehicle Physics).
func spawn_car(id: String, xform: Transform3D) -> void:
	if car and is_instance_valid(car):
		remove_child(car)
		car.queue_free()
	var c := Car.new()
	c.name = "AutoHrace"
	c.car_id = id
	c.is_player = true
	car = c
	car.transform = xform
	add_child(car)
	city.load_around(xform.origin)
	car.add_child(PlayerController.new())
	car.add_child(CarAudio.new())
	car.exploded.connect(_on_car_exploded)
	car.burning.connect(func(_c): hud.show_message("AUTO HOŘÍ! Za chvíli vybuchne", 3.0))
	camera.target = car
	hud.car = car
	circuit.car = car


## Kdyby auto vyletelo z mapy a propadlo pod mesto, vrati se na nejblizsi ulici.
func _physics_process(_delta: float) -> void:
	if car == null or not is_instance_valid(car) or city == null:
		return
	if car.global_position.y < CityBuilder.SAFE_Y + 25.0 and not _testing:
		var ne := city.map.nearest_edge(Vector2(car.global_position.x, car.global_position.z), 1500.0)
		if ne.e >= 0:
			var dir: Vector2 = ne.dir
			spawn_car(car.car_id, Transform3D(Basis.looking_at(Vector3(dir.x, 0, dir.y), Vector3.UP), Vector3(ne.point.x, ne.y + 0.8, ne.point.y)))
			hud.show_message("Zpátky na silnici", 2.0)


func _respawn_here(id: String) -> void:
	var xf := car.global_transform
	var fwd := -xf.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	spawn_car(id, Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), xf.origin + Vector3.UP * 0.6))


func _unhandled_input(event: InputEvent) -> void:
	if car == null or hud == null:
		return      # hra se jeste nacita
	var cars := CarTuning.list_cars()
	for i in 8:
		if event.is_action_pressed("auto_%d" % (i + 1)) and i < cars.size():
			_respawn_here(cars[i])
			hud.show_message(car.t.nazev, 2.0)
	if event.is_action_pressed("dalsi_auto") and not cars.is_empty():
		var k := cars.find(car.car_id)
		_respawn_here(cars[(k + 1) % cars.size()])
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
	if event.is_action_pressed("na_start"):
		# Postavi auto pred startovni branu okruhu
		spawn_car(car.car_id, circuit.grid_transform())
		circuit.reset()
		hud.show_message("Na startu", 1.5)
	if event.is_action_pressed("dalsi_okruh"):
		circuit_index = (circuit_index + 1) % city.map.circuits.size()
		_make_circuit()
		spawn_car(car.car_id, circuit.grid_transform())
		hud.show_message("Okruh: %s (%.1f km)" % [circuit.title, circuit.length / 1000.0], 3.0)
	if event.is_action_pressed("na_plochu"):
		# Presun na dalsi treninkovou plochu
		if not city.lot_spawns.is_empty():
			_lot_index = (_lot_index + 1) % city.lot_spawns.size()
			spawn_car(car.car_id, Transform3D(Basis(), city.lot_spawns[_lot_index]))
			circuit.reset()
			hud.show_message("Tréninková plocha %d" % (_lot_index + 1), 2.0)
	if event.is_action_pressed("zvuk"):
		var bus := AudioServer.get_bus_index("Master")
		AudioServer.set_bus_mute(bus, not AudioServer.is_bus_mute(bus))
		hud.show_message("Zvuk vypnut" if AudioServer.is_bus_mute(bus) else "Zvuk zapnut", 1.5)
	if event.is_action_pressed("test_poskozeni"):
		car.apply_damage(25.0)


func _on_car_exploded(c: Node) -> void:
	hud.show_message("AUTO ZNIČENO!", 3.0)
	await get_tree().create_timer(4.0).timeout
	if not is_instance_valid(c) or c != car:
		return
	spawn_car(c.car_id, circuit.grid_transform())
	circuit.reset()
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
	if city:
		city.set_daylight(day)
	if city and city.ground_material:
		city.ground_material.set_shader_parameter("wetness", 0.45 if day else 0.85)
	Graphics.apply()
