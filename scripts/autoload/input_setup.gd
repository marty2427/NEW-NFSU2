extends Node
## Registruje ovladani (klavesnice + gamepad) pri startu hry.
## Pozdeji (faze 7) sem pribude ukladani vlastniho nastaveni klaves.

const DEADZONE := 0.15


func _ready() -> void:
	_action("plyn", [KEY_W, KEY_UP], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_action("brzda", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_action("vlevo", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("vpravo", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_action("rucni_brzda", [KEY_SPACE], [JOY_BUTTON_X, JOY_BUTTON_RIGHT_SHOULDER], [])
	_action("nitro", [KEY_SHIFT], [JOY_BUTTON_A], [])
	_action("kamera", [KEY_C], [JOY_BUTTON_Y], [])
	_action("pohled_vzad", [KEY_Q], [JOY_BUTTON_LEFT_SHOULDER], [])
	_action("reset_auta", [KEY_R], [JOY_BUTTON_BACK], [])
	_action("auto_1", [KEY_1], [], [])
	_action("auto_2", [KEY_2], [], [])
	_action("auto_3", [KEY_3], [], [])
	_action("grafika", [KEY_F5], [], [])
	_action("nacist_ladeni", [KEY_F6], [], [])
	_action("varianta_rizeni", [KEY_F7], [JOY_BUTTON_RIGHT_STICK], [])
	_action("den_noc", [KEY_F8], [], [])
	_action("fps", [KEY_F3], [], [])
	_action("cela_obrazovka", [KEY_F11], [], [])
	_action("test_poskozeni", [KEY_K], [], [])
	_action("konec", [KEY_ESCAPE], [JOY_BUTTON_START], [])


func _action(name: String, keys: Array, buttons: Array, axes: Array) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name, DEADZONE)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(name, ev)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(name, jb)
	for a in axes:
		var ja := InputEventJoypadMotion.new()
		ja.axis = a[0]
		ja.axis_value = a[1]
		InputMap.action_add_event(name, ja)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cela_obrazovka"):
		var w := get_window()
		if w.mode == Window.MODE_FULLSCREEN or w.mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
			w.mode = Window.MODE_WINDOWED
		else:
			w.mode = Window.MODE_FULLSCREEN
	elif event.is_action_pressed("konec"):
		get_tree().quit()
