extends Node3D
## Wrenmoor prototype. Builds the whole world from code: a walled town,
## the Hollow Field beyond its gate, and the cave the dead crawl out of.

const B = preload("res://scripts/build.gd")
const PlayerScript = preload("res://scripts/player.gd")
const ZombieScript = preload("res://scripts/zombie.gd")
const NpcScript = preload("res://scripts/npc.gd")
const PickupScript = preload("res://scripts/pickup.gd")
const CameraRigScript = preload("res://scripts/camera_rig.gd")
const HudScript = preload("res://scripts/hud.gd")
const TouchScript = preload("res://scripts/touch_controls.gd")
const SfxScript = preload("res://scripts/sfx.gd")

const HOURS_PER_SEC := 1.0 / 20.0      # one in-game hour every 20 seconds
const SPAWN_POINT := Vector3(10, 0, 114)
const TOWN_SPAWN := Vector3(0, 0, 10)

# Sky keyframes: [hour, sky colour, light energy, ambient energy]
const SKY_KEYS := [
	[0.0, Color(0.04, 0.05, 0.12), 0.22, 0.42],
	[5.0, Color(0.05, 0.06, 0.14), 0.22, 0.42],
	[6.5, Color(0.85, 0.55, 0.42), 0.7, 0.55],
	[8.0, Color(0.55, 0.72, 0.95), 1.1, 0.7],
	[17.0, Color(0.55, 0.72, 0.95), 1.1, 0.7],
	[18.5, Color(0.92, 0.48, 0.32), 0.75, 0.55],
	[19.5, Color(0.24, 0.15, 0.3), 0.4, 0.45],
	[21.0, Color(0.04, 0.05, 0.12), 0.22, 0.42],
	[24.0, Color(0.04, 0.05, 0.12), 0.22, 0.42],
]

var ward_z := 28.0
var world: Node3D
var player
var cam_rig
var hud
var touch
var sfx
var env: Environment
var sun: DirectionalLight3D
var lanterns: Array = []      # [OmniLight3D, base energy, flicker]
var window_mats: Array = []
var lock_marker: Node3D
var time_of_day := 18.0
var day := 1
var spawn_timer := 2.0
var shards := 0
var kills := 0
var dialog_active := false
var dialog_lines: Array = []
var dialog_index := 0
var dialog_frame := 0
var dialog_cooldown := 0.0
var game_over_active := false
var game_over_frame := 0
var hitstop_time := 0.0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 1987
	setup_input()
	sfx = SfxScript.new()
	add_child(sfx)
	world = Node3D.new()
	add_child(world)
	build_environment()
	build_ground()
	build_town()
	build_field()
	build_cave()
	spawn_npcs()

	player = PlayerScript.new()
	player.main = self
	player.position = TOWN_SPAWN + Vector3(0, 0, 4)
	world.add_child(player)

	cam_rig = CameraRigScript.new()
	cam_rig.main = self
	cam_rig.player = player
	cam_rig.yaw = 0.0   # camera south of the hero, looking toward the gate and the cave
	add_child(cam_rig)
	player.cam_rig = cam_rig
	player.facing = Vector3(0, 0, 1)
	cam_rig.yaw = PI
	cam_rig.snap()

	lock_marker = Node3D.new()
	var mk := B.glow(Color(1.0, 0.85, 0.2))
	mk.disable_fog = true
	B.mesh(lock_marker, B.prism(Vector3(0.45, 0.45, 0.12)), Vector3.ZERO, mk, Vector3(180, 0, 0))
	lock_marker.visible = false
	world.add_child(lock_marker)

	var ui := CanvasLayer.new()
	add_child(ui)
	var theme := Theme.new()
	theme.default_font_size = 10
	hud = HudScript.new()
	hud.main = self
	hud.theme = theme
	ui.add_child(hud)
	touch = TouchScript.new()
	touch.theme = theme
	ui.add_child(touch)
	touch.resized.connect(touch.queue_redraw)
	if touch.visible:
		hud.set_hint("Stick: move · B: sword (hold to spin) · A: roll / talk · Z: lock on · drag right side: camera")
	else:
		hud.set_hint("WASD move · J / click: sword (hold to spin) · Space: roll / talk · Tab: lock on · Q/E: camera · F11: fullscreen")

	# A few of the dead are already loose in the field.
	for p in [Vector3(-14, 0, 52), Vector3(16, 0, 64), Vector3(-4, 0, 80)]:
		spawn_zombie(p, false)
	update_sky(0.0)


# ---------------------------------------------------------------- input

