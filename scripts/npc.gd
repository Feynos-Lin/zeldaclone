extends StaticBody3D
## A villager or a signpost you can talk to with the action button.

const B = preload("res://scripts/build.gd")
const SculptRig = preload("res://scripts/sculpt_rig.gd")

var main
var npc_name := ""
var lines: Array = []
var colors := {}
var is_sign := false
var kid := false
var model: Node3D
var parts := {}
var base_yaw := 0.0
var t := 0.0
var sculpt = null          # SculptRig for characters with a sculpted model
var stomp_t := -1.0        # time into the current spear stamp, < 0 when idle
var dip := 0.0
var arm_up_axis := Vector3.RIGHT
var anim := ""             # guard, elder or kid, for sculpted villagers
var talk_t := 0.0


func _ready() -> void:
	add_to_group("npcs")
	collision_layer = 2
	collision_mask = 0
	var cs := CollisionShape3D.new()
	model = Node3D.new()
	add_child(model)
	if colors.has("sculpt"):
		var cap0 := CapsuleShape3D.new()
		cap0.radius = 0.38
		cap0.height = 1.7
		cs.shape = cap0
		cs.position.y = 0.85
		sculpt = SculptRig.new()
		sculpt.setup(model, colors.sculpt)
		anim = colors.get("anim", "guard")
		if anim == "guard":
			_prepare_stamp()
		B.blob_shadow(self, 0.45)
		add_child(cs)
		model.rotation.y = base_yaw
		t = randf() * 10.0
		return
	if is_sign:
		var sh := BoxShape3D.new()
		sh.size = Vector3(1.4, 1.8, 0.4)
		cs.shape = sh
		cs.position.y = 0.9
		var wood := B.mat(Color(0.55, 0.38, 0.22), B.noise_tex(0.1, "planks", 3))
		B.mesh(model, B.box_mesh(Vector3(0.16, 1.6, 0.16)), Vector3(0, 0.8, 0), wood)
		B.mesh(model, B.box_mesh(Vector3(1.4, 0.75, 0.1)), Vector3(0, 1.35, -0.05), wood)
		B.mesh(model, B.box_mesh(Vector3(1.1, 0.06, 0.02)), Vector3(0, 1.48, -0.11), B.mat(Color(0.15, 0.1, 0.06)))
		B.mesh(model, B.box_mesh(Vector3(0.8, 0.06, 0.02)), Vector3(-0.1, 1.3, -0.11), B.mat(Color(0.15, 0.1, 0.06)))
	else:
		var cap := CapsuleShape3D.new()
		cap.radius = 0.35
		cap.height = 1.7
		cs.shape = cap
		cs.position.y = 0.85
		var c := colors.duplicate()
		if kid:
			c["head_scale"] = 1.65
		parts = B.humanoid(model, c)
		var body: Node3D = parts.body
		if colors.has("hat"):
			var hat := B.paint_mat(colors.hat, "leather", 9)
			B.mesh(parts.head, B.cyl(0.21, 0.21, 0.025, 12), Vector3(0, 0.27, 0.005), hat)
			B.mesh(parts.head, B.cyl(0.095, 0.115, 0.12, 10), Vector3(0, 0.33, 0.005), hat)
			B.mesh(parts.head, B.cyl(0.117, 0.117, 0.03, 10), Vector3(0, 0.29, 0.005), B.paint_mat(Color(0.25, 0.15, 0.1), "leather"))
		if colors.has("helm"):
			var steel := B.paint_mat(Color(0.62, 0.64, 0.68), "metal")
			B.mesh(parts.head, B.loft(B.rings_offset([
				[1.645, 0.112, 0.124, 0.01], [1.7, 0.118, 0.13, 0.006], [1.76, 0.1, 0.112, 0.0], [1.81, 0.06, 0.07, 0.0], [1.835, 0.002, 0.002, 0.0],
			], -1.5), 12), Vector3.ZERO, steel)
			B.mesh(parts.head, B.box_mesh(Vector3(0.022, 0.09, 0.02)), Vector3(0, 0.15, -0.122), steel)
			B.mesh(parts.head, B.box_mesh(Vector3(0.02, 0.06, 0.12)), Vector3(0, 0.33, 0.0), B.paint_mat(Color(0.72, 0.18, 0.14), "cloth"))
			# Breastplate over the tunic
			B.mesh(body, B.loft([[1.02, 0.15, 0.108], [1.2, 0.178, 0.128, -0.008], [1.31, 0.198, 0.124, -0.004], [1.4, 0.19, 0.108], [1.44, 0.13, 0.08]], 12), Vector3.ZERO, steel)
			for side in [-1, 1]:
				B.mesh(parts.arm_l if side < 0 else parts.arm_r, B.sphere(0.066, 8, 5), Vector3(0, 0.0, 0), steel)
			# Spear held upright in the right hand
			var spear := Node3D.new()
			spear.position = Vector3(0, -0.3, -0.01)
			spear.rotation.x = -1.6
			parts.forearm_r.add_child(spear)
			B.mesh(spear, B.cyl(0.018, 0.018, 2.2, 6), Vector3(0, 0.55, 0), B.paint_mat(Color(0.48, 0.32, 0.17), "leather"))
			B.mesh(spear, B.prism(Vector3(0.08, 0.22, 0.02)), Vector3(0, 1.75, 0), steel)
			parts.arm_r.rotation.x = 0.35
			parts.forearm_r.rotation.x = 1.25
		if colors.has("shawl"):
			B.mesh(body, B.loft([[1.16, 0.25, 0.16], [1.3, 0.255, 0.15], [1.4, 0.2, 0.12], [1.47, 0.07, 0.06]], 12), Vector3.ZERO, B.paint_mat(colors.shawl, "cloth", 31))
			B.mesh(body, B.loft([[0.06, 0.25, 0.23], [0.45, 0.2, 0.17], [0.84, 0.158, 0.118], [1.02, 0.142, 0.1]], 12), Vector3.ZERO, B.paint_mat(colors.dress, "cloth", 33))
			parts.pivot.rotation.x = -0.18
			parts.head.rotation.x = 0.2
		if colors.has("apron"):
			B.mesh(body, B.box_mesh(Vector3(0.26, 0.5, 0.02)), Vector3(0, 0.88, -0.118), B.paint_mat(colors.apron, "cloth", 35))
		if kid:
			model.scale = Vector3.ONE * 0.68
		B.blob_shadow(self, 0.4)
	add_child(cs)
	B.merge_children(model)
	model.rotation.y = base_yaw
	t = randf() * 10.0


