class_name HUD
extends CanvasLayer
## Herni ukazatele: otackomer/tachometr, drift body, FPS, zpravy.
## Poskozeni se ukazuje primo na aute (kour, ohen) a cervenym okrajem obrazovky.

var car: Car:
	set(value):
		car = value
		if _tacho:
			_tacho.car = value

var _tacho: Tachometer
var _info_label: Label
var _car_label: Label
var _message: Label
var _drift_label: Label
var _drift_score_label: Label
var _help: Label
var _blur_rect: ColorRect
var _vignette: ColorRect
var _message_time := 0.0
var _show_fps := true
var _drift_score := 0.0
var _drift_hold := 0.0
var _drift_banner_time := 0.0
var _font: Font

const NEON_PINK := Color(1.0, 0.17, 0.84)
const NEON_CYAN := Color(0.13, 0.9, 1.0)


func _ready() -> void:
	layer = 10
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Arial", "DejaVu Sans", "Sans-Serif"])
	sf.font_weight = 700
	_font = sf

	# Efekty pres celou obrazovku (pod ukazateli)
	var fx_layer := CanvasLayer.new()
	fx_layer.layer = 5
	add_child(fx_layer)
	_blur_rect = _fullscreen_shader(fx_layer, "res://shaders/speed_blur.gdshader")
	_vignette = _fullscreen_shader(fx_layer, "res://shaders/vignette.gdshader")

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# --- Vlevo nahore ---
	_car_label = _label(root, 30, Color.WHITE)
	_car_label.position = Vector2(28, 18)
	_car_label.add_theme_color_override("font_outline_color", Color(0.05, 0.1, 0.3))
	_car_label.add_theme_constant_override("outline_size", 6)
	_info_label = _label(root, 17, Color(0.75, 0.8, 0.95, 0.85))
	_info_label.position = Vector2(30, 58)

	# --- Vpravo dole: otackomer ---
	_tacho = Tachometer.new()
	root.add_child(_tacho)
	_place(_tacho, Control.PRESET_BOTTOM_RIGHT, -400, -440, -20, -10)
	_tacho.car = car

	# --- Stred: zpravy ---
	_message = _label(root, 60, Color(1, 0.9, 0.4))
	_place(_message, Control.PRESET_CENTER_TOP, -700, 200, 700, 290)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_color_override("font_outline_color", Color(0.35, 0.0, 0.15))
	_message.add_theme_constant_override("outline_size", 10)

	# --- Drift ---
	_drift_label = _label(root, 46, NEON_PINK)
	_place(_drift_label, Control.PRESET_CENTER_TOP, -400, 110, 400, 170)
	_drift_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drift_label.add_theme_color_override("font_outline_color", Color(0.15, 0.0, 0.25))
	_drift_label.add_theme_constant_override("outline_size", 8)
	_drift_score_label = _label(root, 30, Color.WHITE)
	_place(_drift_score_label, Control.PRESET_CENTER_TOP, -400, 165, 400, 205)
	_drift_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drift_score_label.add_theme_color_override("font_outline_color", Color(0.15, 0.0, 0.25))
	_drift_score_label.add_theme_constant_override("outline_size", 6)

	# --- Vlevo dole: ovladani ---
	_help = _label(root, 16, Color(0.8, 0.83, 0.95, 0.8))
	_place(_help, Control.PRESET_BOTTOM_LEFT, 28, -190, 760, -20)
	_help.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_help.text = "\n".join([
		"W/S nebo šipky ... plyn / brzda / couvání      A/D ... zatáčení",
		"MEZERNÍK ... ruční brzda      SHIFT ... nitro      C ... kamera      Q ... pohled vzad",
		"R ... postavit auto      1 / 2 ... změna auta      F6 ... znovu načíst auta.cfg",
		"F5 ... kvalita grafiky      F3 ... FPS      F11 ... celá obrazovka      K ... test poškození",
		"F1 ... skrýt nápovědu      ESC ... konec",
	])

	Graphics.quality_changed.connect(func(_q): show_message("Grafika: " + Graphics.quality_name(), 1.5))


func _place(c: Control, preset: int, left: float, top: float, right: float, bottom: float) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = left
	c.offset_top = top
	c.offset_right = right
	c.offset_bottom = bottom


func _fullscreen_shader(parent: Node, path: String) -> ColorRect:
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(path)
	rect.material = mat
	parent.add_child(rect)
	return rect


func _label(parent: Node, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func show_message(text: String, time := 2.5) -> void:
	_message.text = text
	_message_time = time
	_message.modulate.a = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F1:
		_help.visible = not _help.visible
	elif event.is_action_pressed("fps"):
		_show_fps = not _show_fps


func _process(delta: float) -> void:
	var info := "Grafika: %s" % Graphics.quality_name()
	if _show_fps:
		info = "FPS %d   ·   %s" % [Engine.get_frames_per_second(), info]
	_info_label.text = info

	if _message_time > 0.0:
		_message_time -= delta
		_message.modulate.a = clampf(_message_time / 0.5, 0.0, 1.0)

	if car == null or not is_instance_valid(car) or car.t == null:
		return
	_car_label.text = car.t.nazev
	_update_drift(delta)

	# Efekty obrazovky
	var blur_mat := _blur_rect.material as ShaderMaterial
	var blur := 0.0
	if Graphics.speed_blur:
		blur = clampf((car.speed_kmh - 80.0) / 170.0, 0.0, 1.0)
		if car.nitro_active:
			blur = minf(1.0, blur + 0.5)
	_blur_rect.visible = blur > 0.01
	blur_mat.set_shader_parameter("strength", blur)
	blur_mat.set_shader_parameter("nitro", 1.0 if car.nitro_active else 0.0)
	var vig := _vignette.material as ShaderMaterial
	vig.set_shader_parameter("damage", clampf((car.damage_ratio() - 0.6) * 2.5, 0.0, 1.0))
	vig.set_shader_parameter("pulse", sin(Time.get_ticks_msec() / 150.0) * 0.5 + 0.5)


## Body za drift (rychlost x uhel), po skonceni driftu se zobrazi souhrn.
func _update_drift(delta: float) -> void:
	if car.drifting and not car.destroyed:
		_drift_score += car.speed_kmh * car.drift_angle * delta * 0.15
		_drift_hold = 0.8
		_drift_label.text = "DRIFT  %d°" % int(car.drift_angle)
		_drift_score_label.text = "%d" % int(_drift_score)
		_drift_label.modulate.a = 1.0
		_drift_score_label.modulate.a = 1.0
	else:
		if _drift_hold > 0.0:
			_drift_hold -= delta
			if _drift_hold <= 0.0 and _drift_score > 50.0:
				_drift_label.text = "SKVĚLÝ DRIFT!" if _drift_score > 1500.0 else "DRIFT"
				_drift_score_label.text = "+%d" % int(_drift_score)
				_drift_banner_time = 1.6
				_drift_score = 0.0
			elif _drift_hold <= 0.0:
				_drift_score = 0.0
		if _drift_banner_time > 0.0:
			_drift_banner_time -= delta
			var a := clampf(_drift_banner_time / 0.5, 0.0, 1.0)
			_drift_label.modulate.a = a
			_drift_score_label.modulate.a = a
		elif _drift_hold <= 0.0:
			_drift_label.text = ""
			_drift_score_label.text = ""
