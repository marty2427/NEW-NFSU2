class_name NitroFlame
extends Node3D
## Plamen nitra z vyfuku: dva kuzele (vnejsi zelenkavy plast + svitive jadro) a male svetlo.
## Ovlada se jako castice: vlastnost emitting. Plamen se plynule rozhori a zhasne, delka se chveje.

var emitting := false
static var force_on := false     # jen pro vyvojove snimky
var _power := 0.0
var _outer: MeshInstance3D
var _core: MeshInstance3D
var _light: OmniLight3D
var _mats: Array[ShaderMaterial] = []
var _time := 0.0
var _seed := randf() * 100.0

const LEN := 1.05


func _ready() -> void:
	_outer = _cone(0.085, 0.012, LEN, 1.9, Color(0.3, 1.0, 0.6), Color(0.15, 0.55, 1.0))
	_core = _cone(0.045, 0.006, LEN * 0.55, 3.6, Color(0.6, 1.0, 0.85), Color(0.3, 0.8, 1.0))
	_light = OmniLight3D.new()
	_light.light_color = Color(0.35, 1.0, 0.75)
	_light.omni_range = 3.2
	_light.light_energy = 0.0
	_light.shadow_enabled = false
	_light.position = Vector3(0, 0, 0.35)
	add_child(_light)
	visible = false


func _cone(r0: float, r1: float, length: float, intensity: float, mid: Color, tip: Color) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.bottom_radius = r0
	m.top_radius = r1
	m.height = length
	m.radial_segments = 14
	m.rings = 6
	m.cap_top = false
	m.cap_bottom = false
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/nitro_flame.gdshader")
	mat.set_shader_parameter("height", length)
	mat.set_shader_parameter("intensity", intensity)
	mat.set_shader_parameter("col_mid", mid)
	mat.set_shader_parameter("col_tip", tip)
	mat.set_shader_parameter("seed", _seed)
	_mats.append(mat)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# kuzel stoji podel osy Y; otocit dozadu (+Z) a posunout, aby zacinal u vyfuku
	mi.basis = Basis(Vector3.RIGHT, PI * 0.5)
	mi.position = Vector3(0, 0, length * 0.5)
	add_child(mi)
	return mi


func _process(delta: float) -> void:
	_time += delta
	_power = move_toward(_power, 1.0 if emitting or force_on else 0.0, delta * 9.0)
	visible = _power > 0.01
	if not visible:
		return
	var flick := 0.88 + 0.12 * sin(_time * 53.0 + _seed) * sin(_time * 31.0)
	var s := lerpf(0.35, 1.0, _power) * flick
	scale = Vector3(1.0, 1.0, s)
	for mat in _mats:
		mat.set_shader_parameter("power", _power)
	_light.light_energy = 1.2 * _power * flick
