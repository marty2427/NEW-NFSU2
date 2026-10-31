extends Node
## Nastaveni kvality grafiky: NIZKA / STREDNI / VYSOKA / ULTRA.
## Ve hre se prepina klavesou F5. Aktualni WorldEnvironment musi byt ve skupine "world_env".

signal quality_changed(level: int)

enum Quality { LOW, MEDIUM, HIGH, ULTRA }

const NAMES := ["NIZKA", "STREDNI", "VYSOKA", "ULTRA"]

## Vychozi kvalita pro herni PC (RTX 3060 Ti).
var quality: int = Quality.HIGH
## Zapnuty efekt rozmazani v rychlosti (pouziva HUD).
var speed_blur := true


func _ready() -> void:
	# Pocka, az se nacte scena, pak nastavi grafiku.
	apply.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("grafika"):
		set_quality((quality + 1) % NAMES.size())


func set_quality(level: int) -> void:
	quality = clampi(level, 0, NAMES.size() - 1)
	apply()
	quality_changed.emit(quality)


func quality_name() -> String:
	return NAMES[quality]


func apply() -> void:
	var vp := get_viewport()
	var q := quality

	# --- Vyhlazovani hran ---
	match q:
		Quality.LOW:
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		Quality.MEDIUM:
			vp.msaa_3d = Viewport.MSAA_2X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		_:
			vp.msaa_3d = Viewport.MSAA_4X
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.use_debanding = q >= Quality.MEDIUM

	# --- Stiny ---
	var shadow_size: int = [2048, 4096, 8192, 8192][q]
	RenderingServer.directional_shadow_atlas_set_size(shadow_size, true)
	vp.positional_shadow_atlas_size = [2048, 4096, 8192, 8192][q]
	var soft: int = [
		RenderingServer.SHADOW_QUALITY_HARD,
		RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
		RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
	][q]
	RenderingServer.directional_soft_shadow_filter_set_quality(soft)
	RenderingServer.positional_soft_shadow_filter_set_quality(soft)

	# --- Efekty prostredi ---
	speed_blur = q >= Quality.MEDIUM
	for node in get_tree().get_nodes_in_group("world_env"):
		var we := node as WorldEnvironment
		if we and we.environment:
			_apply_environment(we.environment, q)

	# --- Dosah poulicnich lamp (pocet svetel ve scene) ---
	var fade: float = [70.0, 100.0, 130.0, 180.0][q]
	for node in get_tree().get_nodes_in_group("street_lights"):
		var sl := node as Light3D
		if sl:
			sl.distance_fade_begin = fade

	# --- Svetla, ktera vrhaji stiny jen ve vyssi kvalite ---
	for node in get_tree().get_nodes_in_group("shadow_optional"):
		var light := node as Light3D
		if light:
			light.shadow_enabled = q >= Quality.HIGH


func _apply_environment(env: Environment, q: int) -> void:
	# Globalni osvetleni (SDFGI) - vysoka a ultra
	env.sdfgi_enabled = q >= Quality.HIGH
	if q >= Quality.HIGH:
		env.sdfgi_cascades = 4 if q == Quality.HIGH else 6
		RenderingServer.environment_set_sdfgi_ray_count(
			RenderingServer.ENV_SDFGI_RAY_COUNT_32 if q == Quality.HIGH else RenderingServer.ENV_SDFGI_RAY_COUNT_64)

	# Odrazy (SSR) - mokry asfalt
	env.ssr_enabled = q >= Quality.MEDIUM
	env.ssr_max_steps = [16, 32, 64, 96][q]

	# Ambient occlusion
	env.ssao_enabled = q >= Quality.MEDIUM
	env.ssil_enabled = q >= Quality.ULTRA

	# Objemova mlha
	env.volumetric_fog_enabled = q >= Quality.MEDIUM
	env.fog_enabled = q == Quality.LOW  # levna mlha jako nahrada
	match q:
		Quality.MEDIUM:
			RenderingServer.environment_set_volumetric_fog_volume_size(64, 64)
		Quality.HIGH:
			RenderingServer.environment_set_volumetric_fog_volume_size(128, 96)
		Quality.ULTRA:
			RenderingServer.environment_set_volumetric_fog_volume_size(160, 128)
	RenderingServer.environment_set_volumetric_fog_filter_active(q >= Quality.HIGH)

	# Bloom (zare svetel) - vzdy, je to zaklad stylu
	env.glow_enabled = true
