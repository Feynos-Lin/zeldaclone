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
const WorldScript = preload("res://scripts/world.gd")
const ControlsScript = preload("res://scripts/controls.gd")
const PauseScript = preload("res://scripts/pause_menu.gd")
const GraphicsScript = preload("res://scripts/graphics.gd")

const HOURS_PER_SEC := 1.0 / 20.0      # one in-game hour every 20 seconds
const SPAWN_POINT := Vector3(8, 0, 113)
const TOWN_SPAWN := Vector3(0, 0, 8)

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

var ward_radius := 27.0
var world_builder
var controls
var pause_menu
var graphics
var world: Node3D
var player
var cam_rig
var hud
var touch
var sfx
var env: Environment
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var sky_mat: ProceduralSkyMaterial
var lanterns: Array = []      # [OmniLight3D, base energy, flicker]
var window_mats: Array = []
var lock_marker: Node3D
var time_of_day := 18.0
var day := 1
var spawn_timer := 2.0
var shards := 0
var kills := 0
var dialog_active := false
var dialog_npc = null
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
	controls = ControlsScript.new()
	add_child(controls)
	sfx = SfxScript.new()
	add_child(sfx)
	world = Node3D.new()
	add_child(world)
	build_environment()
	world_builder = WorldScript.new()
	world_builder.build(self)
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
	pause_menu = PauseScript.new()
	pause_menu.main = self
	pause_menu.controls = controls
	pause_menu.theme = theme
	ui.add_child(pause_menu)
	graphics = GraphicsScript.new()
	graphics.main = self
	add_child(graphics)
	graphics.apply_display()
	hud.set_hint(controls.hint_text())
	controls.device_changed.connect(func(_kind): hud.set_hint(controls.hint_text()))
	controls.message.connect(func(text): hud.toast(text))

	# A few of the dead are already loose in the field.
	for p in [Vector3(-12, 0, 46), Vector3(8, 0, 62), Vector3(-2, 0, 84), Vector3(18, 0, 92)]:
		spawn_zombie(p, false)
	update_sky(0.0)


# ---------------------------------------------------------------- input

# ---------------------------------------------------------------- world building

func build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_curve = 0.12
	sky_mat.ground_curve = 0.05
	sky_mat.sun_angle_max = 18.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 16.0
	env.fog_depth_end = 70.0
	env.fog_depth_curve = 1.2
	env.fog_density = 1.0
	env.fog_sky_affect = 0.35
	# Soft, warm "late-GameCube" grade with a little bloom on lights.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 4.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.0
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 42.0
	sun.directional_shadow_split_1 = 0.22
	sun.shadow_blur = 1.6
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.shadow_opacity = 0.9
	add_child(sun)
	# Cool bounce light from the sky on the shadow side.
	fill = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, 215, 0)
	fill.light_color = Color(0.62, 0.72, 1.0)
	fill.light_energy = 0.22
	fill.shadow_enabled = false
	fill.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(fill)