## Works out which way to swing the upper arm so the elbow, and the spear
## hand with it, lifts straight up.
func _prepare_stamp() -> void:
	var sh: Vector3 = sculpt.joints[sculpt.names.find("arm_l")]
	var el: Vector3 = sculpt.joints[sculpt.names.find("forearm_l")]
	var u := (el - sh).normalized()
	var ax := u.cross(Vector3.UP)
	if ax.length() < 0.01:
		ax = Vector3.FORWARD
	ax = ax.normalized()
	arm_up_axis = ax if (Basis(ax, 0.3) * u).y > u.y else -ax


func _process(delta: float) -> void:
	if is_sign or main == null:
		return
	t += delta
	if sculpt != null:
		_animate_sculpt(delta)
		return
	var p = main.player
	var d: float = global_position.distance_to(p.global_position)
	var desired := base_yaw
	if d < 5.0:
		var to: Vector3 = p.global_position - global_position
		desired = B.yaw_of(Vector3(to.x, 0, to.z))
	model.rotation.y = lerp_angle(model.rotation.y, desired, 4.0 * delta)
	parts.body.position.y = parts.body_y + sin(t * 2.0) * 0.012
	parts.head.rotation.x = sin(t * 0.7) * 0.06
	if kid:
		parts.arm_l.rotation.z = -0.3 + sin(t * 3.0) * 0.2
		parts.arm_r.rotation.z = 0.3 - sin(t * 3.0) * 0.2


func _animate_sculpt(delta: float) -> void:
	var p = main.player
	var d: float = global_position.distance_to(p.global_position)
	var desired := base_yaw
	if d < 5.0:
		var to: Vector3 = p.global_position - global_position
		desired = B.yaw_of(Vector3(to.x, 0, to.z))
	model.rotation.y = lerp_angle(model.rotation.y, desired, 4.0 * delta)
	var talking: bool = main.dialog_active and main.dialog_npc == self
	talk_t = talk_t + delta if talking else 0.0
	match anim:
		"elder":
			_animate_elder(talking)
		"kid":
			_animate_kid(talking)
		_:
			_animate_guard(talking, delta)


## Grandmother: slow breathing and a gentle sway; while talking she nods along
## and lifts her right hand, palm up, as she makes her point.
func _animate_elder(talking: bool) -> void:
	var breathe := sin(t * 1.4) * 0.005
	var nod := sin(talk_t * 3.2) * 0.07 if talking else 0.0
	var gesture := (0.5 + 0.5 * sin(talk_t * 1.6 - 1.2)) if talking else 0.0
	gesture = gesture * gesture
	sculpt.apply({
		"body": Transform3D(Basis(Vector3.FORWARD, sin(t * 0.6) * 0.02) * Basis(Vector3.RIGHT, -0.03), Vector3(0, breathe, 0)),
		"head": Transform3D(Basis.from_euler(Vector3(sin(t * 0.5) * 0.04 + nod - 0.04, sin(t * 0.3) * 0.1, sin(t * 0.45) * 0.04)), Vector3.ZERO),
		"arm_r": Transform3D(Basis(Vector3.RIGHT, 0.55 * gesture) * Basis(Vector3.BACK, 0.12 * gesture), Vector3.ZERO),
		"forearm_r": Transform3D(Basis(Vector3.RIGHT, 0.75 * gesture), Vector3.ZERO),
		"arm_l": Transform3D(Basis(Vector3.RIGHT, sin(t * 1.4) * 0.02), Vector3.ZERO),
	})


