class_name CarTuning
extends RefCounted
## Nacita hodnoty jizdy z tuning/auta.cfg.
## Kdyz nejaka hodnota v souboru chybi, pouzije se vychozi hodnota nize.

const PATH := "res://tuning/auta.cfg"

var id := ""
var nazev := "Auto"
var model := "octavia"
var barva := Color(0.8, 0.8, 0.8)
var hmotnost := 1400.0
var vykon_kw := 150.0
var max_rychlost := 230.0
var pohon := "zadni"
var rychlost_couvani := 40.0
var pocet_rychlosti := 6
var max_otacky := 7000.0
var volnobezne_otacky := 900.0
var sila_brzd := 15000.0
var sila_rucni_brzdy := 5000.0
var max_natoceni_kol := 34.0
var natoceni_ve_vysoke_rychlosti := 0.32
var rychlost_volantu := 3.2
var pomoc_zataceni := 1.0
var mokra_silnice := 0.78
var prilnavost_predni := 1.3
var prilnavost_zadni := 1.22
var uhel_max_prilnavosti := 7.0
var prilnavost_ve_smyku := 0.68
var prilnavost_rucni_brzda := 0.32
var pomoc_driftu := 1.0
var max_uhel_driftu := 55.0
var propad_podvozku := 0.12
var tlumeni := 0.38
var zdvih_pruziny := 0.3
var pritlak := 1.5
var vyska_teziste := 0.42
var nitro_vykon := 1.5
var nitro_spotreba := 0.28
var nitro_dobijeni := 0.025
var nitro_za_drift := 0.12
var odolnost := 1.0
var prah_poskozeni := 7.0


static func load_car(car_id: String) -> CarTuning:
	var t := CarTuning.new()
	t.id = car_id
	var cfg := ConfigFile.new()
	var err := cfg.load(PATH)
	if err != OK:
		push_error("Nepodarilo se nacist %s (chyba %d) - pouzivam vychozi hodnoty." % [PATH, err])
		return t
	t._read_section(cfg, "vychozi")
	if cfg.has_section(car_id):
		t._read_section(cfg, car_id)
	else:
		push_warning("Auto '%s' v %s neexistuje." % [car_id, PATH])
	return t


## Seznam aut (sekci) v souboru, ktera maji 3D model.
static func list_cars() -> PackedStringArray:
	var cfg := ConfigFile.new()
	var result := PackedStringArray()
	if cfg.load(PATH) == OK:
		for s in cfg.get_sections():
			if s != "vychozi" and CarModel.has_model(cfg.get_value(s, "model", s)):
				result.append(s)
	return result


func _read_section(cfg: ConfigFile, section: String) -> void:
	for key in cfg.get_section_keys(section):
		if not key in self:
			push_warning("Neznama hodnota '%s' v sekci [%s] souboru auta.cfg" % [key, section])
			continue
		var value = cfg.get_value(section, key)
		var current = get(key)
		# Prevod cisel, at nevadi "200" misto "200.0"
		if typeof(current) == TYPE_FLOAT and (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT):
			set(key, float(value))
		elif typeof(current) == TYPE_INT and typeof(value) == TYPE_FLOAT:
			set(key, int(value))
		elif typeof(current) == typeof(value):
			set(key, value)
		else:
			push_warning("Spatny typ hodnoty '%s' v sekci [%s]" % [key, section])
