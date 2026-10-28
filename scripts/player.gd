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

# Sword-arm poses: [arm direction, blade direction, torso twist, elbow bend, blade flat hint].
# Directions are in the hero's own space: -Z is forward, +X his right, +Y up.
const REST_POSE := [Vector3(0.12, -1.0, -0.18), Vector3(0.12, -0.4, -1.0), 0.0, 0.35, Vector3.UP]
const GUARD_POSE := [Vector3(0.22, -0.6, -0.78), Vector3(0.05, 0.3, -1.0), -0.12, 0.6, Vector3.UP]
const CHARGE_POSE := [Vector3(0.85, -0.05, 0.45), Vector3(0.5, 0.1, 0.86), -0.6, 0.35, Vector3.UP]
const SPIN_POSE := [Vector3(1.0, 0.05, -0.2), Vector3(1.0, 0.0, -0.1), 0.0, 0.1, Vector3.UP]
# Each swing: wind-up, contact, follow-through.
const SWINGS := [
	[   # right-to-left slash
		[Vector3(0.9, 0.0, 0.35), Vector3(0.45, 0.18, 0.87), -0.55, 0.35, Vector3.UP],
		[Vector3(0.25, 0.05, -1.0), Vector3(0.1, -0.02, -1.0), 0.0, 0.1, Vector3.UP],
		[Vector3(-0.6, -0.15, -0.75), Vector3(-0.95, -0.12, -0.25), 0.55, 0.2, Vector3.UP],
	],
	[   # backhand, left-to-right
		[Vector3(-0.45, -0.05, -0.6), Vector3(-0.95, 0.15, 0.15), 0.5, 0.45, Vector3.UP],
		[Vector3(0.3, 0.08, -1.0), Vector3(0.2, 0.0, -1.0), 0.0, 0.15, Vector3.UP],
		[Vector3(0.95, -0.05, -0.15), Vector3(0.85, -0.12, 0.5), -0.55, 0.2, Vector3.UP],
	],
	[   # overhead chop
		[Vector3(0.3, 1.0, 0.12), Vector3(0.05, 0.55, 0.85), -0.15, 1.1, Vector3.RIGHT],
		[Vector3(0.2, 0.35, -1.0), Vector3(0.05, 0.45, -1.0), 0.0, 0.25, Vector3.RIGHT],
		[Vector3(0.15, -0.55, -0.85), Vector3(0.05, -0.8, -0.6), 0.05, 0.15, Vector3.RIGHT],
	],
]
var cur_pose: Array = REST_POSE
var from_pose: Array = REST_POSE