## Pip: never quite still, rocking on his heels and swinging his arms; talking to
## the hero he bounces and waves.
func _animate_kid(talking: bool) -> void:
	var bounce := absf(sin(t * (5.0 if talking else 2.2))) * (0.025 if talking else 0.008)
	var swing := sin(t * 2.2) * 0.12
	var wave_up := clampf(talk_t * 3.0, 0.0, 1.0) if talking else 0.0
	var wave := sin(talk_t * 9.0) * 0.35 * wave_up
	sculpt.apply({
		"body": Transform3D(Basis(Vector3.RIGHT, sin(t * 2.2) * 0.03), Vector3(0, bounce, 0)),
		"head": Transform3D(Basis.from_euler(Vector3(sin(t * 1.1) * 0.05, sin(t * 0.7) * 0.15, sin(t * 1.7) * 0.06)), Vector3.ZERO),
		"arm_r": Transform3D(Basis(Vector3.BACK, (0.15 + swing * 0.5) * (1.0 - wave_up) + 2.5 * wave_up), Vector3.ZERO),
		"forearm_r": Transform3D(Basis(Vector3.BACK, wave), Vector3.ZERO),
		"arm_l": Transform3D(Basis(Vector3.FORWARD, 0.15 - swing * 0.5) * Basis(Vector3.RIGHT, swing), Vector3.ZERO),
	})


func _animate_guard(talking: bool, delta: float) -> void:
	# Spear stamp while talking: lift (0.4 s), hold, drive it down, rest.
	var lift := 0.0
	if talking and stomp_t < 0.0:
		stomp_t = 0.0
	if stomp_t >= 0.0:
		var before := stomp_t
		stomp_t += delta
		if stomp_t < 0.4:
			var k := stomp_t / 0.4
			lift = 1.0 - (1.0 - k) * (1.0 - k)
		elif stomp_t < 0.62:
			lift = 1.0
		elif stomp_t < 0.7:
			var k2 := (stomp_t - 0.62) / 0.08
			lift = 1.0 - k2 * k2
		if before < 0.7 and stomp_t >= 0.7:
			_stamp_impact()
		if stomp_t >= 1.5:
			stomp_t = 0.0 if talking else -1.0
	dip = move_toward(dip, 0.0, delta * 0.25)
	var a := lift * 0.95
	var R := Basis(arm_up_axis, a)
	var breathe := sin(t * 1.8) * 0.006
	var pose := {
		"body": Transform3D(Basis(Vector3.RIGHT, -dip * 1.5 - lift * 0.04), Vector3(0, breathe - dip, 0)),
		"head": Transform3D(Basis.from_euler(Vector3(sin(t * 0.7) * 0.05 + (0.12 if talking and stomp_t > 0.7 and stomp_t < 0.9 else 0.0), sin(t * 0.4) * 0.08, 0)), Vector3.ZERO),
		"arm_l": Transform3D(R, Vector3.ZERO),
		"forearm_l": Transform3D(R.inverse(), Vector3(0, lift * 0.1, 0)),
		"arm_r": Transform3D(Basis(Vector3.RIGHT, sin(t * 1.8) * 0.03), Vector3.ZERO),
	}
	sculpt.apply(pose)


func _stamp_impact() -> void:
	dip = 0.035
	var butt: Array = sculpt.rig.spear_butt
	var bp: Vector3 = model.global_transform * Vector3(butt[0], 0.02, butt[2])
	main.sfx.play_at("stomp", bp)
	# a puff of dust where the spear lands
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.62, 0.55, 0.45, 0.55)
	var puff := MeshInstance3D.new()
	puff.mesh = B.sphere(0.12, 10, 5)
	puff.material_override = m
	puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_parent().add_child(puff)
	puff.global_position = bp
	puff.scale = Vector3(1.0, 0.25, 1.0)
	var tw := puff.create_tween()
	tw.set_parallel(true)
	tw.tween_property(puff, "scale", Vector3(3.2, 0.5, 3.2), 0.45)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.45)
	tw.chain().tween_callback(puff.queue_free)
