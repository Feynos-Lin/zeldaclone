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
		parts = B.humanoid(model, colors)
		if colors.has("hat"):
			B.mesh(parts.head, B.box_mesh(Vector3(0.5, 0.18, 0.5)), Vector3(0, 0.5, 0), B.mat(colors.hat))
		if colors.has("helm"):
			var steel := B.mat(Color(0.6, 0.62, 0.66))
			B.mesh(parts.head, B.box_mesh(Vector3(0.44, 0.24, 0.44)), Vector3(0, 0.45, 0), steel)
			B.mesh(parts.body, B.box_mesh(Vector3(0.62, 0.4, 0.38)), Vector3(0, 1.26, 0), steel)
			B.mesh(parts.arm_r, B.cyl(0.03, 0.03, 2.4, 4), Vector3(0, -0.55, -0.05), B.mat(Color(0.45, 0.3, 0.15)))
			B.mesh(parts.arm_r, B.prism(Vector3(0.18, 0.35, 0.04)), Vector3(0, 0.75, -0.05), steel)
		if colors.has("shawl"):
			B.mesh(parts.body, B.box_mesh(Vector3(0.66, 0.3, 0.42)), Vector3(0, 1.32, 0), B.mat(colors.shawl))
			B.mesh(parts.body, B.box_mesh(Vector3(0.62, 0.55, 0.4)), Vector3(0, 0.55, 0), B.mat(colors.shirt))
			parts.pivot.rotation.x = -0.15
		if kid:
			model.scale = Vector3.ONE * 0.68
		B.blob_shadow(self, 0.4)
	add_child(cs)
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
	parts.body.position.y = -0.85 + sin(t * 2.0) * 0.012
	parts.head.rotation.x = sin(t * 0.7) * 0.06
	if kid:
		parts.arm_l.rotation.z = -0.3 + sin(t * 3.0) * 0.2
		parts.arm_r.rotation.z = 0.3 - sin(t * 3.0) * 0.2
