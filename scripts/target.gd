extends Node3D
## A straw archery target on a post. Arrows that hit it report to whoever is
## running the archery challenge.

const B = preload("res://scripts/build.gd")

var on_hit: Callable
var face: Node3D
var wobble := 0.0
var lit := false
var ring_mat: StandardMaterial3D


func _ready() -> void:
	add_to_group("targets")
	var wood := B.paint_mat(Color(0.45, 0.32, 0.2), "leather", 61)
	B.solid_cylinder(self, 0.12, 1.6, Vector3.ZERO)
	B.mesh(self, B.cyl(0.07, 0.08, 1.5, 6), Vector3(0, 0.75, 0), wood)
	face = Node3D.new()
	face.position = Vector3(0, 1.35, 0)
	add_child(face)
	var straw := B.paint_mat(Color(0.86, 0.74, 0.45), "hair", 62)
	ring_mat = B.mat(Color(0.8, 0.2, 0.15))
	B.mesh(face, B.cyl(0.5, 0.5, 0.16, 16), Vector3.ZERO, straw, Vector3(90, 0, 0))
	B.mesh(face, B.cyl(0.36, 0.36, 0.17, 16), Vector3.ZERO, B.mat(Color(0.92, 0.9, 0.82)), Vector3(90, 0, 0))
	B.mesh(face, B.cyl(0.24, 0.24, 0.18, 16), Vector3.ZERO, ring_mat, Vector3(90, 0, 0))
	B.mesh(face, B.cyl(0.1, 0.1, 0.19, 12), Vector3.ZERO, B.mat(Color(0.95, 0.85, 0.3)), Vector3(90, 0, 0))


func centre() -> Vector3:
	return face.global_position


## Called by an arrow passing within the target's face.
func arrow_hit() -> void:
	wobble = 1.0
	if on_hit.is_valid():
		on_hit.call(self)


func set_lit(on: bool) -> void:
	lit = on
	ring_mat.albedo_color = Color(0.3, 0.85, 0.3) if on else Color(0.8, 0.2, 0.15)


func _process(delta: float) -> void:
	wobble = move_toward(wobble, 0.0, delta * 1.5)
	face.rotation.x = sin(wobble * 25.0) * wobble * 0.35
