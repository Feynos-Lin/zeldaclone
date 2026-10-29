extends Node3D
## An arrow in flight: falls a little, sticks in whatever it hits, and hurts zombies.

const B = preload("res://scripts/build.gd")

var main
var vel := Vector3.ZERO
var damage := 1
var stuck := false
var life := 4.0


static func make_mesh(parent: Node3D) -> void:
	# Shaft along -Z with the head at the front, fletching at the back.
	var wood := B.paint_mat(Color(0.6, 0.45, 0.28), "leather", 3)
	var steel := B.paint_mat(Color(0.7, 0.71, 0.72), "metal")
	var feather := B.mat(Color(0.86, 0.84, 0.78))
	B.mesh(parent, B.cyl(0.008, 0.008, 0.68, 5), Vector3(0, 0, -0.02), wood, Vector3(90, 0, 0))
	B.mesh(parent, B.prism(Vector3(0.035, 0.08, 0.008)), Vector3(0, 0, -0.39), steel, Vector3(-90, 0, 0))
	for i in 3:
		var f := Node3D.new()
		f.rotation.z = TAU * i / 3.0
		parent.add_child(f)
		B.mesh(f, B.box_mesh(Vector3(0.002, 0.03, 0.1)), Vector3(0, 0.017, 0.27), feather)


func _ready() -> void:
	make_mesh(self)
	if vel.length() > 0.01:
		look_at(global_position + vel, Vector3.UP)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if stuck:
		return
	vel.y -= 9.0 * delta
	var from := global_position
	var to := from + vel * delta
	# zombies first: is any body within reach of this step?
	for z in get_tree().get_nodes_in_group("zombies"):
		if not z.is_alive():
			continue
		var c: Vector3 = z.global_position + Vector3(0, 1.0, 0)
		var seg := to - from
		var tt := clampf((c - from).dot(seg) / maxf(seg.length_squared(), 1e-6), 0.0, 1.0)
		var closest := from + seg * tt
		if closest.distance_to(c) < 0.5 and absf(closest.y - c.y) < 0.9:
			var dir := Vector3(vel.x, 0, vel.z).normalized()
			z.take_hit(damage, dir)
			main.spawn_flash(closest)
			main.hitstop(0.03)
			queue_free()
			return
	# archery targets
	for tg in get_tree().get_nodes_in_group("targets"):
		var c2: Vector3 = tg.centre()
		var seg2 := to - from
		var tt2 := clampf((c2 - from).dot(seg2) / maxf(seg2.length_squared(), 1e-6), 0.0, 1.0)
		var cl2 := from + seg2 * tt2
		if cl2.distance_to(c2) < 0.5:
			global_position = cl2
			stuck = true
			life = 6.0
			tg.arrow_hit()
			main.sfx.play_at("thunk", cl2)
			return
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() or to.y < -0.5:
		global_position = hit.position if not hit.is_empty() else Vector3(to.x, 0.0, to.z)
		stuck = true
		life = 8.0
		main.sfx.play_at("thunk", global_position)
		return
	global_position = to
	look_at(to + vel, Vector3.UP)
