extends Node
## Spolecny stav hry pro vyvoj: zvolena varianta rizeni a denni/nocni osvetleni.

signal profile_changed(profile: String)
signal daylight_changed(day: bool)

## Varianty rizeni (F7). "gevp" = prevzate rizeni Godot Easy Vehicle Physics.
const PROFILES := ["arkada", "sport", "drift", "gevp"]
const PROFILE_NAMES := {
	"arkada": "ARKÁDA (ostré zatáčení)",
	"sport": "SPORT (realističtější)",
	"drift": "DRIFT (snadný smyk)",
	"gevp": "EASY VEHICLE PHYSICS (převzaté)",
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
