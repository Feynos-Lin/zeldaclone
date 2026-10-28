extends CharacterBody3D
## A shambling dead thing from Hollow Cave. Emerges, wanders, chases,
## winds up a two-armed swipe, flinches when struck, and sinks into the earth.

const B = preload("res://scripts/build.gd")
const GRAVITY := 24.0

var main
var hp := 3
var state := "emerge"   # emerge, wander, chase, windup, recover, hurt, dying
var state_time := 0.0
var speed := 1.5
var model: Node3D
var parts := {}
var knock := Vector3.ZERO
var wander_target := Vector3.ZERO
var emerge_dir := Vector3(0, 0, -1)
var anim_t := 0.0
var attack_cd := 0.0
var flash_time := 0.0
var groan_timer := 0.0
var mesh_mats: Array = []
var flash_mat: StandardMaterial3D
var voice: AudioStreamPlayer3D
var face_dir := Vector3(0, 0, -1)


func _ready() -> void:
	add_to_group("zombies")
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)

	speed = randf_range(1.3, 1.8)
	anim_t = randf() * TAU
	var tint: float = [-0.04, 0.0, 0.04].pick_random()
	model = Node3D.new()
	add_child(model)
	var skin := Color(0.5 + tint, 0.58 + tint, 0.45)
	var shirt: Color = [Color(0.4, 0.34, 0.27), Color(0.3, 0.33, 0.38), Color(0.45, 0.3, 0.25), Color(0.36, 0.4, 0.3)].pick_random()
	parts = B.humanoid(model, {
		"skin": skin,
		"shirt": shirt,
		"arm": shirt.darkened(0.1),
		"forearm": skin,
		"pants": [Color(0.24, 0.22, 0.22), Color(0.3, 0.26, 0.2), Color(0.22, 0.25, 0.3)].pick_random(),
		"hair": [Color(0.22, 0.22, 0.2), Color(0.35, 0.3, 0.25), Color(0.5, 0.5, 0.48)].pick_random(),
		"boots": Color(0.17, 0.14, 0.12),
		"face": "zombie",
		"face_res": 1,
		"glow_eyes": Color(1.0, 0.3, 0.15),
		"hair_style": ["stringy", "none", "stringy", "long", "short"].pick_random(),
		"head_scale": 1.32,
		"leg": 0.88,
		"limb": 1.08,
		"hand_scale": 1.2,
		"bulk": randf_range(0.9, 1.1),
	})
	# Ragged shirt hem hanging in tatters
	var rag := B.paint_mat(shirt.darkened(0.15), "cloth", 41)
	for i in 7:
		var a := -PI + TAU * i / 7.0 + randf_range(-0.2, 0.2)
		var p := Vector3(sin(a) * 0.14, 0.95, -cos(a) * 0.1)
		B.mesh(parts.body, B.prism(Vector3(0.07, randf_range(0.08, 0.16), 0.02)), p, rag, Vector3(180, rad_to_deg(-a), randf_range(-15, 15)))
	# Exposed rib shading on some of them
	if randf() < 0.5:
		var bone := B.mat(Color(0.82, 0.8, 0.7))
		for i in 3:
			B.mesh(parts.body, B.box_mesh(Vector3(0.1, 0.012, 0.02)), Vector3(0.05, 1.12 + i * 0.05, -0.115), bone, Vector3(0, 0, -8))
	parts.pivot.rotation.x = -0.22
	parts.arm_l.rotation.x = 1.45
	parts.arm_r.rotation.x = 1.3
	parts.forearm_l.rotation.x = -0.25
	parts.forearm_r.rotation.x = -0.15
	parts.shin_l.rotation.x = -0.15
	parts.shin_r.rotation.x = -0.15
	parts.head.rotation.x = 0.15
	B.blob_shadow(self, 0.48)
	model.scale = Vector3.ONE * randf_range(0.95, 1.1)

	B.merge_children(model)
	flash_mat = B.glow(Color(1, 1, 1))
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		mesh_mats.append([mi, mi.material_override])

	voice = AudioStreamPlayer3D.new()
	voice.max_distance = 26.0
	voice.unit_size = 5.0
	voice.volume_db = -4.0
	add_child(voice)
	groan_timer = randf_range(1.5, 6.0)
	wander_target = position
	if state == "emerge":
		face_dir = emerge_dir


func is_alive() -> bool:
	return state != "dying"


func set_state(s: String) -> void:
	state = s
	state_time = 0.0


