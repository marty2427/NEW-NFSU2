class_name HUD
extends CanvasLayer
## Herni ukazatele: rychlost, nitro, poskozeni, FPS, zpravy.

var car: Car

var _speed_label: Label
var _unit_label: Label
var _nitro_bar: ProgressBar
var _damage_bar: ProgressBar
var _damage_label: Label
var _info_label: Label
var _car_label: Label
var _message: Label
var _drift_label: Label
var _help: Label
var _blur_rect: ColorRect
var _vignette: ColorRect
var _message_time := 0.0
var _show_fps := true

const NEON_PINK := Color(1.0, 0.17, 0.84)
const NEON_CYAN := Color(0.13, 0.9, 1.0)


func _ready() -> void:
	layer = 10
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
	_info_label = _label(root, 20, Color(0.8, 0.85, 1.0))
	_info_label.position = Vector2(24, 18)
	_car_label = _label(root, 26, NEON_CYAN)
	_car_label.position = Vector2(24, 48)

	# --- Vpravo dole: rychlomer ---
	var panel := Control.new()
	root.add_child(panel)
	_place(panel, Control.PRESET_BOTTOM_RIGHT, -420, -230, -20, -20)

	_speed_label = _label(panel, 96, Color.WHITE)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_label.size = Vector2(300, 110)
	_speed_label.position = Vector2(0, 0)
	_speed_label.add_theme_color_override("font_outline_color", NEON_PINK)
	_speed_label.add_theme_constant_override("outline_size", 6)
	_unit_label = _label(panel, 28, NEON_PINK)
	_unit_label.text = "km/h"
	_unit_label.position = Vector2(310, 62)

	var nitro_title := _label(panel, 18, NEON_CYAN)
	nitro_title.text = "NITRO"
	nitro_title.position = Vector2(20, 118)
	_nitro_bar = _bar(panel, NEON_CYAN)
	_nitro_bar.position = Vector2(180, 122)
	_nitro_bar.size = Vector2(200, 20)

	_damage_label = _label(panel, 18, Color(1, 0.6, 0.3))
	_damage_label.text = "POŠKOZENÍ"
	_damage_label.position = Vector2(20, 156)
	_damage_bar = _bar(panel, Color(0.3, 1.0, 0.4))
	_damage_bar.position = Vector2(180, 160)
	_damage_bar.size = Vector2(200, 20)

	# --- Stred: zpravy ---
	_message = _label(root, 64, Color(1, 0.85, 0.3))
	_place(_message, Control.PRESET_CENTER_TOP, -600, 220, 600, 310)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_color_override("font_outline_color", Color(0.4, 0.0, 0.1))
	_message.add_theme_constant_override("outline_size", 10)

	_drift_label = _label(root, 44, NEON_PINK)
	_place(_drift_label, Control.PRESET_CENTER_BOTTOM, -300, -200, 300, -140)
	_drift_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_drift_label.add_theme_color_override("font_outline_color", Color(0.1, 0.0, 0.2))
	_drift_label.add_theme_constant_override("outline_size", 8)

	# --- Vlevo dole: ovladani ---
	_help = _label(root, 17, Color(0.75, 0.78, 0.9, 0.85))
	_place(_help, Control.PRESET_BOTTOM_LEFT, 24, -200, 700, -20)
	_help.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_help.text = "\n".join([
		"W/S nebo šipky ... plyn / brzda / couvání",
		"A/D ... zatáčení      MEZERNÍK ... ruční brzda",
		"SHIFT ... nitro       C ... kamera    Q ... pohled vzad",
		"R ... postavit auto   K ... test poškození",
		"1 / 2 / 3 ... změna auta   F6 ... znovu načíst auta.cfg",
		"F5 ... kvalita grafiky   F3 ... FPS   F11 ... celá obrazovka",
		"F1 ... skrýt nápovědu   ESC ... konec",
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
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _bar(parent: Node, color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0.0
	b.max_value = 1.0
	b.show_percentage = false
	b.size = Vector2(270, 20)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.1, 0.75)
	bg.border_color = color.darkened(0.3)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fill)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	return b


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
		info = "FPS: %d   |   %s" % [Engine.get_frames_per_second(), info]
	_info_label.text = info

	if _message_time > 0.0:
		_message_time -= delta
		_message.modulate.a = clampf(_message_time / 0.5, 0.0, 1.0)

	if car == null or not is_instance_valid(car):
		return
	_car_label.text = car.t.nazev if car.t else ""
	_speed_label.text = "%d" % int(round(car.speed_kmh))
	_nitro_bar.value = car.nitro
	var fill: StyleBoxFlat = _nitro_bar.get_theme_stylebox("fill")
	fill.bg_color = Color(1, 1, 1) if car.nitro_active else NEON_CYAN

	var d := car.damage_ratio()
	_damage_bar.value = d
	var dfill: StyleBoxFlat = _damage_bar.get_theme_stylebox("fill")
	dfill.bg_color = Color(0.3, 1.0, 0.4).lerp(Color(1.0, 0.85, 0.1), clampf(d * 2.0, 0.0, 1.0)).lerp(Color(1.0, 0.1, 0.1), clampf(d * 2.0 - 1.0, 0.0, 1.0))
	_damage_label.text = "ZNIČENO" if car.destroyed else "POŠKOZENÍ %d%%" % int(car.damage)

	_drift_label.text = "DRIFT  %d°" % int(car.drift_angle) if car.drifting else ""

	# Efekty obrazovky
	var blur_mat := _blur_rect.material as ShaderMaterial
	var blur := 0.0
	if Graphics.speed_blur:
		blur = clampf((car.speed_kmh - 90.0) / 140.0, 0.0, 1.0)
		if car.nitro_active:
			blur = minf(1.0, blur + 0.45)
	_blur_rect.visible = blur > 0.01
	blur_mat.set_shader_parameter("strength", blur)
	var vig := _vignette.material as ShaderMaterial
	vig.set_shader_parameter("damage", clampf((d - 0.5) * 2.0, 0.0, 1.0))
	vig.set_shader_parameter("pulse", sin(Time.get_ticks_msec() / 150.0) * 0.5 + 0.5)
