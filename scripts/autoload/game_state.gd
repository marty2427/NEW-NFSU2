extends Node
## Spolecny stav hry pro vyvoj: zvolena varianta rizeni a denni/nocni osvetleni.

signal profile_changed(profile: String)
signal daylight_changed(day: bool)

## Varianty rizeni (F7).
const PROFILES := ["arkada", "sport"]
const PROFILE_NAMES := {
	"arkada": "ARKÁDA (ostré zatáčení)",
	"sport": "SPORT (realističtější)",
}

var profile := "arkada"
var daylight := true


func next_profile() -> String:
	profile = PROFILES[(PROFILES.find(profile) + 1) % PROFILES.size()]
	profile_changed.emit(profile)
	return profile


func profile_name() -> String:
	return PROFILE_NAMES.get(profile, profile)


func toggle_daylight() -> void:
	daylight = not daylight
	daylight_changed.emit(daylight)
