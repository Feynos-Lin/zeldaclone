extends RefCounted
## A sculpted, painted character mesh with a small joint skeleton, posed in code.
## Each bone turns about its joint (see the rig stored on the mesh); a pose is
## a Dictionary of bone name -> Transform3D in the bone's own joint space
## (rotation about the joint, plus an optional offset).

var skeleton: Skeleton3D
var mesh_instance: MeshInstance3D
var rig: Dictionary
var names: Array = []
var parent_of: Array = []
var joints: Array = []
var globals: Array = []


func setup(parent: Node3D, mesh_path: String) -> void:
	var mesh: ArrayMesh = load(mesh_path)
	rig = mesh.get_meta("rig")
	skeleton = Skeleton3D.new()
	parent.add_child(skeleton)
	var skin := Skin.new()
	for b in rig.bones:
		names.append(b.name)
	for b in rig.bones:
		var i := skeleton.add_bone(b.name)
		parent_of.append(names.find(b.parent) if b.parent != null else -1)
		joints.append(Vector3(b.joint[0], b.joint[1], b.joint[2]))
		skin.add_named_bind(b.name, Transform3D())
		skeleton.set_bone_rest(i, Transform3D())
		globals.append(Transform3D())
	mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.skin = skin
	skeleton.add_child(mesh_instance)
	mesh_instance.skeleton = NodePath("..")
	apply({})


func apply(pose: Dictionary) -> void:
	for i in names.size():
		var j: Vector3 = joints[i]
		var local := Transform3D(Basis(), j) * (pose.get(names[i], Transform3D()) as Transform3D) * Transform3D(Basis(), -j)
		var g: Transform3D = local if parent_of[i] < 0 else (globals[parent_of[i]] as Transform3D) * local
		globals[i] = g
		skeleton.set_bone_pose(i, g)


## A point of the sculpt (mesh space) carried by a bone, in world space.
func point_global(bone: String, p: Vector3) -> Vector3:
	return skeleton.global_transform * ((globals[names.find(bone)] as Transform3D) * p)
