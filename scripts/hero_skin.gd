extends RefCounted
## Puts the sculpted hero mesh (assets/hero/hero_mesh.res) on top of the
## procedural humanoid rig. The procedural parts keep animating exactly as
## before; every frame their rotations, measured against the rest pose, are
## copied onto a matching skeleton that deforms the sculpted mesh.

const MESH_PATH := "res://assets/hero/hero_mesh.res"

var model: Node3D
var parts: Dictionary
var skeleton: Skeleton3D
var mesh_instance: MeshInstance3D
var names: Array = []
var parent_of: Array = []        # index of parent bone, -1 for the root
var bind_pos: Array = []         # Vector3, bind-pose joint (mesh space)
var target_pos: Array = []       # Vector3, joint in the rest pose
var target_basis: Array = []     # Basis, bone rotation in the rest pose
var rest_inv: Array = []         # Transform3D, inverse of each part's rest transform (model space)
var cur_basis: Array = []
var cur_pos: Array = []


static func available() -> bool:
	return ResourceLoader.exists(MESH_PATH)


func setup(p_model: Node3D, p_parts: Dictionary) -> void:
	model = p_model
	parts = p_parts
	var mesh: ArrayMesh = load(MESH_PATH)
	var rig: Dictionary = mesh.get_meta("rig")
	skeleton = Skeleton3D.new()
	skeleton.name = "HeroSkeleton"
	model.add_child(skeleton)
	var skin := Skin.new()
	for b in rig.bones:
		names.append(b.name)
	for b in rig.bones:
		var i := skeleton.add_bone(b.name)
		parent_of.append(names.find(b.parent) if b.parent != null else -1)
		var bp := _v(b.bind_pos)
		bind_pos.append(bp)
		target_pos.append(_v(b.target_pos))
		var tb: Array = b.target_basis
		target_basis.append(Basis(Vector3(tb[0], tb[1], tb[2]), Vector3(tb[3], tb[4], tb[5]), Vector3(tb[6], tb[7], tb[8])))
		skin.add_named_bind(b.name, Transform3D(Basis(), bp).affine_inverse())
		cur_basis.append(Basis())
		cur_pos.append(bp)
		skeleton.set_bone_rest(i, Transform3D())
	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "HeroMesh"
	mesh_instance.mesh = mesh
	mesh_instance.skin = skin
	skeleton.add_child(mesh_instance)
	mesh_instance.skeleton = NodePath("..")
	# The sculpt replaces the procedural body; weapons stay.
	_strip(model)
	# The animated arms hang from the sculpt's shoulders.
	for side in ["l", "r"]:
		var sh: Node3D = parts["arm_" + side]
		var body_x := _part_xform("body")
		sh.position = body_x.affine_inverse() * (target_pos[names.find("arm_" + side)] as Vector3)
	_thicken(parts.arm_l)
	_thicken(parts.arm_r)
	capture_rest()
	update()


func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _strip(n: Node) -> void:
	for ch in n.get_children():
		if ch == skeleton or ch == parts.arm_l or ch == parts.arm_r:
			continue
		if ch is MeshInstance3D:
			n.remove_child(ch)
			ch.queue_free()
		else:
			_strip(ch)


## The sculpt has chunkier, baggier sleeves than the stock rig.
func _thicken(n: Node) -> void:
	for ch in n.get_children():
		if ch.name == "Sword" or ch.name == "Shield":
			continue
		if ch is MeshInstance3D:
			(ch as MeshInstance3D).scale *= Vector3(1.2, 1.0, 1.2)
		_thicken(ch)


func _part_xform(name: String) -> Transform3D:
	var n: Node3D = parts[name]
	var t := n.transform
	var p := n.get_parent()
	while p != model and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


## Call with the procedural rig in its rest pose.
func capture_rest() -> void:
	rest_inv.clear()
	for nm in names:
		rest_inv.append(_part_xform(nm).affine_inverse())


func update() -> void:
	for i in names.size():
		var now := _part_xform(names[i])
		var delta: Transform3D = now * (rest_inv[i] as Transform3D)
		var db: Basis = delta.basis.orthonormalized()
		var pi: int = parent_of[i]
		var pos: Vector3
		if pi < 0:
			pos = delta * (target_pos[i] as Vector3)
		else:
			var parent_delta: Basis = cur_basis[pi] * (target_basis[pi] as Basis).inverse()
			pos = (cur_pos[pi] as Vector3) + parent_delta * ((target_pos[i] as Vector3) - (target_pos[pi] as Vector3))
		var b: Basis = db * (target_basis[i] as Basis)
		cur_basis[i] = b
		cur_pos[i] = pos
		skeleton.set_bone_pose(i, Transform3D(b, pos))
