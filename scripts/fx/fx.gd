class_name FX
extends RefCounted
## Tovarna na efekty: kour, ohen, jiskry, vybuch.
## Vse se generuje v kodu, nepotrebuje zadne textury ze souboru.

static var _soft_tex: Texture2D
static var _materials := {}


## Mekke kulate "kolecko" pouzivane jako textura castic.
static func soft_texture() -> Texture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.55))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 64
		t.height = 64
		_soft_tex = t
	return _soft_tex


static func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p in points:
		c.add_point(p)
	var ct := CurveTexture.new()
	ct.curve = c
	return ct


static func _ramp(colors: Array, offsets: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array(offsets)
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt


static func _billboard_material(kind: String) -> StandardMaterial3D:
	if _materials.has(kind):
		return _materials[kind]
	var m := StandardMaterial3D.new()
	m.albedo_texture = soft_texture()
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	match kind:
		"smoke":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
			m.roughness = 1.0
		"fire":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.albedo_color = Color(1.6, 0.9, 0.38)
		"spark":
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			m.albedo_color = Color(6.0, 3.5, 1.2)
			m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
	_materials[kind] = m
	return m


static func _quad(size: Vector2, kind: String) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = size
	q.material = _billboard_material(kind)
	return q


static func _auto_free(node: Node, time: float) -> void:
	node.get_tree().create_timer(time, false).timeout.connect(node.queue_free)


# ---------------------------------------------------------------------
#  Trvale efekty (pripojuji se k autu)
# ---------------------------------------------------------------------

## Kour z poskozeneho motoru. heavy = husty cerny kour.
static func make_smoke(heavy := false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 60 if heavy else 32
	p.lifetime = 2.6 if heavy else 2.0
	p.visibility_aabb = AABB(Vector3(-8, -2, -8), Vector3(16, 14, 16))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 25.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 2.5
	pm.gravity = Vector3(0, 1.2, 0)
	pm.damping_min = 0.5
	pm.damping_max = 1.0
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.scale_min = 0.8
	pm.scale_max = 1.4
	pm.scale_curve = _curve([Vector2(0, 0.3), Vector2(1, 1.0)])
	pm.angle_min = 0.0
	pm.angle_max = 360.0
	if heavy:
		pm.color_ramp = _ramp([Color(0.05, 0.05, 0.05, 0.0), Color(0.06, 0.06, 0.06, 0.85), Color(0.1, 0.1, 0.1, 0.0)], [0.0, 0.15, 1.0])
	else:
		pm.color_ramp = _ramp([Color(0.6, 0.6, 0.62, 0.0), Color(0.55, 0.55, 0.58, 0.45), Color(0.4, 0.4, 0.42, 0.0)], [0.0, 0.15, 1.0])
	p.process_material = pm
	p.draw_pass_1 = _quad(Vector2(1.6, 1.6) * (1.4 if heavy else 1.0), "smoke")
	return p


## Ohen z motoru.
static func make_fire() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 28
	p.lifetime = 0.7
	p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 8, 8))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 15.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, 2.0, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.5, 0.1, 0.5)
	pm.scale_min = 0.6
	pm.scale_max = 1.1
	pm.scale_curve = _curve([Vector2(0, 1.0), Vector2(1, 0.2)])
	pm.angle_max = 360.0
	pm.color_ramp = _ramp([Color(1, 0.9, 0.5, 0.0), Color(1, 0.6, 0.2, 1.0), Color(0.9, 0.2, 0.05, 0.6), Color(0.2, 0.05, 0.0, 0.0)], [0.0, 0.1, 0.5, 1.0])
	p.process_material = pm
	p.draw_pass_1 = _quad(Vector2(1.0, 1.0), "fire")
	return p


# ---------------------------------------------------------------------
#  Jednorazove efekty
# ---------------------------------------------------------------------

