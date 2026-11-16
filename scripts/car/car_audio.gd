class_name CarAudio
extends Node
## Zvuky auta: motor (smycky v ruznych otackach, zvlast pod plynem a bez plynu, plynule
## se prolinaji), hvizd turba, kvileni pneumatik, nitro, vitr, narazy, preraeni a odfuk turba.
## Vsechny zvuky jsou synteticke (tools/generuj_zvuky.py + tools/motor_synth.py).
## Funguje s Car i GevpCar (cte jen rpm, plyn, rychlost, smyk, nitro).

const DIR := "res://assets/sounds/"
## typ motoru -> otacky, pro ktere existuji smycky (pod plynem / bez plynu); musi sedet s tools/motor_synth.py
const ENGINES := {
	"r4": {"plyn": [1000, 2200, 3600, 5000, 6600], "volno": [900, 3200, 6000], "turbo": true},
	"r4s": {"plyn": [1100, 2400, 3900, 5500, 7100], "volno": [1000, 3500, 6500], "turbo": true},
	"v8": {"plyn": [800, 1900, 3100, 4500, 6000], "volno": [750, 2800, 5500], "turbo": false},
}
const ENGINE_GAIN := 0.8

var car: Node
var _on: Array[AudioStreamPlayer] = []     # smycky pod plynem
var _off: Array[AudioStreamPlayer] = []    # smycky bez plynu
var _on_rpm: Array = []
var _off_rpm: Array = []
var _whistle: AudioStreamPlayer
var _boost := 0.0
var _skid: AudioStreamPlayer
var _nitro: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _scrape: AudioStreamPlayer
var _one_shots: Array[AudioStreamPlayer] = []
var _load := 0.0
var _last_gear := 1
var _was_throttle := 0.0
var _scrape_time := 0.0
var _turbo := true


func _ready() -> void:
	car = get_parent()
	var kind: String = car.t.zvuk_motoru if car.get("t") else "r4"
	if not ENGINES.has(kind):
		kind = "r4"
	var e: Dictionary = ENGINES[kind]
	_turbo = e.turbo
	_on_rpm = e.plyn
	_off_rpm = e.volno
	for r in _on_rpm:
		_on.append(_loop("motor_%s_plyn_%d.wav" % [kind, r], -80.0))
	for r in _off_rpm:
		_off.append(_loop("motor_%s_volno_%d.wav" % [kind, r], -80.0))
	if _turbo:
		_whistle = _loop("turbo_hvizd.wav", -80.0)
	_skid = _loop("pneumatiky.wav", -80.0)
	_nitro = _loop("nitro.wav", -80.0)
	_wind = _loop("vitr.wav", -80.0)
	_scrape = _loop("skrabani.wav", -80.0)
	for i in 4:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_one_shots.append(p)
	if car.has_signal("impact"):
		car.impact.connect(_on_impact)
	if car.has_signal("exploded"):
		car.exploded.connect(func(_c): _play("naraz_3.wav", 4.0, 0.6))


func _stream(file: String, looped: bool) -> AudioStream:
	var s := load(DIR + file) as AudioStreamWAV
	if s and looped:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	return s


