extends Node3D
## Character showcase: the hero posed on a mossy stone block in a grey stone
## alcove, lit like a studio render. Not part of the game build.
## Run with: godot --path . res://showcase/showcase.tscn
## Env: SHOWCASE_OUT=<dir> to save renders, SHOWCASE_MODE=stills|turntable.

const B = preload("res://scripts/build.gd")
const PlayerScript = preload("res://scripts/player.gd")

var hero
var cam: Camera3D
var out_dir := ""


func _ready() -> void:
	out_dir = OS.get_environment("SHOWCASE_OUT")
	build_studio()
	build_hero()
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		if OS.get_environment("SHOWCASE_MODE") == "turntable":
			turntable()
		else:
			stills()


# ------------------------------------------------------------------ studio

func block_tex() -> ImageTexture:
	# Big hand-painted stone blocks with soft, dark mortar lines.
	var W := 256
	var img := Image.create_empty(W, W, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var base := Color(0.5, 0.49, 0.48)
	img.fill(base)
	var rows := 3
	var rh := W / rows
	for r in rows:
		var x := -rng.randi_range(0, 60) if r % 2 == 1 else 0
		while x < W:
			var bw := rng.randi_range(70, 120)
			var shade := rng.randf_range(-0.07, 0.07)
			for y in range(r * rh, (r + 1) * rh):
				for xx in range(maxi(x, 0), mini(x + bw, W)):
					var c := base.lightened(shade) if shade > 0.0 else base.darkened(-shade)
					# light top edge, darker bottom edge on each block
					var ty := float(y - r * rh) / rh
					c = c.lightened(maxf(0.0, 0.1 - ty) * 0.8).darkened(maxf(0.0, ty - 0.85) * 0.8)
					var e := mini(mini(xx - x, x + bw - xx), mini(y - r * rh, (r + 1) * rh - y))
					if e < 3:
						c = c.darkened(0.25 - e * 0.05)
					img.set_pixel(xx, y, c)
			x += bw
	for i in 900:
		var px := rng.randi_range(0, W - 1)
		var py := rng.randi_range(0, W - 1)
		var c2 := img.get_pixel(px, py)
		for k in rng.randi_range(2, 6):
			var q := posmod(px + k, W)
			img.set_pixel(q, py, c2.lightened(0.04) if i % 2 == 0 else c2.darkened(0.04))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func moss_tex() -> ImageTexture:
	var W := 128
	var img := Image.create_empty(W, W, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var stone := Color(0.62, 0.6, 0.55)
	var moss := Color(0.45, 0.5, 0.33)
	for y in W:
		for x in W:
			var n := sin(x * 0.11) * sin(y * 0.13 + 1.0) + sin((x + y) * 0.05) * 0.6 + rng.randf_range(-0.25, 0.25)
			var c := stone.lerp(moss, clampf(n * 0.6 + 0.4, 0.0, 1.0))
			c = c.lightened(rng.randf_range(0.0, 0.05))
			img.set_pixel(x, y, c)
	for i in 160:
		var cx := rng.randi_range(0, W - 1)
		var cy := rng.randi_range(0, W - 1)
		var c := img.get_pixel(cx, cy)
		for k in 6:
			img.set_pixel(posmod(cx + k, W), cy, c.darkened(0.12) if i % 3 == 0 else c.lightened(0.08))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func build_studio() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.42, 0.41, 0.4)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.76, 0.74)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.92
	env.tonemap_white = 4.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.05
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.4, 0.39, 0.38)
	env.fog_depth_begin = 7.0
	env.fog_depth_end = 18.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	# Warm key from the front left, cool rim from behind, soft fill from the right.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, -32, 0)
	key.light_color = Color(1.0, 0.94, 0.86)
	key.light_energy = 1.0
	key.shadow_enabled = true
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	key.directional_shadow_max_distance = 12.0
	key.shadow_blur = 2.2
	key.shadow_opacity = 0.85
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_color = Color(0.9, 0.93, 1.0)
	rim.light_energy = 0.7
	add_child(rim)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, 60, 0)
	fill.light_color = Color(0.82, 0.86, 0.95)
	fill.light_energy = 0.25
	add_child(fill)

	var wall := B.tex_mat(block_tex())
	wall.uv1_scale = Vector3(3.0, 1.0, 1.0)
	# Curved alcove wall behind and a stone floor.
	var cyl := CylinderMesh.new()
	cyl.top_radius = 5.5
	cyl.bottom_radius = 5.5
	cyl.height = 6.0
	cyl.radial_segments = 40
	cyl.cap_top = false
	cyl.cap_bottom = false
	var w := MeshInstance3D.new()
	w.mesh = cyl
	w.material_override = wall
	w.position = Vector3(0, 3.0, 0)
	var flip := wall.duplicate()
	flip.cull_mode = BaseMaterial3D.CULL_FRONT
	w.material_override = flip
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(w)
	var floor_mat := B.mat(Color(0.44, 0.43, 0.42))
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(12, 12)
	fl.mesh = pm
	fl.material_override = floor_mat
	add_child(fl)

	# Mossy stone block the hero stands on.
	var block := B.tex_mat(moss_tex())
	var bm := B.mesh(self, B.box_mesh(Vector3(1.25, 0.42, 0.95)), Vector3(0, 0.21, 0), block, Vector3(0, -18, 0))
	bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	B.mesh(self, B.box_mesh(Vector3(1.29, 0.04, 0.99)), Vector3(0, 0.43, 0), B.paint_mat(Color(0.44, 0.45, 0.37), "stone", 9), Vector3(0, -18, 0))


