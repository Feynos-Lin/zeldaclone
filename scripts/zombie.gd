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
	collision_mask = 1 | 2
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)

	speed = randf_range(1.3, 1.8)
	anim_t = randf() * TAU
	var tint := randf_range(-0.05, 0.05)
	model = Node3D.new()
	add_child(model)
	parts = B.humanoid(model, {
		"skin": Color(0.47 + tint, 0.56 + tint, 0.42),
		"shirt": [Color(0.38, 0.33, 0.27), Color(0.3, 0.32, 0.36), Color(0.42, 0.28, 0.24)].pick_random(),
		"arm": Color(0.47 + tint, 0.56 + tint, 0.42),
		"pants": Color(0.22, 0.2, 0.2),
		"hair": Color(0.25, 0.25, 0.22),
		"boots": Color(0.15, 0.13, 0.12),
		"eye": Color(1.0, 0.25, 0.15),
	})
	# Torn shirt edge and a jaw hanging open
	B.mesh(parts.body, B.box_mesh(Vector3(0.5, 0.14, 0.3)), Vector3(0.04, 0.76, 0), B.mat(Color(0.3, 0.26, 0.22)), Vector3(0, 0, 8))
	B.mesh(parts.head, B.box_mesh(Vector3(0.2, 0.05, 0.03)), Vector3(0, 0.08, -0.185), B.mat(Color(0.12, 0.05, 0.05)))
	parts.pivot.rotation.x = -0.22
	parts.arm_l.rotation.x = 1.45
	parts.arm_r.rotation.x = 1.3
	B.blob_shadow(self, 0.48)
	model.scale = Vector3.ONE * randf_range(0.95, 1.1)

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
	var player_ok: bool = player.is_alive() and player.global_position.z > main.ward_z and not main.game_over_active
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
	if global_position.z < main.ward_z + 0.8:
		velocity.z = maxf(velocity.z, 1.2)

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
	p.x = clampf(p.x, -45.0, 45.0)
	p.z = clampf(p.z, main.ward_z + 3.0, 104.0)
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
		parts.pivot.rotation.z = s * 0.12
		parts.head.rotation.z = sin(anim_t * 0.5) * 0.25
		parts.arm_l.rotation.x = 1.45 + sin(anim_t * 1.3) * 0.12
		parts.arm_r.rotation.x = 1.3 + cos(anim_t * 1.1) * 0.12
	elif state == "hurt":
		parts.pivot.rotation.x = lerp(parts.pivot.rotation.x, 0.25, 12.0 * delta)
	if state != "hurt":
		parts.pivot.rotation.x = lerp(parts.pivot.rotation.x, -0.22, 6.0 * delta)