func _physics_process(delta: float) -> void:
	state_time += delta
	attack_cd = maxf(attack_cd - delta, 0.0)
	update_flash(delta)

	if state == "dying":
		var p: Node3D = parts.pivot
		p.rotation.x = lerp(p.rotation.x, -PI * 0.5, 5.0 * delta)
		p.position.y = lerp(p.position.y, 0.3, 5.0 * delta)
		if state_time > 0.9:
			position.y -= delta * 0.9
		if state_time > 2.4:
			queue_free()
		return

	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta

	var player = main.player
	var to_p: Vector3 = player.global_position - global_position
	to_p.y = 0
	var dist := to_p.length()
	var player_ok: bool = player.is_alive() and not main.in_ward(player.global_position, -0.5) and not main.game_over_active
	var aggro := 20.0 if main.is_night() else 13.0

	match state:
		"emerge":
			walk(emerge_dir, speed * 0.8)
			if state_time > 3.0:
				set_state("wander")
				pick_wander()
		"wander":
			if player_ok and dist < aggro:
				set_state("chase")
				groan()
			else:
				if global_position.distance_to(wander_target) < 1.0 or state_time > 7.0:
					pick_wander()
					state_time = 0.0
				var to_w := wander_target - global_position
				to_w.y = 0
				walk(to_w.normalized() if to_w.length() > 0.1 else Vector3.ZERO, speed * 0.55)
		"chase":
			if not player_ok or dist > aggro + 8.0:
				set_state("wander")
				pick_wander()
			elif dist < 1.55 and attack_cd <= 0.0:
				set_state("windup")
				face_dir = to_p.normalized()
				velocity.x = 0.0
				velocity.z = 0.0
			else:
				walk(to_p / maxf(dist, 0.01), speed)
		"windup":
			velocity.x = 0.0
			velocity.z = 0.0
			if dist > 0.1:
				face_dir = face_dir.lerp(to_p / dist, 4.0 * delta).normalized()
			var t := minf(state_time / 0.55, 1.0)
			parts.arm_l.rotation.x = lerp(1.45, 2.9, t)
			parts.arm_r.rotation.x = lerp(1.3, 2.9, t)
			if state_time >= 0.55:
				if player_ok and dist < 1.95:
					var fwd := face_dir
					if dist < 0.3 or fwd.dot(to_p / dist) > 0.2:
						player.take_damage(1, to_p if dist > 0.01 else fwd)
				main.sfx.play_at("swipe", global_position)
				attack_cd = 1.4
				set_state("recover")
		"recover":
			velocity.x = 0.0
			velocity.z = 0.0
			var t2 := minf(state_time / 0.25, 1.0)
			parts.arm_l.rotation.x = lerp(0.6, 1.45, t2)
			parts.arm_r.rotation.x = lerp(0.6, 1.3, t2)
			if state_time >= 0.7:
				set_state("chase")
		"hurt":
			var k := 1.0 - minf(state_time / 0.35, 1.0)
			velocity.x = knock.x * k
			velocity.z = knock.z * k
			if state_time >= 0.35:
				set_state("chase")

	# The ward-stones keep the dead out of Wrenmoor.
	var flat := Vector2(global_position.x, global_position.z)
	if flat.length() < main.ward_radius + 0.8 and flat.length() > 0.01:
		var out := Vector3(flat.x, 0, flat.y).normalized()
		var vout := velocity.x * out.x + velocity.z * out.z
		if vout < 1.2:
			velocity.x += out.x * (1.2 - vout)
			velocity.z += out.z * (1.2 - vout)

	move_and_slide()
	animate(delta)

	groan_timer -= delta
	if groan_timer <= 0.0:
		groan_timer = randf_range(4.0, 9.0)
		if dist < 26.0:
			groan()


func walk(dir: Vector3, spd: float) -> void:
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	if dir.length() > 0.1:
		face_dir = dir


func pick_wander() -> void:
	var p := global_position + Vector3(randf_range(-9, 9), 0, randf_range(-9, 9))
	p.x = clampf(p.x, -44.0, 44.0)
	p.z = clampf(p.z, -40.0, 104.0)
	var fl := Vector2(p.x, p.z)
	if fl.length() < main.ward_radius + 3.0:
		fl = fl.normalized() * (main.ward_radius + 3.0)
		p.x = fl.x
		p.z = fl.y
	wander_target = p


func groan() -> void:
	if voice.playing:
		return
	voice.stream = main.sfx.get_stream("groan")
	voice.pitch_scale = randf_range(0.8, 1.15)
	voice.play()


func take_hit(dmg: int, dir: Vector3) -> void:
	if state == "dying":
		return
	hp -= dmg
	flash_time = 0.12
	knock = dir.normalized() * 6.5
	knock.y = 0
	parts.arm_l.rotation.x = 1.45
	parts.arm_r.rotation.x = 1.3
	main.sfx.play_at("hit", global_position)
	if hp <= 0:
		set_state("dying")
		collision_layer = 0
		collision_mask = 0
		voice.stream = main.sfx.get_stream("die")
		voice.pitch_scale = randf_range(0.85, 1.05)
		voice.play()
		main.on_zombie_killed(self)
	else:
		set_state("hurt")
		attack_cd = maxf(attack_cd, 0.6)


func update_flash(delta: float) -> void:
	if flash_time > 0.0:
		flash_time -= delta
		var on := flash_time > 0.0
		for pair in mesh_mats:
			pair[0].material_override = flash_mat if on else pair[1]


func animate(delta: float) -> void:
	model.rotation.y = lerp_angle(model.rotation.y, B.yaw_of(face_dir), 5.0 * delta)
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if state == "chase" or state == "wander" or state == "emerge":
		anim_t += delta * (1.5 + hspeed * 2.2)
		var s := sin(anim_t)
		parts.leg_l.rotation.x = s * 0.45
		parts.leg_r.rotation.x = -s * 0.45
		parts.shin_l.rotation.x = -0.15 - maxf(0.0, -cos(anim_t)) * 0.5
		parts.shin_r.rotation.x = -0.15 - maxf(0.0, cos(anim_t)) * 0.5
		parts.pivot.rotation.z = s * 0.12
		parts.head.rotation.z = sin(anim_t * 0.5) * 0.25
		parts.arm_l.rotation.x = 1.45 + sin(anim_t * 1.3) * 0.12
		parts.arm_r.rotation.x = 1.3 + cos(anim_t * 1.1) * 0.12
	elif state == "hurt":
		parts.pivot.rotation.x = lerp(parts.pivot.rotation.x, 0.25, 12.0 * delta)
	if state != "hurt":
		parts.pivot.rotation.x = lerp(parts.pivot.rotation.x, -0.22, 6.0 * delta)