# ------------------------------------------------------------------ hero

func build_hero() -> void:
	hero = PlayerScript.new()
	hero.position = Vector3(0, 0.45, 0)
	add_child(hero)
	hero.set_physics_process(false)
	hero.set_process(false)
	# The reference has no weapons.
	for n in hero.find_children("Sword", "Node3D", true, false):
		n.visible = false
	for n in hero.find_children("Shield", "Node3D", true, false):
		n.visible = false
	for n in hero.get_children():
		if n is MeshInstance3D:
			n.visible = false     # blob shadow; the studio has real shadows
	pose_nervous()
	hero.attach_gear()


## Nervous stance: knees bent and apart, fists raised near the chest,
## shoulders hunched, head tipped down and turned off to his right.
func pose_nervous() -> void:
	var p: Dictionary = hero.parts
	hero.model.rotation.y = PI - 0.42
	p.pivot.position.y = 0.8
	p.pivot.rotation = Vector3(-0.1, 0, 0)
	p.body.position.y = p.body_y
	p.body.rotation = Vector3(0, 0.08, 0)
	p.leg_l.rotation = Vector3(0.28, 0.25, -0.2)
	p.leg_r.rotation = Vector3(-0.05, -0.2, 0.2)
	p.shin_l.rotation = Vector3(-0.5, 0, 0)
	p.shin_r.rotation = Vector3(-0.32, 0, 0)
	p.arm_l.basis = Basis.from_euler(Vector3(0.62, 0.0, 0.32))
	p.arm_r.basis = Basis.from_euler(Vector3(0.7, 0.0, -0.3))
	p.forearm_l.rotation = Vector3(1.95, 0.0, 0.25)
	p.forearm_r.rotation = Vector3(1.75, 0.0, -0.3)
	p.head.rotation = Vector3(-0.16, -0.32, 0.06)


# ------------------------------------------------------------------ renders

func make_camera() -> void:
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true


func frame(pos: Vector3, look: Vector3, fov: float) -> void:
	cam.fov = fov
	cam.global_position = pos
	cam.look_at(look)


func save(name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))


func head_pos() -> Vector3:
	if hero.skin != null:
		var sk = hero.skin
		var i: int = sk.names.find("head")
		return sk.skeleton.global_transform * (sk.cur_pos[i] as Vector3) + Vector3(0, 0.2, 0)
	return hero.parts.head.global_position + Vector3(0, 0.22, 0)


func stills() -> void:
	make_camera()
	await get_tree().create_timer(0.4).timeout
	var hp := head_pos()
	var top := hp.y + 0.38
	var bottom := 0.15
	var mid := Vector3(0, (top + bottom) * 0.5, 0)
	var d := (top - bottom) * 0.5 / tan(deg_to_rad(15.0))
	frame(mid + Vector3(0.18, 0.12, 1.0).normalized() * d + Vector3(0, 0.25, 0), mid, 30.0)
	await save("hero_full")
	frame(hp + Vector3(0.3, 0.02, 1.35), hp + Vector3(0, -0.06, 0), 30.0)
	await save("hero_face")
	frame(mid + Vector3(-0.75, 0.12, 0.65).normalized() * d + Vector3(0, 0.25, 0), mid, 30.0)
	await save("hero_side")
	frame(mid + Vector3(0.2, 0.12, -1.0).normalized() * d + Vector3(0, 0.25, 0), mid, 30.0)
	await save("hero_back")
	get_tree().quit()


func turntable() -> void:
	make_camera()
	await get_tree().create_timer(0.4).timeout
	var frames := 96
	for i in frames:
		var a := TAU * float(i) / float(frames)
		var d := 3.6
		var top := head_pos().y + 0.2
		var mid := Vector3(0, (top + 0.15) * 0.5, 0)
		d = (top - 0.15) * 0.5 / tan(deg_to_rad(15.0))
		frame(mid + Vector3(sin(a) * d, 0.12 * d + 0.25, cos(a) * d), mid, 30.0)
		await save("turn_%03d" % i)
	get_tree().quit()