func _loop(file: String, volume_db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _stream(file, true)
	p.volume_db = volume_db
	add_child(p)
	p.play()
	return p


func _play(file: String, volume_db: float, pitch: float) -> void:
	for p in _one_shots:
		if not p.playing:
			p.stream = _stream(file, false)
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return


## Prolnuti dvou sousednich smycek podle otacek; kazda se preladi na aktualni otacky.
func _mix_layers(players: Array[AudioStreamPlayer], refs: Array, rpm: float, gain: float) -> void:
	var n := players.size()
	var seg := 0
	while seg < n - 2 and rpm > float(refs[seg + 1]):
		seg += 1
	var f := clampf((rpm - float(refs[seg])) / (float(refs[seg + 1]) - float(refs[seg])), 0.0, 1.0)
	for i in n:
		var p := players[i]
		var g := 0.0
		if i == seg:
			g = cos(f * PI * 0.5)
		elif i == seg + 1:
			g = sin(f * PI * 0.5)
		if g * gain < 0.002:
			p.stream_paused = true
			continue
		p.stream_paused = false
		p.pitch_scale = clampf(rpm / float(refs[i]), 0.5, 1.8)
		p.volume_db = _db(g * gain)


static func _db(linear: float) -> float:
	return linear_to_db(maxf(linear, 0.0001))


func _on_impact(_c: Node, dv: float, _pos: Vector3) -> void:
	if dv > 3.5:
		_play(["naraz_1.wav", "naraz_2.wav", "naraz_3.wav"][randi() % 3], _db(clampf(dv / 14.0, 0.25, 1.4)), randf_range(0.85, 1.15))
	else:
		_scrape_time = 0.25      # slaby naraz = skrabani o zed


func _process(delta: float) -> void:
	if car == null or not is_instance_valid(car) or car.get("t") == null:
		return
	var rpm: float = car.rpm
	var redline: float = car.t.max_otacky
	var throttle: float = car.in_throttle
	var speed: float = car.speed_kmh
	var dead: bool = car.destroyed

	# --- Motor: pod plynem hlasity a ostry, bez plynu tlumeny a bublavy ---
	_load = lerpf(_load, throttle, 1.0 - exp(-14.0 * delta))
	var x := clampf((rpm - 900.0) / (redline - 900.0), 0.0, 1.0)
	var master := 0.0 if dead else ENGINE_GAIN
	_mix_layers(_on, _on_rpm, rpm, master * sqrt(_load) * (0.55 + 0.45 * x))
	_mix_layers(_off, _off_rpm, rpm, master * sqrt(1.0 - _load) * (0.42 + 0.25 * x))
	if _whistle:
		# Turbo se roztaci s plynem a otackami, po ubrani plynu dobiha
		var target := throttle * smoothstep(0.25, 0.7, x)
		_boost = lerpf(_boost, target, 1.0 - exp(-(2.5 if target > _boost else 5.0) * delta))
		_whistle.volume_db = _db(0.0 if dead else _boost * 0.11)
		_whistle.pitch_scale = 0.55 + 0.6 * _boost + 0.15 * x

	# --- Preraeni a odfuk turba ---
	var gear: int = car.gear
	if gear != _last_gear:
		if gear > 0 and _last_gear > 0:
			_play("razeni.wav", -8.0, randf_range(0.9, 1.1))
		_last_gear = gear
	if _turbo and _was_throttle > 0.7 and throttle < 0.2 and x > 0.55 and not dead:
		_play("turbo_odfuk.wav", -7.0, randf_range(0.9, 1.1))
	_was_throttle = lerpf(_was_throttle, throttle, 1.0 - exp(-8.0 * delta))

	# --- Pneumatiky: kvileni podle uhlu smyku (zpetna vazba, ze auto jede na hrane) ---
	var slip: float = car.drift_angle
	var skid := 0.0
	if speed > 25.0 and car.grounded_wheels >= 2:
		skid = smoothstep(5.0, 16.0, slip)
		if car.in_handbrake:
			skid = maxf(skid, 0.7)
		if car.get("wheelspin") and speed < 70.0:
			skid = maxf(skid, 0.5)
	_skid.volume_db = lerpf(_skid.volume_db, _db(skid * 0.5), 1.0 - exp(-14.0 * delta))
	_skid.pitch_scale = 0.85 + 0.25 * clampf(speed / 150.0, 0.0, 1.0)

	# --- Nitro, vitr, skrabani ---
	var nitro_on: bool = car.nitro_active
	_nitro.volume_db = lerpf(_nitro.volume_db, _db(0.6 if nitro_on else 0.0), 1.0 - exp(-10.0 * delta))
	_wind.volume_db = _db(clampf((speed - 60.0) / 200.0, 0.0, 1.0) * 0.45)
	_wind.pitch_scale = 0.8 + clampf(speed / 250.0, 0.0, 1.0) * 0.6
	_scrape_time = maxf(0.0, _scrape_time - delta)
	if car.get("scraping"):
		_scrape_time = 0.1
	_scrape.volume_db = lerpf(_scrape.volume_db, _db(0.5 if _scrape_time > 0.0 and speed > 15.0 else 0.0), 1.0 - exp(-20.0 * delta))