## Jiskry pri narazu kovu.
static func spawn_sparks(parent: Node, pos: Vector3, normal: Vector3, amount := 40) -> void:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = 0.6
	p.one_shot = true
	p.explosiveness = 0.95
	p.transform_align = GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY
	var pm := ParticleProcessMaterial.new()
	pm.direction = normal.normalized() if normal.length() > 0.01 else Vector3.UP
	pm.spread = 70.0
	pm.initial_velocity_min = 4.0
	pm.initial_velocity_max = 12.0
	pm.gravity = Vector3(0, -12, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.color_ramp = _ramp([Color(1, 1, 0.8, 1), Color(1, 0.5, 0.1, 1), Color(0.8, 0.2, 0.0, 0)], [0.0, 0.5, 1.0])
	p.process_material = pm
	p.draw_pass_1 = _quad(Vector2(0.04, 0.35), "spark")
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	_auto_free(p, 1.5)


## Velky vybuch: ohnive koule, kour, jiskry, zablesk svetla a tlakova vlna.
static func spawn_explosion(parent: Node, pos: Vector3, radius := 9.0, force := 9000.0, exclude: Array[RID] = []) -> void:
	var root := Node3D.new()
	root.name = "Vybuch"
	parent.add_child(root)
	root.global_position = pos

	# Ohniva koule
	var fire := GPUParticles3D.new()
	fire.amount = 60
	fire.lifetime = 1.1
	fire.one_shot = true
	fire.explosiveness = 0.9
	var fpm := ParticleProcessMaterial.new()
	fpm.direction = Vector3.UP
	fpm.spread = 180.0
	fpm.initial_velocity_min = 3.0
	fpm.initial_velocity_max = 9.0
	fpm.gravity = Vector3(0, 3.0, 0)
	fpm.damping_min = 3.0
	fpm.damping_max = 5.0
	fpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fpm.emission_sphere_radius = 1.0
	fpm.scale_min = 1.5
	fpm.scale_max = 3.0
	fpm.scale_curve = _curve([Vector2(0, 0.4), Vector2(0.3, 1.0), Vector2(1, 0.6)])
	fpm.angle_max = 360.0
	fpm.color_ramp = _ramp([Color(1, 1, 0.8, 1), Color(1, 0.55, 0.15, 1), Color(0.7, 0.15, 0.02, 0.7), Color(0.1, 0.05, 0.02, 0)], [0.0, 0.2, 0.6, 1.0])
	fire.process_material = fpm
	fire.draw_pass_1 = _quad(Vector2(2.2, 2.2), "fire")
	root.add_child(fire)
	fire.emitting = true

	# Cerny kour
	var smoke := GPUParticles3D.new()
	smoke.amount = 50
	smoke.lifetime = 4.0
	smoke.one_shot = true
	smoke.explosiveness = 0.7
	smoke.visibility_aabb = AABB(Vector3(-15, -2, -15), Vector3(30, 30, 30))
	var spm := ParticleProcessMaterial.new()
	spm.direction = Vector3.UP
	spm.spread = 60.0
	spm.initial_velocity_min = 2.0
	spm.initial_velocity_max = 6.0
	spm.gravity = Vector3(0, 1.5, 0)
	spm.damping_min = 1.0
	spm.damping_max = 2.0
	spm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	spm.emission_sphere_radius = 1.5
	spm.scale_min = 2.0
	spm.scale_max = 3.5
	spm.scale_curve = _curve([Vector2(0, 0.5), Vector2(1, 1.6)])
	spm.angle_max = 360.0
	spm.color_ramp = _ramp([Color(0.1, 0.08, 0.07, 0), Color(0.08, 0.07, 0.07, 0.9), Color(0.15, 0.15, 0.15, 0)], [0.0, 0.1, 1.0])
	smoke.process_material = spm
	smoke.draw_pass_1 = _quad(Vector2(2.5, 2.5), "smoke")
	root.add_child(smoke)
	smoke.emitting = true

	spawn_sparks(root, pos, Vector3.UP, 120)

	# Zablesk svetla
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 12.0
	light.omni_range = 22.0
	light.light_volumetric_fog_energy = 3.0
	root.add_child(light)
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)

	# Otres kamery
	for cam in root.get_tree().get_nodes_in_group("camera_shake"):
		var d: float = cam.global_position.distance_to(pos)
		cam.call("add_shake", clampf(1.2 - d / 60.0, 0.0, 1.0))

	# Tlakova vlna odhodi okolni objekty
	push_bodies(root, pos, radius, force, exclude)

	_auto_free(root, 6.0)


## Odstrci vsechna fyzicka telesa v okruhu.
static func push_bodies(node: Node3D, pos: Vector3, radius: float, force: float, exclude: Array[RID] = []) -> void:
	var space := node.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = radius
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(), pos)
	q.exclude = exclude
	for hit in space.intersect_shape(q, 32):
		var body := hit.collider as RigidBody3D
		if body == null:
			continue
		var dir: Vector3 = body.global_position - pos
		var dist := maxf(dir.length(), 0.5)
		dir.y = maxf(dir.y, 0.0)
		var strength := force * (1.0 - clampf(dist / radius, 0.0, 1.0))
		var impulse := (dir.normalized() + Vector3.UP * 0.8).normalized() * strength * minf(body.mass, 400.0) / 400.0
		body.apply_impulse(impulse, Vector3(randf_range(-0.3, 0.3), 0.2, randf_range(-0.3, 0.3)))
