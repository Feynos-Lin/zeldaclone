extends CharacterBody3D
## The hero: camera-relative movement, 3-hit sword combo, charged spin attack,
## dodge roll with invincibility frames, and lock-on targeting.

const B = preload("res://scripts/build.gd")

const SPEED := 5.5
const ROLL_SPEED := 10.5
const ROLL_TIME := 0.45
const GRAVITY := 24.0
const CHARGE_TIME := 0.7

var main
var cam_rig
var model: Node3D
var parts := {}
var sword_root: Node3D
var blade_mat: StandardMaterial3D

var max_hp := 6   # half-hearts: 6 = 3 hearts
var hp := 6
var facing := Vector3(0, 0, -1)
var state := "move"   # move, attack, charge, roll, hurt, dead
var state_time := 0.0
var combo := 0
var combo_queued := false
var hit_done := false
var spin := false
var held_time := 0.0
var invuln := 0.0
var knock := Vector3.ZERO
var roll_dir := Vector3.ZERO
var target = null
var anim_t := 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 2
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)

	model = Node3D.new()
	add_child(model)
	parts = B.humanoid(model, {
		"skin": Color(0.93, 0.76, 0.6),
		"shirt": Color(0.24, 0.32, 0.5),
		"arm": Color(0.2, 0.26, 0.42),
		"pants": Color(0.36, 0.28, 0.2),
		"hair": Color(0.2, 0.13, 0.08),
		"boots": Color(0.28, 0.17, 0.09),
	})
	var body: Node3D = parts.body
	var scarf := B.mat(Color(0.78, 0.16, 0.12))
	B.mesh(body, B.box_mesh(Vector3(0.6, 0.14, 0.38)), Vector3(0, 1.42, 0), scarf)
	B.mesh(body, B.box_mesh(Vector3(0.16, 0.5, 0.06)), Vector3(0.12, 1.18, 0.21), scarf, Vector3(18, 0, 10))
	B.mesh(body, B.box_mesh(Vector3(0.58, 0.08, 0.34)), Vector3(0, 0.84, 0), B.mat(Color(0.3, 0.2, 0.1)))
	# Round-ish wooden shield strapped to the left arm
	B.mesh(parts.arm_l, B.cyl(0.3, 0.3, 0.07, 8), Vector3(-0.12, -0.32, 0), B.mat(Color(0.5, 0.33, 0.16)), Vector3(0, 0, 90))
	B.mesh(parts.arm_l, B.cyl(0.08, 0.08, 0.09, 6), Vector3(-0.15, -0.32, 0), B.mat(Color(0.7, 0.68, 0.6)), Vector3(0, 0, 90))

	sword_root = Node3D.new()
	body.add_child(sword_root)
	blade_mat = B.mat(Color(0.82, 0.86, 0.92))
	B.mesh(sword_root, B.box_mesh(Vector3(0.07, 0.03, 1.0)), Vector3(0, 0, -0.62), blade_mat)
	B.mesh(sword_root, B.box_mesh(Vector3(0.32, 0.07, 0.07)), Vector3(0, 0, -0.1), B.mat(Color(0.72, 0.56, 0.2)))
	B.mesh(sword_root, B.box_mesh(Vector3(0.06, 0.06, 0.22)), Vector3(0, 0, 0.05), B.mat(Color(0.32, 0.18, 0.1)))
	B.blob_shadow(self)
	rest_pose()


func is_alive() -> bool:
	return state != "dead"


func _physics_process(delta: float) -> void:
	state_time += delta
	invuln = maxf(invuln - delta, 0.0)
	model.visible = state == "dead" or invuln <= 0.0 or int(invuln * 20.0) % 2 == 0

	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta

	var frozen: bool = main.dialog_active or main.game_over_active
	var input_vec := Vector2.ZERO
	if not frozen:
		input_vec = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move_dir := cam_relative(input_vec)

	update_target(frozen)

	match state:
		"move":
			state_move(move_dir, frozen)
		"attack":
			state_attack(delta)
		"charge":
			state_charge(move_dir)
		"roll":
			state_roll()
		"hurt":
			var k := 1.0 - clampf(state_time / 0.3, 0.0, 1.0)
			velocity.x = knock.x * k
			velocity.z = knock.z * k
			if state_time >= 0.3:
				state = "move"
		"dead":
			velocity.x = 0.0
			velocity.z = 0.0
			var p: Node3D = parts.pivot
			p.rotation.x = lerp(p.rotation.x, PI * 0.5, 6.0 * delta)
			p.position.y = lerp(p.position.y, 0.25, 6.0 * delta)

	move_and_slide()
	animate(delta)


