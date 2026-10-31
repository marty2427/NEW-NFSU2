class_name CarTuning
extends RefCounted
## Nacita hodnoty jizdy z tuning/auta.cfg.
## Kdyz nejaka hodnota v souboru chybi, pouzije se vychozi hodnota nize.

const PATH := "res://tuning/auta.cfg"

var id := ""
var nazev := "Auto"
var barva := Color(0.8, 0.8, 0.8)
var rozmery := Vector3(1.9, 1.2, 4.5)
var hmotnost := 1200.0
var max_rychlost := 200.0
var sila_motoru := 9000.0
var pohon := "zadni"
var rychlost_couvani := 40.0
var sila_brzd := 14000.0
var sila_rucni_brzdy := 5000.0
var max_natoceni_kol := 34.0
var natoceni_ve_vysoke_rychlosti := 0.35
var rychlost_volantu := 3.5
var pomoc_zataceni := 1.0
var prilnavost_predni := 1.6
var prilnavost_zadni := 1.5
var prilnavost_rucni_brzda := 0.3
var prilnavost_v_driftu := 0.55
var uhel_zacatku_driftu := 12.0
var pomoc_driftu := 1.0
var max_uhel_driftu := 55.0
var propad_podvozku := 0.14
var tlumeni := 0.35
var polomer_kola := 0.36
var zdvih_pruziny := 0.32
var pritlak := 2.0
var nitro_sila := 1.6
var nitro_max_rychlost := 1.2
var nitro_spotreba := 0.3
var nitro_dobijeni := 0.03
var nitro_za_drift := 0.12
var odolnost := 1.0
var prah_poskozeni := 3.0


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


## Seznam aut (sekci) v souboru, krome [vychozi].
static func list_cars() -> PackedStringArray:
	var cfg := ConfigFile.new()
	var result := PackedStringArray()
	if cfg.load(PATH) == OK:
		for s in cfg.get_sections():
			if s != "vychozi":
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
		elif typeof(current) == typeof(value):
			set(key, value)
		else:
			push_warning("Spatny typ hodnoty '%s' v sekci [%s]" % [key, section])