func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 2 | 4
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
		"skin": Color(0.95, 0.74, 0.58),
		"shirt": Color(0.52, 0.32, 0.19),
		"arm": Color(0.52, 0.32, 0.19),
		"forearm": Color(0.5, 0.31, 0.18),
		"hand": Color(0.95, 0.74, 0.58),
		"pants": Color(0.56, 0.53, 0.48),
		"hair": Color(0.47, 0.29, 0.14),
		"boots": Color(0.44, 0.29, 0.17),
		"eye_color": Color(0.16, 0.15, 0.18),
		"hair_style": "spiky",
		"face": "worried",
		"smudge": true,
		"pointed_ears": true,
		"vneck": true,
		"cuffs": true,
		"baggy": 1.2,
		"head_scale": 1.68,
		"bulk": 1.0,
		"leg": 0.74,
		"limb": 1.22,
		"arm_len": 0.86,
		"hand_scale": 1.35,
	})
	model.scale = Vector3.ONE * 0.95
	var body: Node3D = parts.body
	var tunic := B.paint_mat(Color(0.52, 0.32, 0.19), "cloth", 21)
	var rope := B.paint_mat(Color(0.72, 0.6, 0.4), "rope")
	var leather := B.paint_mat(Color(0.36, 0.22, 0.12), "leather")
	# Tunic hem flaring over the hips
	B.mesh(body, B.loft([[0.66, 0.198, 0.158], [0.72, 0.19, 0.15], [0.84, 0.172, 0.13], [0.94, 0.156, 0.112], [1.0, 0.146, 0.104]], 12), Vector3.ZERO, tunic)
	# Rope belt, knotted at the front with two hanging ends
	B.mesh(body, B.loft([[0.945, 0.156, 0.113], [0.965, 0.168, 0.124], [0.985, 0.166, 0.122], [1.005, 0.152, 0.11]], 14), Vector3.ZERO, rope)
	B.mesh(body, B.sphere(0.028, 6, 4), Vector3(0.06, 0.968, -0.122), rope)
	for k in 2:
		var end := Node3D.new()
		end.position = Vector3(0.055 + k * 0.03, 0.95, -0.122 + k * 0.004)
		end.rotation.z = 0.12 - k * 0.2
		body.add_child(end)
		B.mesh(end, B.cyl(0.011, 0.013, 0.15 - k * 0.03, 5), Vector3(0, -0.075 + k * 0.015, 0), rope)
		B.mesh(end, B.cyl(0.018, 0.008, 0.035, 5), Vector3(0, -0.155 + k * 0.03, 0), rope)
	# Small wooden buckler strapped to the left forearm
	var shield := Node3D.new()
	shield.position = Vector3(-0.065, -0.13, 0)
	shield.rotation_degrees = Vector3(0, 0, 90)
	parts.forearm_l.add_child(shield)
	B.mesh(shield, B.cyl(0.21, 0.21, 0.04, 12), Vector3.ZERO, B.paint_mat(Color(0.55, 0.37, 0.2), "leather", 5))
	B.mesh(shield, B.cyl(0.222, 0.222, 0.03, 12), Vector3(0, 0.005, 0), B.paint_mat(Color(0.48, 0.47, 0.46), "metal"))
	B.mesh(shield, B.sphere(0.05, 8, 4), Vector3(0, 0.03, 0), B.paint_mat(Color(0.55, 0.54, 0.52), "metal"))

	# Sword: tapered blade, crossguard, wrapped grip, pommel
	sword_root = Node3D.new()
	sword_root.position = Vector3(0, -0.3, -0.005)
	parts.forearm_r.add_child(sword_root)
	blade_mat = B.mat(Color(0.82, 0.86, 0.92))
	B.mesh(sword_root, B.box_mesh(Vector3(0.055, 0.014, 0.78)), Vector3(0, 0, -0.5), blade_mat)
	B.mesh(sword_root, B.prism(Vector3(0.055, 0.14, 0.014)), Vector3(0, 0, -0.96), blade_mat, Vector3(-90, 0, 0))
	B.mesh(sword_root, B.box_mesh(Vector3(0.22, 0.04, 0.045)), Vector3(0, 0, -0.1), B.paint_mat(Color(0.5, 0.48, 0.45), "metal"))
	B.mesh(sword_root, B.cyl(0.02, 0.022, 0.18, 6), Vector3(0, 0, 0.0), leather, Vector3(90, 0, 0))
	B.mesh(sword_root, B.sphere(0.032, 6, 4), Vector3(0, 0, 0.1), B.paint_mat(Color(0.5, 0.48, 0.45), "metal"))
	B.merge_children(model)
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
	from_pose = cur_pose
	face_target()
	blade_mat.albedo_color = Color(0.82, 0.86, 0.92)
	main.sfx.play("spin" if is_spin else "swing")


func state_attack(delta: float) -> void:
	var dur := 0.5 if spin else 0.38
	var t := clampf(state_time / dur, 0.0, 1.0)
	var lunge := 0.0 if spin else 4.0 * (1.0 - t)
	velocity.x = facing.x * lunge
	velocity.z = facing.z * lunge
	if Input.is_action_pressed("attack"):
		held_time += delta
	if not spin and state_time > 0.08 and Input.is_action_just_pressed("attack"):
		combo_queued = true
	if not hit_done and state_time >= (0.14 if spin else dur * 0.4):
		hit_done = true
		do_hit()
	pose_attack(t)
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
		main.controls.rumble(0.35, 0.2 if not spin else 0.5, 0.1)


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
	main.controls.rumble(0.5, 0.8 if hp - amount <= 0 else 0.55, 0.3)
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
	parts.pivot.rotation.y = 0.0
	apply_pose(REST_POSE)


func nlerp(a: Vector3, b: Vector3, t: float) -> Vector3:
	var v := a.normalized().lerp(b.normalized(), t)
	return v.normalized() if v.length() > 0.001 else b.normalized()


func blend_pose(p: Array, q: Array, t: float) -> Array:
	return [nlerp(p[0], q[0], t), nlerp(p[1], q[1], t), lerpf(p[2], q[2], t), lerpf(p[3], q[3], t), q[4] if t > 0.5 else p[4]]