func cam_relative(v: Vector2) -> Vector3:
	if v == Vector2.ZERO:
		return Vector3.ZERO
	var yaw: float = cam_rig.yaw
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var d := right * v.x + fwd * (-v.y)
	if d.length() > 1.0:
		d = d.normalized()
	return d


func face_target() -> void:
	if target != null and is_instance_valid(target):
		var to: Vector3 = target.global_position - global_position
		to.y = 0
		if to.length() > 0.1:
			facing = to.normalized()


func update_target(frozen: bool) -> void:
	if target != null:
		if not is_instance_valid(target) or not target.is_alive() or global_position.distance_to(target.global_position) > 18.0:
			# Hop to the next closest enemy, like a real lock-on would.
			target = main.nearest_zombie(global_position, 8.0)
	if frozen or state == "dead":
		return
	if Input.is_action_just_pressed("target"):
		if target != null:
			target = null
		else:
			target = main.nearest_zombie(global_position, 15.0)
			if target == null:
				cam_rig.recenter(facing)
			else:
				main.sfx.play("lock")


func state_move(move_dir: Vector3, frozen: bool) -> void:
	var spd := SPEED * (0.8 if target != null else 1.0)
	velocity.x = move_dir.x * spd
	velocity.z = move_dir.z * spd
	if target != null:
		face_target()
	elif move_dir.length() > 0.1:
		facing = move_dir.normalized()
	if frozen:
		return
	if Input.is_action_just_pressed("attack"):
		start_attack(0, false)
	elif Input.is_action_just_pressed("action"):
		var npc = main.nearest_npc(global_position, 2.6)
		if npc != null and main.dialog_cooldown > 0.0:
			pass
		elif npc != null:
			velocity.x = 0.0
			velocity.z = 0.0
			main.start_dialog(npc)
		elif move_dir.length() > 0.2:
			start_roll(move_dir.normalized())
		else:
			start_roll(facing)


func start_attack(c: int, is_spin: bool) -> void:
	state = "attack"
	state_time = 0.0
	combo = c
	combo_queued = false
	hit_done = false
	spin = is_spin
	held_time = 0.0
	face_target()
	blade_mat.albedo_color = Color(0.82, 0.86, 0.92)
	main.sfx.play("spin" if is_spin else "swing")


func state_attack(delta: float) -> void:
	var dur := 0.5 if spin else 0.32
	var t := clampf(state_time / dur, 0.0, 1.0)
	var lunge := 0.0 if spin else 4.0 * (1.0 - t)
	velocity.x = facing.x * lunge
	velocity.z = facing.z * lunge
	if Input.is_action_pressed("attack"):
		held_time += delta
	if not spin and state_time > 0.08 and Input.is_action_just_pressed("attack"):
		combo_queued = true
	if not hit_done and state_time >= (0.14 if spin else 0.08):
		hit_done = true
		do_hit()
	pose_sword(t)
	if state_time >= dur:
		if combo_queued and combo < 2:
			start_attack(combo + 1, false)
		elif not spin and Input.is_action_pressed("attack") and held_time > 0.18:
			state = "charge"
			state_time = 0.0
		else:
			state = "move"
			rest_pose()


func state_charge(move_dir: Vector3) -> void:
	velocity.x = move_dir.x * SPEED * 0.4
	velocity.z = move_dir.z * SPEED * 0.4
	if target != null:
		face_target()
	elif move_dir.length() > 0.1:
		facing = move_dir.normalized()
	sword_root.position = Vector3(0.3, 1.0, 0.1)
	sword_root.rotation_degrees = Vector3(-8, 115, 0)
	parts.arm_r.rotation.x = 0.6
	if state_time >= CHARGE_TIME:
		var f := 0.5 + 0.5 * sin(state_time * 30.0)
		blade_mat.albedo_color = Color(0.82, 0.86, 0.92).lerp(Color(1.0, 0.95, 0.5), f)
		if state_time - get_physics_process_delta_time() < CHARGE_TIME:
			main.sfx.play("charged")
	if not Input.is_action_pressed("attack"):
		if state_time >= CHARGE_TIME:
			start_attack(0, true)
		else:
			state = "move"
			blade_mat.albedo_color = Color(0.82, 0.86, 0.92)
			rest_pose()


func start_roll(dir: Vector3) -> void:
	state = "roll"
	state_time = 0.0
	roll_dir = dir
	facing = dir
	main.sfx.play("roll")


