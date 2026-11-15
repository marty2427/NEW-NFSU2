class_name Circuit
extends Node3D
## Okruh mestem: trasa pres krizovatky, sipky v zatackach, startovni brana a mereni casu kola.

signal lap_finished(time: float, best: float)
signal checkpoint_passed(index: int, total: int)

## Krizovatky, pres ktere okruh vede (y = 0). Jede se v tomto poradi.
const POINTS := [
	Vector3(90, 0, 0), Vector3(-90, 0, 0), Vector3(-90, 0, 90), Vector3(0, 0, 90),
	Vector3(0, 0, 180), Vector3(180, 0, 180), Vector3(180, 0, -90), Vector3(90, 0, -90),
]
const GATE_RADIUS := 16.0

var car: Node3D
var lap_time := 0.0
var best_time := 0.0
var last_time := 0.0
var lap_count := 0
var running := false
var next_cp := 0          # index krizovatky, kterou ma hrac projet jako dalsi

var _markers: Array[Node3D] = []


static func path() -> PackedVector3Array:
	return PackedVector3Array(POINTS)


## Misto a smer startu (na prvni rovince, 30 m za prvni krizovatkou).
static func start_transform() -> Transform3D:
	var a: Vector3 = POINTS[0]
	var b: Vector3 = POINTS[1]
	var dir := (b - a).normalized()
	return Transform3D(Basis.looking_at(dir, Vector3.UP), a + dir * 30.0 + Vector3(0, 0.6, 0))


func _ready() -> void:
	_build_visuals()


func _mat(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _build_visuals() -> void:
	var n := POINTS.size()
	var font: Font = load("res://assets/fonts/RussoOne-Regular.ttf")
	for i in n:
		var prev: Vector3 = POINTS[posmod(i - 1, n)]
		var p: Vector3 = POINTS[i]
		var next: Vector3 = POINTS[(i + 1) % n]
		var dir_in := (p - prev).normalized()
		var dir_out := (next - p).normalized()
		var left := dir_in.cross(dir_out).y > 0.0
		# Svitici sipky za krizovatkou (bez kolize, da se jimi projet), ukazuji smer zatacky
		var board := Node3D.new()
		add_child(board)
		board.position = p + dir_in * 11.5 + Vector3(0, 0.15, 0)
		board.basis = Basis.looking_at(dir_in, Vector3.UP)   # celem k prijizdejicimu autu (-Z miri od auta)
		var label := Label3D.new()
		label.font = font
		label.text = ("‹ ‹ ‹ ‹ ‹ ‹" if left else "› › › › › ›")
		label.font_size = 220
		label.pixel_size = 0.009
		label.modulate = Color(2.2, 1.6, 0.1, 0.9)
		label.outline_modulate = Color(0.4, 0.2, 0.0, 0.6)
		label.outline_size = 20
		label.shaded = false
		label.double_sided = false
		label.position = Vector3(0, 2.0, 0)
		board.add_child(label)
		# Svitici sloupek prujezdu (zhasne, kdyz neni na rade)
		var marker := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.25
		cyl.bottom_radius = 0.25
		cyl.height = 5.0
		marker.mesh = cyl
		marker.material_override = _mat(Color(0.2, 1.0, 0.4), 4.0)
		marker.position = p + (dir_out - dir_in).normalized() * 12.5 + Vector3(0, 2.5, 0)
		add_child(marker)
		_markers.append(marker)

	# Startovni / cilova brana
	var st := start_transform()
	var gate := Node3D.new()
	add_child(gate)
	gate.transform = Transform3D(st.basis, st.origin - Vector3(0, 0.6, 0))
	for side in [-1.0, 1.0]:
		var pole := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.5, 7.0, 0.5)
		pole.mesh = pb
		pole.material_override = _mat(Color(0.05, 0.05, 0.06), 0.0)
		pole.position = Vector3(side * 9.2, 3.5, 0)
		gate.add_child(pole)
	var beam := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(18.9, 1.4, 0.5)
	beam.mesh = bb
	beam.material_override = _mat(Color(0.05, 0.05, 0.06), 0.0)
	beam.position = Vector3(0, 6.6, 0)
	gate.add_child(beam)
	for face in [1.0, -1.0]:
		var txt := Label3D.new()
		txt.font = font
		txt.text = "START  ·  CÍL"
		txt.font_size = 180
		txt.pixel_size = 0.006
		txt.modulate = Color(0.3, 2.2, 2.6)
		txt.shaded = false
		txt.position = Vector3(0, 6.6, 0.27 * face)
		txt.rotation.y = 0.0 if face > 0 else PI
		gate.add_child(txt)
	# Sachovnicova cara na zemi
	for i in 16:
		for j in 2:
			if (i + j) % 2 == 0:
				var q := MeshInstance3D.new()
				var qb := BoxMesh.new()
				qb.size = Vector3(1.0, 0.02, 1.0)
				q.mesh = qb
				q.material_override = _mat(Color(0.9, 0.9, 0.9), 0.2)
				q.position = Vector3(-7.5 + i, 0.012, -0.5 + j)
				gate.add_child(q)


func _physics_process(delta: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	if running:
		lap_time += delta
	var n := POINTS.size()
	var p := car.global_position
	# Start / cil: prujezd carou ve smeru jizdy
	var st := start_transform()
	var local := st.affine_inverse() * p
	if absf(local.x) < 9.0 and absf(local.z) < 3.0 and car.linear_velocity.dot(-st.basis.z) > 2.0:
		if not running:
			running = true
			lap_time = 0.0
			next_cp = 1
		elif next_cp == 0:
			last_time = lap_time
			if best_time <= 0.0 or lap_time < best_time:
				best_time = lap_time
			lap_count += 1
			lap_finished.emit(last_time, best_time)
			lap_time = 0.0
			next_cp = 1
	# Prujezdy krizovatkami v poradi
	if running:
		var cp: Vector3 = POINTS[next_cp]
		if Vector2(p.x - cp.x, p.z - cp.z).length() < GATE_RADIUS:
			next_cp = (next_cp + 1) % n
			checkpoint_passed.emit(next_cp, n)
	for i in _markers.size():
		_markers[i].visible = not running or i == next_cp or (next_cp == 0 and i == 0)


func reset() -> void:
	running = false
	lap_time = 0.0
	next_cp = 0