func setup_input() -> void:
	add_action("move_left", [key(KEY_A), joy_axis(JOY_AXIS_LEFT_X, -1.0)])
	add_action("move_right", [key(KEY_D), joy_axis(JOY_AXIS_LEFT_X, 1.0)])
	add_action("move_forward", [key(KEY_W), key(KEY_UP), joy_axis(JOY_AXIS_LEFT_Y, -1.0)])
	add_action("move_back", [key(KEY_S), key(KEY_DOWN), joy_axis(JOY_AXIS_LEFT_Y, 1.0)])
	add_action("cam_left", [key(KEY_Q), key(KEY_LEFT), joy_axis(JOY_AXIS_RIGHT_X, -1.0)])
	add_action("cam_right", [key(KEY_E), key(KEY_RIGHT), joy_axis(JOY_AXIS_RIGHT_X, 1.0)])
	add_action("attack", [key(KEY_J), mouse_btn(MOUSE_BUTTON_LEFT), joy_btn(JOY_BUTTON_X), joy_btn(JOY_BUTTON_B)])
	add_action("action", [key(KEY_SPACE), key(KEY_K), key(KEY_ENTER), joy_btn(JOY_BUTTON_A)])
	add_action("target", [key(KEY_TAB), key(KEY_L), mouse_btn(MOUSE_BUTTON_RIGHT), joy_axis(JOY_AXIS_TRIGGER_LEFT, 1.0), joy_btn(JOY_BUTTON_LEFT_SHOULDER)])
	add_action("fullscreen", [key(KEY_F11)])