## Points the shoulder, bends the elbow, twists the torso, and angles the blade.
func apply_pose(p: Array) -> void:
	cur_pose = p
	var twist: float = p[2]
	parts.body.rotation.y = twist
	parts.leg_l.rotation.y = -twist
	parts.leg_r.rotation.y = -twist
	var d: Vector3 = (p[0] as Vector3).normalized()
	var up := Vector3.BACK if absf(d.y) > 0.9 else Vector3.UP
	parts.arm_r.basis = Basis.looking_at(d, up) * Basis(Vector3.RIGHT, PI * 0.5)
	parts.forearm_r.rotation.x = p[3]
	var bd: Vector3 = (p[1] as Vector3).normalized()
	var hint: Vector3 = p[4]
	if absf(bd.dot(hint)) > 0.95:
		hint = Vector3.BACK
	sword_root.global_basis = parts.body.global_basis * Basis.looking_at(bd, hint)


func pose_attack(t: float) -> void:
	if spin:
		var e := 1.0 - pow(1.0 - t, 2.0)
		parts.pivot.rotation.y = lerpf(-0.6, TAU, e)
		apply_pose(blend_pose(from_pose, SPIN_POSE, minf(t * 6.0, 1.0)))
		return
	var k: Array = SWINGS[combo]
	var p: Array
	if t < 0.22:
		var w := t / 0.22
		p = blend_pose(from_pose, k[0], 1.0 - (1.0 - w) * (1.0 - w))
	elif t < 0.6:
		var w := (t - 0.22) / 0.38
		w = w * w * (3.0 - 2.0 * w)
		if w < 0.5:
			p = blend_pose(k[0], k[1], w * 2.0)
		else:
			p = blend_pose(k[1], k[2], (w - 0.5) * 2.0)
	else:
		p = k[2]
	apply_pose(p)


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
			parts.shin_l.rotation.x = -maxf(0.0, -cos(anim_t)) * 0.9 - 0.08
			parts.shin_r.rotation.x = -maxf(0.0, cos(anim_t)) * 0.9 - 0.08
			al.rotation.x = -s * 0.5
			parts.forearm_l.rotation.x = 0.25 + maxf(0.0, -s) * 0.5
			parts.body.position.y = parts.body_y + abs(cos(anim_t)) * 0.06
		else:
			la.rotation.x = lerp(la.rotation.x, 0.0, 10.0 * delta)
			lr.rotation.x = lerp(lr.rotation.x, 0.0, 10.0 * delta)
			al.rotation.x = lerp(al.rotation.x, 0.0, 10.0 * delta)
			parts.shin_l.rotation.x = lerp(parts.shin_l.rotation.x, 0.0, 10.0 * delta)
			parts.shin_r.rotation.x = lerp(parts.shin_r.rotation.x, 0.0, 10.0 * delta)
			parts.forearm_l.rotation.x = lerp(parts.forearm_l.rotation.x, 0.15, 10.0 * delta)
			parts.body.position.y = parts.body_y + sin(Time.get_ticks_msec() * 0.003) * 0.015
		if target != null:
			al.rotation.x = 0.5   # shield up while locked on
			parts.forearm_l.rotation.x = 1.3
		var want: Array
		if state == "charge":
			want = CHARGE_POSE.duplicate()
			if state_time >= CHARGE_TIME:
				want[0] = (want[0] as Vector3) + Vector3(randf_range(-0.03, 0.03), randf_range(-0.03, 0.03), 0)
		elif target != null:
			want = GUARD_POSE
		else:
			want = REST_POSE.duplicate()
			if hspeed > 0.4:
				want[0] = Vector3(0.12, -1.0, -0.18 + sin(anim_t) * 0.4)
		apply_pose(blend_pose(cur_pose, want, minf(1.0, 14.0 * delta)))
	elif state == "attack":
		la.rotation.x = 0.4
		lr.rotation.x = -0.3
		parts.shin_l.rotation.x = -0.2
		parts.shin_r.rotation.x = -0.4
	if state == "roll" or state == "hurt" or state == "dead":
		apply_pose(blend_pose(cur_pose, REST_POSE, minf(1.0, 14.0 * delta)))
	if state == "roll":
		la.rotation.x = 1.6
		lr.rotation.x = 1.3
		parts.shin_l.rotation.x = -2.0
		parts.shin_r.rotation.x = -1.8
