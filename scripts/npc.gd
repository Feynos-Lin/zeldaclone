extends StaticBody3D
## A villager or a signpost you can talk to with the action button.

const B = preload("res://scripts/build.gd")

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


func _ready() -> void:
	add_to_group("npcs")
	collision_layer = 2
	collision_mask = 0
	var cs := CollisionShape3D.new()
	model = Node3D.new()
	add_child(model)
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


func _process(delta: float) -> void:
	if is_sign or main == null:
		return
	t += delta
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
