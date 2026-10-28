extends Node3D
## Floating heart or bone shard dropped by a fallen zombie.

const B = preload("res://scripts/build.gd")

var main
var kind := "shard"
var t := 0.0
var life := 25.0
var vel := Vector3.ZERO
var gfx: Node3D


func _ready() -> void:
	gfx = Node3D.new()
	add_child(gfx)
	if kind == "heart":
		var red := B.glow(Color(0.95, 0.15, 0.2))
		B.mesh(gfx, B.sphere(0.16, 6, 3), Vector3(-0.11, 0.06, 0), red)
		B.mesh(gfx, B.sphere(0.16, 6, 3), Vector3(0.11, 0.06, 0), red)
		B.mesh(gfx, B.box_mesh(Vector3(0.26, 0.26, 0.16)), Vector3(0, -0.07, 0), red, Vector3(0, 0, 45))
	else:
		var bone := B.glow(Color(0.92, 0.9, 0.78))
		B.mesh(gfx, B.prism(Vector3(0.2, 0.42, 0.1)), Vector3(0, 0, 0), bone)
		B.mesh(gfx, B.prism(Vector3(0.2, 0.3, 0.1)), Vector3(0, -0.3, 0), bone, Vector3(0, 0, 180))
	B.blob_shadow(self, 0.18)
	vel = Vector3(randf_range(-1.5, 1.5), 4.0, randf_range(-1.5, 1.5))


func _process(delta: float) -> void:
	t += delta
	life -= delta
	# Small pop out of the body, then hover.
	if vel != Vector3.ZERO:
		vel.y -= 14.0 * delta
		var p := position + vel * delta
		if p.y <= 0.0 and vel.y < 0.0:
			p.y = 0.0
			vel = Vector3.ZERO
		position = p
	gfx.position.y = 0.55 + sin(t * 3.0) * 0.1
	gfx.rotation.y += delta * 2.5
	if life < 5.0:
		gfx.visible = int(life * 8.0) % 2 == 0
	if life <= 0.0:
		queue_free()
		return
	var pl = main.player
	if pl.is_alive() and t > 0.4:
		var d: Vector3 = pl.global_position - global_position
		d.y = 0
		if d.length() < 1.1:
			main.collect(kind)
			queue_free()