func spawn_npcs() -> void:
	add_npc("Old Brannoc", Vector3(3.4, 0, 19.0), PI, {"sculpt": "res://assets/guard/guard_mesh.res", "anim": "guard"}, [
		"Heading out? At this hour?",
		"Forty years I've stood this gate, and I've never seen the dead walk like they do now.",
		"Ever since the bell cracked, they've been crawling out of Hollow Cave, up the trail through the woods.",
		"The ward-stones hold them back from the village. Out in the trees, though... you're on your own.",
		"Keep that shield up, lad. Hold the shield button and take their blows on the wood, not your skull.",
		"Hold your sword arm back to charge a spin. And lock on if they start circling you.",
	])
	add_npc("Grandmother Ysel", Vector3(8.0, 0, 3.6), 1.1, {"sculpt": "res://assets/villagers/lady_mesh.res", "anim": "elder"}, [
		"The moon has been wrong for three nights now. Pale as bone, and closer every evening.",
		"When it rises, the cave breathes out the dead.",
		"Somebody ought to find out what is waking them. Wrenmoor can't take many more nights like this.",
	])
	add_npc("Pip", Vector3(-1.2, 0, -1.6), 0.4, {"sculpt": "res://assets/villagers/child_mesh.res", "anim": "kid"}, [
		"Mom says I'm not allowed past the gate.",
		"Is that a real sword? And a bow?! And BOMBS?! Can I hold one? ...No? Okay.",
		"Do they really walk like this? *shuffle* *shuffle* Uuuurgh!",
		"Bring me back a bone shard sometime? Just one. I won't tell anybody.",
	], true)
	add_npc("Dorran the Trader", Vector3(10, 0, -9.0), PI, {
		"skin": Color(0.66, 0.48, 0.35), "shirt": Color(0.3, 0.46, 0.36), "pants": Color(0.36, 0.28, 0.22),
		"hair": Color(0.1, 0.08, 0.06), "hat": Color(0.45, 0.3, 0.18), "beard": Color(0.12, 0.09, 0.07),
		"hair_style": "short", "eye_color": Color(0.2, 0.14, 0.1), "head_scale": 1.4, "cuffs": true, "leg": 0.82, "limb": 1.2, "hand_scale": 1.25, "apron": Color(0.7, 0.62, 0.48), "bulk": 1.12, "hips": 1.1,
	}, [
		"Bone shards! Bring me the shards those things leave behind.",
		"Grind enough of them down and you get ward-dust. Get me enough, and maybe we seal that cave for good.",
	])
	add_sign("Signpost", Vector3(3.2, 0, 23.5), 0.0, [
		"WRENMOOR. North trail: Hollow Cave. West road: closed, tree down.",
		"Scratched underneath: THEY ONLY COME OUT AT NIGHT. MOSTLY.",
	])
	add_sign("Weathered sign", Vector3(14.5, 0, 90.0), 0.3, [
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


func in_ward(p: Vector3, margin: float = 0.0) -> bool:
	return Vector2(p.x, p.z).length() < ward_radius + margin


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
	dialog_npc = npc
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
		dialog_npc = null
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
	# ammo, more likely the lower he's running
	if randf() < 0.35 + (0.3 if player.arrows < 6 else 0.0):
		drop(p, "arrows")
	if randf() < 0.18 + (0.25 if player.bombs < 2 else 0.0):
		drop(p, "bombs")


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
	elif kind == "arrows":
		player.arrows = mini(player.arrows + 5, player.MAX_ARROWS)
		sfx.play("shard", 0.8)
	elif kind == "bombs":
		player.bombs = mini(player.bombs + 2, player.MAX_BOMBS)
		sfx.play("shard", 0.7)
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
	hud.show_game_over(true, controls.confirm_name(), controls.last_device == "touch")


func respawn() -> void:
	game_over_active = false
	hud.show_game_over(false, controls.confirm_name(), controls.last_device == "touch")
	for z in get_tree().get_nodes_in_group("zombies"):
		if Vector2(z.global_position.x, z.global_position.z).length() < 45.0:
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
		if Input.is_action_just_pressed("action") or Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("jump"):
			advance_dialog()
	if game_over_active and Engine.get_process_frames() > game_over_frame + 20:
		if Input.is_action_just_pressed("action") or Input.is_action_just_pressed("jump"):
			respawn()
	if Input.is_action_just_pressed("fullscreen"):
		graphics.toggle_fullscreen()

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
	var day_f := clampf((energy - 0.22) / 0.88, 0.0, 1.0)
	var night_f := 1.0 - day_f
	sky_mat.sky_top_color = sky.darkened(0.28).lerp(Color(0.2, 0.36, 0.72), day_f * 0.5)
	sky_mat.sky_horizon_color = sky.lightened(0.12)
	sky_mat.ground_horizon_color = sky.lightened(0.05)
	sky_mat.ground_bottom_color = sky.darkened(0.5)
	sky_mat.sun_angle_max = 18.0 if day_f > 0.1 else 0.0
	env.background_color = sky
	env.fog_light_color = sky.lightened(0.08)
	env.ambient_light_color = sky.lerp(Color(0.62, 0.64, 0.78), 0.6)
	env.ambient_light_energy = amb * 0.55
	sun.light_energy = energy * 1.3
	sun.light_color = Color(0.55, 0.62, 1.0).lerp(Color(1.0, 0.93, 0.8), day_f)
	# Sun arcs across the sky by day; at night the light comes from the moon's side.
	var sun_t := clampf((h - 6.0) / 13.0, 0.0, 1.0)
	if day_f > 0.05:
		sun.rotation_degrees = Vector3(-18.0 - sin(sun_t * PI) * 42.0, lerpf(80.0, -60.0, sun_t), 0)
	else:
		sun.rotation_degrees = Vector3(-48, 200, 0)
	fill.light_energy = lerpf(0.14, 0.3, day_f)
	for l in lanterns:
		var light: OmniLight3D = l[0]
		light.light_energy = l[1] * (0.25 + 0.75 * night_f) * (1.0 + randf_range(-l[2], l[2]))
	for wm in window_mats:
		wm.albedo_color = Color(0.45, 0.42, 0.38).lerp(Color(1.0, 0.82, 0.45), night_f)
