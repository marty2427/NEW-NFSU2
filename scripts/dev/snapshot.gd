extends Node
## Vyvojovy snimek: -- --snapshot=SOUBOR  (kamera z boku na stojici auto)
var _frames := 0
var _path := ""

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snapshot="):
			_path = arg.substr(11)

func _process(_delta: float) -> void:
	_frames += 1
	var arena := get_parent()
	var cam: Camera3D = arena.camera
	cam.set_physics_process(false)
	var car: Node3D = arena.car
	cam.global_position = car.global_position + Vector3(-6.0, 3.0, -5.0)
	cam.look_at(car.global_position + Vector3(0, 0, -6), Vector3.UP)
	if _frames == 25:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_path)
		get_tree().quit()
