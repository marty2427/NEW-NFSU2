class_name LapRecords
extends RefCounted
## Ukladani casu kol: rekordy (nejlepsi cas pro okruh + auto + rizeni) a zaznam vsech kol.
## Soubory lezi ve slozce hry: zaznamy/rekordy.json a zaznamy/casy_kol.csv (do gitu se nenahravaji,
## aktualizace je nesmaze). Kdyby slozka nesla zapsat, pouzije se uzivatelska slozka Godotu.

static var enabled := true
static var _data := {}
static var _loaded := false


static func _dir() -> String:
	for d in ["res://zaznamy", "user://zaznamy"]:
		if DirAccess.dir_exists_absolute(d) or DirAccess.make_dir_recursive_absolute(d) == OK:
			# Godot si slozky s .gdignore nevsima (jinak by .csv bral jako preklady)
			if not FileAccess.file_exists(d + "/.gdignore"):
				var g := FileAccess.open(d + "/.gdignore", FileAccess.WRITE)
				if g == null:
					continue
			return d
	return "user://"


static func _key(circuit: String, car_id: String, profile: String) -> String:
	return "%s|%s|%s" % [circuit, car_id, profile]


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var path := _dir() + "/rekordy.json"
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			_data = parsed


## Rekord (sekundy), 0 = zatim zadny.
static func best(circuit: String, car_id: String, profile: String) -> float:
	_load()
	var rec: Variant = _data.get(_key(circuit, car_id, profile))
	return float(rec.cas) if rec is Dictionary else 0.0


## Ulozi dokoncene kolo. Vrati true, kdyz je to novy rekord.
static func add_lap(circuit: String, car_id: String, profile: String, time: float) -> bool:
	_load()
	var old := best(circuit, car_id, profile)
	var is_record := old <= 0.0 or time < old
	if not enabled:
		return is_record
	var now := Time.get_datetime_string_from_system(false, true)
	if is_record:
		_data[_key(circuit, car_id, profile)] = {"okruh": circuit, "auto": car_id, "rizeni": profile, "cas": snappedf(time, 0.001), "datum": now}
		var f := FileAccess.open(_dir() + "/rekordy.json", FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(_data, "  ", true))
	var csv_path := _dir() + "/casy_kol.csv"
	var new_file := not FileAccess.file_exists(csv_path)
	var c := FileAccess.open(csv_path, FileAccess.READ_WRITE if not new_file else FileAccess.WRITE)
	if c:
		if new_file:
			c.store_line("datum;okruh;auto;rizeni;cas_s;rekord")
		c.seek_end()
		c.store_line("%s;%s;%s;%s;%.3f;%s" % [now, circuit, car_id, profile, time, "ano" if is_record else ""])
	return is_record