func state_roll() -> void:
	var t := clampf(state_time / ROLL_TIME, 0.0, 1.0)
	var spd := ROLL_SPEED * (1.0 - t * 0.6)
	velocity.x = roll_dir.x * spd
	velocity.z = roll_dir.z * spd
	var p: Node3D = parts.pivot
	p.rotation.x = -t * TAU
	p.position.y = 0.85 - sin(t * PI) * 0.4
	if state_time >= ROLL_TIME:
		p.rotation.x = 0.0
		p.position.y = 0.85
		state = "move"


func do_hit() -> void:
	var reach := 2.9 if spin else 2.3
	var dmg := 1
	if spin or combo == 2:
		dmg = 2
	var landed := false
	for z in get_tree().get_nodes_in_group("zombies"):
		if not z.is_alive():
			continue
		var to: Vector3 = z.global_position - global_position
		to.y = 0
		var d := to.length()
		if d > reach:
			continue
		var dir := facing
		if d > 0.05:
			dir = to / d
			if not spin and facing.dot(dir) < 0.25:
				continue
		z.take_hit(dmg, dir)
		main.spawn_flash(z.global_position + Vector3(0, 1.1, 0))
		landed = true
	if landed:
		main.hitstop(0.05)


func take_damage(amount: int, push_dir: Vector3) -> void:
	if state == "dead" or invuln > 0.0:
		return
	if state == "roll" and state_time < 0.35:
		return
	hp = maxi(hp - amount, 0)
	invuln = 1.2
	knock = push_dir.normalized() * 7.0
	knock.y = 0
	main.sfx.play("hurt")
	main.cam_rig.shake(0.25)
	rest_pose()
	parts.pivot.rotation.x = 0.0
	parts.pivot.position.y = 0.85
	if hp <= 0:
		state = "dead"
		state_time = 0.0
		target = null
		main.on_player_died()
	else:
		state = "hurt"
		state_time = 0.0


func heal(amount: int) -> void:
	hp = mini(hp + amount, max_hp)


func respawn(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	hp = max_hp
	state = "move"
	state_time = 0.0
	invuln = 1.5
	target = null
	facing = Vector3(0, 0, 1)
	parts.pivot.rotation.x = 0.0
	parts.pivot.position.y = 0.85
	rest_pose()


func rest_pose() -> void:
	sword_root.position = Vector3(0.38, 0.86, -0.05)
	sword_root.rotation_degrees = Vector3(-62, 0, 0)
	parts.arm_r.rotation = Vector3.ZERO


func pose_sword(t: float) -> void:
	# Sword swings around the chest; arm follows.
	sword_root.position = Vector3(0, 1.1, 0)
	var e := 1.0 - pow(1.0 - t, 3.0)
	if spin:
		sword_root.rotation_degrees = Vector3(0, 90.0 - e * 400.0, 0)
		model.rotation.y += 0.0
	elif combo == 0:
		sword_root.rotation_degrees = Vector3(-5, lerp(100.0, -85.0, e), 0)
	elif combo == 1:
		sword_root.rotation_degrees = Vector3(5, lerp(-100.0, 85.0, e), 0)
	else:
		sword_root.rotation_degrees = Vector3(lerp(80.0, -65.0, e), 0, 0)
	parts.arm_r.rotation.x = 1.3


func animate(delta: float) -> void:
	var desired := B.yaw_of(facing)
	model.rotation.y = lerp_angle(model.rotation.y, desired, 16.0 * delta)
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var la: Node3D = parts.leg_l
	var lr: Node3D = parts.leg_r
	var al: Node3D = parts.arm_l
	if state == "move" or state == "charge":
		if hspeed > 0.4:
			anim_t += delta * hspeed * 1.9
			var s := sin(anim_t)
			la.rotation.x = s * 0.7
			lr.rotation.x = -s * 0.7
			al.rotation.x = -s * 0.5
			parts.body.position.y = -0.85 + abs(cos(anim_t)) * 0.06
		else:
			la.rotation.x = lerp(la.rotation.x, 0.0, 10.0 * delta)
			lr.rotation.x = lerp(lr.rotation.x, 0.0, 10.0 * delta)
			al.rotation.x = lerp(al.rotation.x, 0.0, 10.0 * delta)
			parts.body.position.y = -0.85 + sin(Time.get_ticks_msec() * 0.003) * 0.015
		if target != null:
			al.rotation.x = 1.2   # shield up while locked on
	elif state == "attack":
		la.rotation.x = 0.4
		lr.rotation.x = -0.3
