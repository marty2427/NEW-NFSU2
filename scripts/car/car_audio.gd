class_name CarAudio
extends Node
## Zvuky auta: motor (dve vrstvy podle otacek), kvileni pneumatik, nitro, vitr,
## narazy, preraeni a odfuk turba. Vsechny zvuky jsou synteticke (tools/generuj_zvuky.py).
## Funguje s Car i GevpCar (cte jen rpm, plyn, rychlost, smyk, nitro).

const DIR := "res://assets/sounds/"
## typ motoru -> [soubor nizke otacky, jeho referencni otacky, soubor vysoke otacky, referencni otacky]
const ENGINES := {
	"r4": ["motor_r4_nizky.wav", 2500.0, "motor_r4_vysoky.wav", 5500.0],
	"v8": ["motor_v8_nizky.wav", 2000.0, "motor_v8_vysoky.wav", 4500.0],
}

var car: Node
var _low: AudioStreamPlayer
var _high: AudioStreamPlayer
var _skid: AudioStreamPlayer
var _nitro: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _scrape: AudioStreamPlayer
var _one_shots: Array[AudioStreamPlayer] = []
var _refs := [2500.0, 5500.0]
var _load := 0.0
var _last_gear := 1
var _was_throttle := 0.0
var _scrape_time := 0.0
var _turbo := true


func _ready() -> void:
	car = get_parent()
	var kind: String = car.t.zvuk_motoru if car.get("t") else "r4"
	var e: Array = ENGINES.get(kind, ENGINES["r4"])
	_refs = [e[1], e[3]]
	_turbo = kind != "v8"
	_low = _loop(e[0], -80.0)
	_high = _loop(e[2], -80.0)
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

	# --- Motor: pod plynem hlasity a ostry, bez plynu tlumeny ---
	_load = lerpf(_load, throttle, 1.0 - exp(-12.0 * delta))
	var x := clampf((rpm - 900.0) / (redline - 900.0), 0.0, 1.0)
	var mix := smoothstep(0.25, 0.75, x)                     # 0 = nizka vrstva, 1 = vysoka
	var gain := (0.35 + 0.65 * _load) * (0.75 + 0.25 * x)
	if dead:
		gain = 0.0
	_low.pitch_scale = clampf(rpm / _refs[0], 0.35, 3.0)
	_high.pitch_scale = clampf(rpm / _refs[1], 0.35, 2.5)
	_low.volume_db = _db(gain * cos(mix * PI * 0.5) * 0.42)
	_high.volume_db = _db(gain * sin(mix * PI * 0.5) * 0.38)

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
