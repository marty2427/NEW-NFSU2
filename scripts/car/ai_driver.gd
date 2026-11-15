class_name AIDriver
extends Node
## Pocitacovy jezdec: jede po zaoblene stope, pred zatackami brzdi podle predpocitaneho
## rychlostniho profilu. Ovlada auto stejne jako hrac (plyn, brzda, volant), takze slouzi
## i k testovani rizeni a pozdeji jako souper.
## keyboard = true: volant jen naplno vlevo/vpravo/nic (jako klavesnice, "tukani").

var car: Node
var keyboard := true
var lat_g := 1.4              # s jakym bocnim pretizenim jezdec pocita v zatackach
var brake_decel := 8.5        # m/s2, s jakym zpomalenim pocita pred zatackou
var top_speed := 80.0         # m/s, strop rychlosti na rovince
var use_nitro := false
var enabled := true

var line: PackedVector3Array      # husta stopa (body po ~2 m)
var speed_limit: PackedFloat32Array
var index := 0                    # nejblizsi bod stopy
var laps := 0
var off_line_max := 0.0           # nejvetsi vzdalenost od stopy (m)
var _pwm := 0.0
var _step := 2.0


func _ready() -> void:
	car = get_parent()


## Pripravi stopu z rohovych bodu (krizovatek): zatacky se zaobli obloukem o polomeru radius.
func set_route(corners: PackedVector3Array, radius := 26.0) -> void:
	line = rounded_path(corners, radius, _step)
	_build_speed_profile()
	snap_to_line()


static func rounded_path(corners: PackedVector3Array, radius: float, step: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var n := corners.size()
	for i in n:
		var prev := corners[posmod(i - 1, n)]
		var p := corners[i]
		var next := corners[(i + 1) % n]
		var d_in := (p - prev).normalized()
		var d_out := (next - p).normalized()
		var angle := d_in.angle_to(d_out)
		var t_len := minf(radius * tan(angle * 0.5), minf((p - prev).length(), (next - p).length()) * 0.45)
		var r := t_len / maxf(tan(angle * 0.5), 0.001)
		# Rovinka od konce predchoziho oblouku k zacatku tohoto
		var prev_prev := corners[posmod(i - 2, n)]
		var prev_angle := (prev - prev_prev).normalized().angle_to(d_in)
		var prev_t := minf(radius * tan(prev_angle * 0.5), minf((prev - prev_prev).length(), (p - prev).length()) * 0.45)
		var a := prev + d_in * prev_t
		var b := p - d_in * t_len
		var seg_len := (b - a).length()
		var count := maxi(int(seg_len / step), 1)
		for k in count:
			out.append(a.lerp(b, float(k) / count))
		# Oblouk
		if angle > 0.02:
			var side := signf(d_in.cross(d_out).y)                      # + = doleva
			var to_center := Vector3.UP.cross(d_in) * side              # kolmo ke smeru, dovnitr zatacky
			var center := b + to_center * r
			var arc_count := maxi(int(r * angle / step), 2)
			for k in arc_count:
				var ang := angle * float(k) / arc_count * side
				out.append(center + (b - center).rotated(Vector3.UP, ang))
	return out


func _build_speed_profile() -> void:
	var n := line.size()
	speed_limit = PackedFloat32Array()
	speed_limit.resize(n)
	for i in n:
		var a := line[posmod(i - 3, n)]
		var b := line[i]
		var c := line[(i + 3) % n]
		var turn := absf((b - a).normalized().signed_angle_to((c - b).normalized(), Vector3.UP))
		var arc := ((b - a).length() + (c - b).length()) * 0.5
		var radius := arc / maxf(turn, 0.0001)
		speed_limit[i] = minf(sqrt(lat_g * 9.8 * radius), top_speed)
	# Zpetny pruchod: aby slo pred zatackou vcas dobrzdit
	for pass_i in 2:
		for k in n:
			var i := n - 1 - k
			var nxt := (i + 1) % n
			var ds := (line[nxt] - line[i]).length()
			speed_limit[i] = minf(speed_limit[i], sqrt(speed_limit[nxt] * speed_limit[nxt] + 2.0 * brake_decel * ds))


func snap_to_line() -> void:
	var best := 1e9
	for i in line.size():
		var d := line[i].distance_squared_to(car.global_position)
		if d < best:
			best = d
			index = i


func _physics_process(delta: float) -> void:
	if not enabled or car == null or line.size() < 8:
		return
	var n := line.size()
	var p: Vector3 = car.global_position
	p.y = 0.0
	# Nejblizsi bod stopy (hleda se jen kousek dopredu, at jezdec nepreskoci na jiny usek)
	var best := 1e9
	var best_i := index
	for k in range(-3, 16):
		var i := posmod(index + k, n)
		var d := Vector2(line[i].x - p.x, line[i].z - p.z).length_squared()
		if d < best:
			best = d
			best_i = i
	if best_i < index and index - best_i > n / 2:
		laps += 1
	index = best_i
	off_line_max = maxf(off_line_max, sqrt(best))

	var v: float = car.linear_velocity.length()
	var fwd: Vector3 = -car.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()

	# --- Volant: mirit na bod stopy pred autem ---
	var look := 6.0 + v * 0.3
	var target := line[posmod(index + int(look / _step), n)]
	var to_t := target - p
	to_t.y = 0.0
	var err := fwd.signed_angle_to(to_t.normalized(), Vector3.UP)   # + = cil je vlevo
	var steer := 0.0
	if keyboard:
		# Clovek na klavesnici: cim vetsi odchylka, tim dele drzi klavesu
		_pwm = fposmod(_pwm + delta / 0.14, 1.0)
		var duty := clampf(absf(err) / deg_to_rad(8.0), 0.0, 1.0)
		if duty > 0.12 and _pwm < duty:
			steer = -signf(err)
	else:
		steer = clampf(-err / deg_to_rad(12.0), -1.0, 1.0)

	# --- Rychlost podle profilu (divat se kousek dopredu kvuli reakcni dobe) ---
	var ahead := posmod(index + int(v * 0.12 / _step) + 1, n)
	var v_allowed := minf(speed_limit[index], speed_limit[ahead])
	var throttle := 0.0
	var brake := 0.0
	if v > v_allowed + 1.5:
		brake = 1.0
	elif v < v_allowed - 0.3:
		throttle = 1.0

	car.in_steer = steer
	car.in_throttle = throttle
	car.in_brake = brake
	car.in_handbrake = false
	car.in_nitro = use_nitro and throttle > 0.5 and absf(err) < 0.06 and speed_limit[posmod(index + 40, n)] > v + 8.0