func add_action(action: String, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	for e in events:
		InputMap.action_add_event(action, e)


func key(k: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k
	return e


func joy_btn(b: JoyButton) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.device = -1
	return e


func joy_axis(a: JoyAxis, v: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = a
	e.axis_value = v
	e.device = -1
	return e


func mouse_btn(b: MouseButton) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = b
	return e


# ---------------------------------------------------------------- world building

func build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 16.0
	env.fog_depth_end = 70.0
	env.fog_depth_curve = 1.0
	env.fog_density = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.shadow_enabled = false
	add_child(sun)


func build_ground() -> void:
	var grass := B.mat(Color(0.38, 0.6, 0.28), B.noise_tex(0.12, "grass", 11), 0.22)
	B.mesh(world, plane(Vector2(260, 320)), Vector3(0, 0, 40), grass)
	var ground := StaticBody3D.new()
	world.add_child(ground)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(260, 1, 320)
	cs.shape = sh
	cs.position = Vector3(0, -0.5, 40)
	ground.add_child(cs)


func plane(size: Vector2) -> PlaneMesh:
	var p := PlaneMesh.new()
	p.size = size
	return p


func strip(a: Vector3, b: Vector3, width: float, material: Material, y: float) -> void:
	var d := b - a
	var mi := B.mesh(world, plane(Vector2(width, d.length())), (a + b) * 0.5 + Vector3(0, y, 0), material)
	mi.rotation.y = atan2(d.x, d.z)


func build_town() -> void:
	var cobble := B.mat(Color(0.62, 0.58, 0.52), B.noise_tex(0.1, "cobble", 5), 0.3)
	B.mesh(world, plane(Vector2(48, 48)), Vector3(0, 0.04, 0), cobble)
	var wood := B.mat(Color(0.5, 0.35, 0.2), B.noise_tex(0.1, "planks", 3), 0.3)
	var dark_wood := B.mat(Color(0.32, 0.22, 0.13), B.noise_tex(0.1, "planks", 3), 0.3)
	var stone := B.mat(Color(0.55, 0.53, 0.5), B.noise_tex(0.12, "bricks", 7), 0.35)

	# Palisade walls with a gate to the north field (+Z).
	B.solid_box(world, Vector3(49, 3.6, 1), Vector3(0, 1.8, -24.5), wood)
	B.solid_box(world, Vector3(1, 3.6, 49), Vector3(-24.5, 1.8, 0), wood)
	B.solid_box(world, Vector3(1, 3.6, 49), Vector3(24.5, 1.8, 0), wood)
	B.solid_box(world, Vector3(21.5, 3.6, 1), Vector3(-13.75, 1.8, 24.5), wood)
	B.solid_box(world, Vector3(21.5, 3.6, 1), Vector3(13.75, 1.8, 24.5), wood)
	for x in range(-24, 25, 3):
		for side in [[x, -24.5], [-24.5, x], [24.5, x], [x, 24.5]]:
			if side[1] == 24.5 and absf(side[0]) < 4.0:
				continue
			B.mesh(world, B.prism(Vector3(1.0, 0.8, 1.0)), Vector3(side[0], 4.0, side[1]), dark_wood)
	for gx in [-3.4, 3.4]:
		B.solid_box(world, Vector3(1.2, 5.4, 1.4), Vector3(gx, 2.7, 24.5), dark_wood)
		B.mesh(world, B.prism(Vector3(1.4, 1.0, 1.6)), Vector3(gx, 5.9, 24.5), dark_wood)
	B.mesh(world, B.box_mesh(Vector3(8.2, 0.7, 1.0)), Vector3(0, 5.0, 24.5), dark_wood)
	B.mesh(world, B.box_mesh(Vector3(3.6, 0.9, 0.12)), Vector3(0, 4.2, 23.9), wood)
	add_lantern(Vector3(-2.4, 0, 22.6))
	add_lantern(Vector3(2.4, 0, 22.6))

	# Houses facing the square.
	var houses := [
		[-14.0, -15.0, 7.0, 6.0, 4.0, Color(0.88, 0.82, 0.68), Color(0.68, 0.22, 0.18)],
		[0.0, -18.0, 10.0, 5.0, 5.0, Color(0.78, 0.8, 0.85), Color(0.22, 0.3, 0.52)],
		[14.0, -15.0, 6.0, 6.0, 4.0, Color(0.85, 0.7, 0.45), Color(0.4, 0.26, 0.16)],
		[-17.0, 1.0, 6.0, 7.0, 4.0, Color(0.8, 0.74, 0.62), Color(0.3, 0.42, 0.3)],
		[17.0, 1.0, 6.0, 7.0, 4.5, Color(0.9, 0.85, 0.75), Color(0.62, 0.3, 0.2)],
		[-15.0, 16.0, 6.0, 5.0, 3.6, Color(0.82, 0.72, 0.58), Color(0.45, 0.25, 0.3)],
		[15.0, 16.0, 6.0, 5.0, 3.6, Color(0.76, 0.78, 0.7), Color(0.55, 0.2, 0.15)],
	]
	for hdef in houses:
		build_house(hdef[0], hdef[1], hdef[2], hdef[3], hdef[4], hdef[5], hdef[6], stone)

	# Well in the square.
	B.solid_cylinder(world, 1.3, 1.0, Vector3(-5, 0, 4))
	B.mesh(world, B.cyl(1.3, 1.4, 1.0, 8), Vector3(-5, 0.5, 4), stone)
	B.mesh(world, B.cyl(1.0, 1.0, 0.05, 8), Vector3(-5, 0.95, 4), B.glow(Color(0.05, 0.08, 0.15)))
	for wx in [-1.1, 1.1]:
		B.mesh(world, B.box_mesh(Vector3(0.18, 2.2, 0.18)), Vector3(-5 + wx, 2.0, 4), dark_wood)
	B.mesh(world, B.prism(Vector3(3.0, 1.0, 2.0)), Vector3(-5, 3.5, 4), B.mat(Color(0.6, 0.25, 0.2), B.noise_tex(0.1, "bricks", 9)))

	# Market stall.
	B.solid_box(world, Vector3(3.4, 1.0, 1.4), Vector3(7, 0.5, -6), wood)
	for sx in [-1.5, 1.5]:
		B.mesh(world, B.box_mesh(Vector3(0.15, 2.6, 0.15)), Vector3(7 + sx, 1.3, -6.6), dark_wood)
	var awning_mat := B.mat(Color(0.75, 0.62, 0.3))
	B.mesh(world, B.box_mesh(Vector3(3.8, 0.1, 2.0)), Vector3(7, 2.6, -6.2), awning_mat, Vector3(-12, 0, 0))
	for i in 4:
		B.mesh(world, B.sphere(0.18, 6, 3), Vector3(5.9 + i * 0.7, 1.15, -6), B.mat([Color(0.8, 0.2, 0.15), Color(0.9, 0.6, 0.1), Color(0.4, 0.6, 0.2), Color(0.6, 0.3, 0.5)][i]))

	# Crates and barrels.
	for c in [Vector3(9.5, 0, -7.5), Vector3(10.3, 0, -6.4), Vector3(-20, 0, -8), Vector3(20, 0, 10), Vector3(-8, 0, 21)]:
		B.solid_box(world, Vector3(1, 1, 1), c + Vector3(0, 0.5, 0), wood, rng.randf_range(0, 40))
	for b in [Vector3(-20.5, 0, -6.5), Vector3(19, 0, 12), Vector3(-9.3, 0, 21.4), Vector3(9, 0, 20.5)]:
		B.solid_cylinder(world, 0.45, 1.1, b)
		B.mesh(world, B.cyl(0.42, 0.45, 1.1, 8), b + Vector3(0, 0.55, 0), dark_wood)

	add_lantern(Vector3(-4, 0, -6))
	add_lantern(Vector3(4, 0, 8))
	add_lantern(Vector3(-11, 0, 10))
	# A gnarled old tree in the square.
	build_tree(Vector3(8, 0, 6), 1.25)


func build_house(x: float, z: float, w: float, d: float, h: float, wall_col: Color, roof_col: Color, stone: Material) -> void:
	var root := Node3D.new()
	root.position = Vector3(x, 0, z)
	root.rotation.y = atan2(-x, -z)
	world.add_child(root)
	var plaster := B.mat(wall_col, B.noise_tex(0.06, "", 21), 0.3)
	B.solid_box(root, Vector3(w, h, d), Vector3(0, h * 0.5, 0), plaster)
	B.mesh(root, B.box_mesh(Vector3(w + 0.1, 0.7, d + 0.1)), Vector3(0, 0.35, 0), stone)
	var roof := B.mat(roof_col, B.noise_tex(0.1, "bricks", 9), 0.5)
	B.mesh(root, B.prism(Vector3(w + 0.8, 2.0, d + 0.8)), Vector3(0, h + 1.0, 0), roof, Vector3(0, 90, 0))
	var trim := B.mat(Color(0.3, 0.2, 0.12))
	B.mesh(root, B.box_mesh(Vector3(1.3, 2.1, 0.12)), Vector3(0, 1.05, d * 0.5 + 0.05), trim)
	var win := B.glow(Color(1.0, 0.82, 0.45))
	window_mats.append(win)
	for wx in [-w * 0.3, w * 0.3]:
		B.mesh(root, B.box_mesh(Vector3(0.9, 0.8, 0.1)), Vector3(wx, h * 0.58, d * 0.5 + 0.04), win)
		B.mesh(root, B.box_mesh(Vector3(1.1, 0.12, 0.16)), Vector3(wx, h * 0.58 - 0.46, d * 0.5 + 0.06), trim)
	B.mesh(root, B.box_mesh(Vector3(0.7, 1.6, 0.7)), Vector3(w * 0.3, h + 1.6, -d * 0.2), stone)


func build_tree(p: Vector3, s: float = 1.0) -> void:
	var trunk := B.mat(Color(0.4, 0.28, 0.17))
	var leaf := B.mat(Color(0.18 + rng.randf_range(-0.03, 0.03), 0.38 + rng.randf_range(-0.05, 0.05), 0.2), B.noise_tex(0.15, "grass", 13), 0.5)
	var root := Node3D.new()
	root.position = p
	root.scale = Vector3.ONE * s
	world.add_child(root)
	B.mesh(root, B.cyl(0.22, 0.34, 2.2, 6), Vector3(0, 1.1, 0), trunk)
	B.mesh(root, B.cyl(0.0, 1.9, 2.6, 7), Vector3(0, 3.0, 0), leaf)
	B.mesh(root, B.cyl(0.0, 1.4, 2.1, 7), Vector3(0, 4.3, 0), leaf, Vector3(0, 25, 0))
	B.solid_cylinder(world, 0.4 * s, 3.0, p)


func add_lantern(p: Vector3) -> void:
	var post := B.mat(Color(0.18, 0.16, 0.15))
	B.solid_cylinder(world, 0.15, 2.8, p)
	B.mesh(world, B.cyl(0.08, 0.1, 2.8, 6), p + Vector3(0, 1.4, 0), post)
	B.mesh(world, B.box_mesh(Vector3(0.4, 0.45, 0.4)), p + Vector3(0, 2.95, 0), B.glow(Color(1.0, 0.75, 0.35)))
	B.mesh(world, B.prism(Vector3(0.55, 0.3, 0.55)), p + Vector3(0, 3.33, 0), post)
	var light := OmniLight3D.new()
	light.position = p + Vector3(0, 2.9, 0)
	light.light_color = Color(1.0, 0.72, 0.4)
	light.omni_range = 9.0
	light.omni_attenuation = 1.2
	light.shadow_enabled = false
	world.add_child(light)
	lanterns.append([light, 1.6, 0.05])


func build_field() -> void:
	var dirt := B.mat(Color(0.55, 0.45, 0.32), B.noise_tex(0.12, "", 17), 0.3)
	strip(Vector3(0, 0, 20), Vector3(0, 0, 42), 4.0, dirt, 0.06)
	strip(Vector3(0, 0, 41), Vector3(10, 0, 70), 4.0, dirt, 0.065)
	strip(Vector3(10, 0, 69), Vector3(10, 0, 112), 4.0, dirt, 0.07)

	var rock := B.mat(Color(0.5, 0.47, 0.44), B.noise_tex(0.14, "", 31), 0.18)
	var cliff := B.mat(Color(0.46, 0.42, 0.38), B.noise_tex(0.16, "", 33), 0.15)

	# Cliffs boxing in the town's flanks and the whole field.
	for sx in [-1, 1]:
		B.solid_box(world, Vector3(30, 9, 60), Vector3(sx * 40, 4.5, -3), cliff)
		var z := 28.0
		while z < 116.0:
			var h := rng.randf_range(8.0, 15.0)
			B.solid_box(world, Vector3(7, h, 8.5), Vector3(sx * rng.randf_range(52.5, 54.0), h * 0.5, z), cliff, rng.randf_range(-6, 6))
			z += 8.0
		B.solid_box(world, Vector3(28, 11, 6), Vector3(sx * 39, 5.5, 27), cliff)
	B.solid_box(world, Vector3(60, 10, 6), Vector3(0, 5, -31), cliff)

	# Ward-stones: the line the dead will not cross.
	var ward_stone := B.mat(Color(0.6, 0.6, 0.64), B.noise_tex(0.1, "", 41), 0.4)
	var rune := B.glow(Color(0.45, 0.95, 1.0))
	var wx := -22.0
	while wx <= 22.0:
		if absf(wx) > 2.5:
			B.solid_cylinder(world, 0.4, 1.4, Vector3(wx, 0, ward_z - 0.5))
			B.mesh(world, B.cyl(0.32, 0.42, 1.4, 5), Vector3(wx, 0.7, ward_z - 0.5), ward_stone)
			B.mesh(world, B.box_mesh(Vector3(0.2, 0.35, 0.05)), Vector3(wx, 0.85, ward_z - 0.12), rune)
		wx += 4.4

	# Trees and boulders scattered across the field, kept off the path.
	var placed := 0
	var tries := 0
	while placed < 46 and tries < 600:
		tries += 1
		var p := Vector3(rng.randf_range(-46, 46), 0, rng.randf_range(32, 100))
		if dist_to_path(p) < 4.5:
			continue
		if p.distance_to(Vector3(10, 0, 106)) < 11.0:
			continue
		build_tree(p, rng.randf_range(0.85, 1.35))
		placed += 1
	for i in 18:
		var p := Vector3(rng.randf_range(-45, 45), 0, rng.randf_range(32, 104))
		if dist_to_path(p) < 3.5:
			continue
		var s := rng.randf_range(0.5, 1.4)
		var r := B.mesh(world, B.sphere(1.0, 6, 4), p + Vector3(0, s * 0.35, 0), rock)
		r.scale = Vector3(s * 1.3, s * 0.8, s)
		r.rotation.y = rng.randf() * TAU
		B.solid_cylinder(world, s * 1.0, s * 0.9, p)

	# Old fence posts and grave markers hinting at what's ahead.
	var grave := B.mat(Color(0.52, 0.52, 0.55), B.noise_tex(0.1, "", 43), 0.4)
	for g in [Vector3(-8, 0, 88), Vector3(-6, 0, 90), Vector3(-9.5, 0, 92), Vector3(-5, 0, 94), Vector3(22, 0, 90), Vector3(24, 0, 93)]:
		B.mesh(world, B.box_mesh(Vector3(0.7, 1.0, 0.2)), g + Vector3(0, 0.5, 0), grave, Vector3(rng.randf_range(-12, 12), rng.randf_range(-20, 20), 0))
		B.mesh(world, B.box_mesh(Vector3(0.8, 0.12, 1.6)), g + Vector3(0, 0.06, 0.9), B.mat(Color(0.35, 0.28, 0.2)))


func dist_to_path(p: Vector3) -> float:
	var pts := [Vector3(0, 0, 20), Vector3(0, 0, 42), Vector3(10, 0, 70), Vector3(10, 0, 112)]
	var best := 1e9
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


func build_cave() -> void:
	var cliff := B.mat(Color(0.42, 0.38, 0.36), B.noise_tex(0.16, "", 35), 0.15)
	var dark := B.glow(Color(0.01, 0.01, 0.02))
	# The cliff face, with a black mouth at x = 10.
	B.solid_box(world, Vector3(63, 15, 4), Vector3(-24.5, 7.5, 110), cliff)
	B.solid_box(world, Vector3(43, 15, 4), Vector3(34.5, 7.5, 110), cliff)
	B.solid_box(world, Vector3(6.5, 10, 4), Vector3(10, 10, 110), cliff)
	B.solid_box(world, Vector3(1, 8, 8), Vector3(6.5, 4, 116), dark)
	B.solid_box(world, Vector3(1, 8, 8), Vector3(13.5, 4, 116), dark)
	B.solid_box(world, Vector3(8, 1, 8), Vector3(10, 5.5, 116), dark)
	B.solid_box(world, Vector3(8, 8, 1), Vector3(10, 4, 120), dark)
	B.mesh(world, plane(Vector2(7, 8)), Vector3(10, 0.08, 115.5), dark)
	# Jagged rocks around the mouth like teeth.
	var tooth := B.mat(Color(0.36, 0.33, 0.32), B.noise_tex(0.16, "", 35), 0.3)
	for t in [[7.6, 4.6, 0.0], [9.0, 4.8, 0.0], [10.6, 4.7, 0.0], [12.2, 4.6, 0.0]]:
		B.mesh(world, B.prism(Vector3(0.9, 1.3, 0.8)), Vector3(t[0], t[1], 107.9), tooth, Vector3(180, 0, 0))
	for r in [Vector3(4, 0, 106.5), Vector3(16, 0, 106.8), Vector3(3, 0, 104)]:
		var m := B.mesh(world, B.sphere(1.3, 6, 4), r + Vector3(0, 0.6, 0), tooth)
		m.scale = Vector3(1.2, 0.9, 1.0)
		B.solid_cylinder(world, 1.3, 1.2, r)
	# Scattered bones.
	var bone := B.mat(Color(0.88, 0.86, 0.76))
	for i in 14:
		var p := Vector3(rng.randf_range(5, 15), 0.06, rng.randf_range(99, 107))
		B.mesh(world, B.box_mesh(Vector3(0.08, 0.08, rng.randf_range(0.3, 0.6))), p, bone, Vector3(0, rng.randf() * 360.0, 0))
	B.mesh(world, B.box_mesh(Vector3(0.3, 0.3, 0.3)), Vector3(13, 0.15, 103), bone, Vector3(0, 30, 0))
	# Torches flanking the cave.
	for tx in [5.5, 14.5]:
		var p := Vector3(tx, 0, 106.6)
		B.solid_cylinder(world, 0.15, 2.2, p)
		B.mesh(world, B.cyl(0.08, 0.12, 2.2, 6), p + Vector3(0, 1.1, 0), B.mat(Color(0.3, 0.2, 0.12)))
		B.mesh(world, B.prism(Vector3(0.35, 0.6, 0.35)), p + Vector3(0, 2.5, 0), B.glow(Color(1.0, 0.55, 0.15)))
		var light := OmniLight3D.new()
		light.position = p + Vector3(0, 2.6, -0.5)
		light.light_color = Color(1.0, 0.5, 0.2)
		light.omni_range = 10.0
		world.add_child(light)
		lanterns.append([light, 2.0, 0.35])


func spawn_npcs() -> void:
	add_npc("Captain Orla", Vector3(4.6, 0, 21.0), PI, {
		"skin": Color(0.78, 0.6, 0.45), "shirt": Color(0.5, 0.2, 0.17), "pants": Color(0.28, 0.24, 0.22),
		"hair": Color(0.12, 0.08, 0.06), "helm": true, "hair_style": "bun", "face": "stern",
		"eye_color": Color(0.35, 0.25, 0.15), "forearm": Color(0.5, 0.2, 0.17), "hand": Color(0.3, 0.2, 0.12),
		"bulk": 1.05,
	}, [
		"Heading out? At this hour?",
		"Ever since the bell cracked, the dead have been crawling out of Hollow Cave, up past the field.",
		"The ward-stones beyond the gate hold them back. Out in the field, though... you're on your own.",
		"Hold your sword arm back to charge a spin. Lock on with Z if they start circling you.",
	])
	add_npc("Grandmother Ysel", Vector3(-7.6, 0, 5.2), 0.8, {
		"skin": Color(0.88, 0.74, 0.64), "shirt": Color(0.36, 0.28, 0.44), "pants": Color(0.32, 0.26, 0.38),
		"hair": Color(0.86, 0.85, 0.84), "shawl": Color(0.58, 0.44, 0.64), "dress": Color(0.3, 0.24, 0.38),
		"hair_style": "bun", "face": "old", "eye_color": Color(0.4, 0.45, 0.5), "hips": 1.1,
	}, [
		"The moon has been wrong for three nights now. Pale as bone, and closer every evening.",
		"When it rises, the cave breathes out the dead.",
		"Somebody ought to find out what is waking them. Wrenmoor can't take many more nights like this.",
	])
	add_npc("Pip", Vector3(5.5, 0, -1.5), -2.4, {
		"skin": Color(0.9, 0.74, 0.6), "shirt": Color(0.86, 0.66, 0.22), "pants": Color(0.3, 0.4, 0.56),
		"hair": Color(0.62, 0.32, 0.12), "hair_style": "short", "face": "kid", "eye_color": Color(0.3, 0.45, 0.25),
		"forearm": Color(0.9, 0.74, 0.6), "bulk": 0.9,
	}, [
		"Mom says I'm not allowed past the gate.",
		"Do they really walk like this? *shuffle* *shuffle* Uuuurgh!",
		"Bring me back a bone shard sometime? Just one. I won't tell anybody.",
	], true)
	add_npc("Dorran the Trader", Vector3(7, 0, -4.4), PI, {
		"skin": Color(0.66, 0.48, 0.35), "shirt": Color(0.3, 0.46, 0.36), "pants": Color(0.36, 0.28, 0.22),
		"hair": Color(0.1, 0.08, 0.06), "hat": Color(0.45, 0.3, 0.18), "beard": Color(0.12, 0.09, 0.07),
		"hair_style": "cropped", "eye_color": Color(0.3, 0.2, 0.12), "apron": Color(0.7, 0.62, 0.48), "bulk": 1.12, "hips": 1.1,
	}, [
		"Bone shards! Bring me the shards those things leave behind.",
		"Grind enough of them down and you get ward-dust. Get me enough, and maybe we seal that cave for good.",
	])
	add_sign("Signpost", Vector3(4.2, 0, 26.6), PI, [
		"WRENMOOR GATE. Beyond the ward-stones: the Hollow Field.",
		"Scratched underneath: THEY ONLY COME OUT AT NIGHT. MOSTLY.",
	])
	add_sign("Weathered sign", Vector3(16.5, 0, 101.5), PI * 0.85, [
		"HOLLOW CAVE.",
		"The rest of the sign has been clawed away.",
		"(This is as far as the prototype goes... for now.)",
	])


func add_npc(n: String, p: Vector3, yaw: float, colors: Dictionary, lines: Array, kid: bool = false) -> void:
	var npc = NpcScript.new()
	npc.main = self
	npc.npc_name = n
	npc.lines = lines
	npc.colors = colors
	npc.kid = kid
	npc.base_yaw = yaw
	npc.position = p
	world.add_child(npc)


func add_sign(n: String, p: Vector3, yaw: float, lines: Array) -> void:
	var npc = NpcScript.new()
	npc.main = self
	npc.npc_name = n
	npc.lines = lines
	npc.is_sign = true
	npc.base_yaw = yaw
	npc.position = p
	world.add_child(npc)


# ---------------------------------------------------------------- gameplay

func spawn_zombie(p: Vector3, emerging: bool = true) -> void:
	var z = ZombieScript.new()
	z.main = self
	z.position = p
	if not emerging:
		z.state = "wander"
	world.add_child(z)


func is_night() -> bool:
	return time_of_day >= 19.0 or time_of_day < 6.0


func alive_zombies() -> int:
	var n := 0
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.is_alive():
			n += 1
	return n


func nearest_zombie(p: Vector3, radius: float):
	var best = null
	var best_d := radius
	for z in get_tree().get_nodes_in_group("zombies"):
		if not z.is_alive():
			continue
		var d: float = p.distance_to(z.global_position)
		if d < best_d:
			best_d = d
			best = z
	return best


func nearest_npc(p: Vector3, radius: float):
	var best = null
	var best_d := radius
	for n in get_tree().get_nodes_in_group("npcs"):
		var d: float = p.distance_to(n.global_position)
		if d < best_d:
			best_d = d
			best = n
	return best


func start_dialog(npc) -> void:
	dialog_active = true
	dialog_lines = npc.lines.duplicate()
	if npc.npc_name == "Dorran the Trader" and shards > 0:
		dialog_lines.append("You've got %d shard%s on you. Keep them coming." % [shards, "" if shards == 1 else "s"])
	if npc.npc_name == "Pip" and shards > 0:
		dialog_lines = ["Whoa! Is that a real bone shard?!", "...I'm gonna pretend I didn't see that. Mom would freak."]
	dialog_index = 0
	dialog_frame = Engine.get_process_frames()
	hud.show_dialog(npc.npc_name, dialog_lines[0])


func advance_dialog() -> void:
	if hud.dialog_typing():
		hud.finish_typing()
		return
	dialog_index += 1
	if dialog_index >= dialog_lines.size():
		dialog_active = false
		dialog_cooldown = 0.4
		hud.hide_dialog()
	else:
		hud.show_dialog(hud.name_label.text, dialog_lines[dialog_index])


func on_zombie_killed(z) -> void:
	kills += 1
	var p: Vector3 = z.global_position
	drop(p, "shard")
	var heart_chance := 0.45 if player.hp < player.max_hp else 0.1
	if randf() < heart_chance:
		drop(p, "heart")


func drop(p: Vector3, kind: String) -> void:
	var pk = PickupScript.new()
	pk.main = self
	pk.kind = kind
	pk.position = Vector3(p.x, 0.6, p.z)
	world.add_child(pk)


func collect(kind: String) -> void:
	if kind == "heart":
		player.heal(2)
		sfx.play("heart")
	else:
		shards += 1
		sfx.play("shard")
		if shards == 1:
			hud.toast("Bone Shard! Dorran the trader wants these.")


func spawn_flash(p: Vector3) -> void:
	var m := B.glow(Color(1, 1, 0.85))
	m.disable_fog = true
	var mi := B.mesh(world, B.sphere(0.35, 6, 3), p, m)
	mi.scale = Vector3.ONE * 0.4
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * 1.3, 0.1)
	tw.tween_callback(mi.queue_free)


func hitstop(t: float) -> void:
	hitstop_time = t
	Engine.time_scale = 0.05


func on_player_died() -> void:
	sfx.play("gameover")
	await get_tree().create_timer(1.6, true, false, true).timeout
	game_over_active = true
	game_over_frame = Engine.get_process_frames()
	hud.show_game_over(true, touch.visible)


func respawn() -> void:
	game_over_active = false
	hud.show_game_over(false, touch.visible)
	for z in get_tree().get_nodes_in_group("zombies"):
		if z.global_position.z < 50.0:
			z.queue_free()
	player.respawn(TOWN_SPAWN)
	cam_rig.yaw = PI
	cam_rig.snap()


func clock_text() -> String:
	var h := int(time_of_day)
	var m := int((time_of_day - h) * 60.0) / 10 * 10
	var ampm := "AM" if h < 12 else "PM"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "Day %d · %d:%02d %s" % [day, h12, m, ampm]


func _process(delta: float) -> void:
	if hitstop_time > 0.0:
		hitstop_time -= delta / maxf(Engine.time_scale, 0.01)
		if hitstop_time <= 0.0:
			Engine.time_scale = 1.0

	if not game_over_active:
		time_of_day += delta * HOURS_PER_SEC
		if time_of_day >= 24.0:
			time_of_day -= 24.0
			day += 1
	update_sky(delta)
	dialog_cooldown = maxf(dialog_cooldown - delta, 0.0)

	if dialog_active and Engine.get_process_frames() != dialog_frame:
		if Input.is_action_just_pressed("action") or Input.is_action_just_pressed("attack"):
			advance_dialog()
	if game_over_active and Engine.get_process_frames() > game_over_frame + 20:
		if Input.is_action_just_pressed("action"):
			respawn()
	if Input.is_action_just_pressed("fullscreen"):
		var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)

	var tgt = player.target
	if tgt != null and is_instance_valid(tgt):
		lock_marker.visible = true
		lock_marker.global_position = tgt.global_position + Vector3(0, 2.35 + sin(Time.get_ticks_msec() * 0.008) * 0.1, 0)
		lock_marker.rotation.y += delta * 4.0
		hud.bars_target = 1.0
	else:
		lock_marker.visible = false
		hud.bars_target = 0.0


func _physics_process(delta: float) -> void:
	if game_over_active:
		return
	spawn_timer -= delta
	var night := is_night()
	var cap := 9 if night else 4
	if spawn_timer <= 0.0:
		spawn_timer = 3.5 if night else 8.0
		if alive_zombies() < cap:
			spawn_zombie(SPAWN_POINT + Vector3(randf_range(-1.5, 1.5), 0, 0))


func update_sky(_delta: float) -> void:
	var h := time_of_day
	var a: Array = SKY_KEYS[0]
	var b: Array = SKY_KEYS[1]
	for i in SKY_KEYS.size() - 1:
		if h >= SKY_KEYS[i][0] and h <= SKY_KEYS[i + 1][0]:
			a = SKY_KEYS[i]
			b = SKY_KEYS[i + 1]
			break
	var t := 0.0
	if b[0] > a[0]:
		t = (h - a[0]) / (b[0] - a[0])
	var sky: Color = (a[1] as Color).lerp(b[1], t)
	var energy: float = lerpf(a[2], b[2], t)
	var amb: float = lerpf(a[3], b[3], t)
	env.background_color = sky
	env.fog_light_color = sky
	env.ambient_light_color = sky.lerp(Color(0.55, 0.6, 0.85), 0.55)
	env.ambient_light_energy = amb
	var day_f := clampf((energy - 0.22) / 0.88, 0.0, 1.0)
	sun.light_energy = energy
	sun.light_color = Color(0.55, 0.62, 1.0).lerp(Color(1.0, 0.96, 0.88), day_f)
	var night_f := 1.0 - day_f
	for l in lanterns:
		var light: OmniLight3D = l[0]
		light.light_energy = l[1] * (0.25 + 0.75 * night_f) * (1.0 + randf_range(-l[2], l[2]))
	for wm in window_mats:
		wm.albedo_color = Color(0.45, 0.42, 0.38).lerp(Color(1.0, 0.82, 0.45), night_f)
