extends Node3D
## Village animals: hens that peck and scatter, a dog that trots about and
## tags along after the hero, and cats that wander and sit in the sun.
## They don't need physics: they steer around anything solid with a short ray.

const B = preload("res://scripts/build.gd")

var main
var kind := "hen"             # hen, dog, cat
var loose := false            # one of Farmer Hobb's escaped hens
var home := Vector3.ZERO      # centre of where it likes to be
var home_r := 18.0            # how far it roams from home
var body: Node3D
var legs: Array = []
var head: Node3D
var tail: Node3D
var target := Vector3.ZERO
var speed := 0.0
var pause_t := 0.0
var t := 0.0
var step := 0.0
var sound_t := 0.0
var follow_t := 0.0


func _ready() -> void:
	add_to_group("animals")
	t = randf() * 10.0
	sound_t = randf_range(4.0, 12.0)
	match kind:
		"hen":
			build_hen()
		"dog":
			build_dog()
		_:
			build_cat()
	B.merge_children(body)
	B.blob_shadow(self, 0.18 if kind == "hen" else 0.3)
	pick_target()


# ------------------------------------------------------------------ models

func build_hen() -> void:
	body = Node3D.new()
	add_child(body)
	var feathers := B.paint_mat(Color(0.78, 0.45, 0.2) if loose else Color(0.95, 0.93, 0.88), "cloth", 50 if loose else 51)
	var red := B.mat(Color(0.85, 0.15, 0.12))
	var beak := B.mat(Color(0.95, 0.7, 0.2))
	var b := B.mesh(body, B.sphere(1.0, 9, 6), Vector3(0, 0.28, 0), feathers)
	b.scale = Vector3(0.16, 0.15, 0.21)
	var tl := B.mesh(body, B.prism(Vector3(0.14, 0.16, 0.06)), Vector3(0, 0.38, 0.17), feathers, Vector3(-30, 0, 0))
	tl.scale = Vector3.ONE
	head = Node3D.new()
	head.position = Vector3(0, 0.42, -0.14)
	body.add_child(head)
	B.mesh(head, B.sphere(0.075, 8, 5), Vector3.ZERO, feathers)
	B.mesh(head, B.prism(Vector3(0.025, 0.06, 0.06)), Vector3(0, 0.07, 0.0), red)
	B.mesh(head, B.prism(Vector3(0.03, 0.05, 0.03)), Vector3(0, -0.01, -0.08), beak, Vector3(-90, 0, 0))
	B.mesh(head, B.sphere(0.02, 5, 3), Vector3(0, -0.06, -0.04), red)
	for s in [-1, 1]:
		var leg := Node3D.new()
		leg.position = Vector3(s * 0.05, 0.17, 0)
		body.add_child(leg)
		B.mesh(leg, B.cyl(0.012, 0.012, 0.17, 4), Vector3(0, -0.085, 0), beak)
		legs.append(leg)


func build_dog() -> void:
	body = Node3D.new()
	add_child(body)
	var fur := B.paint_mat(Color(0.55, 0.36, 0.2), "hair", 52)
	var light := B.paint_mat(Color(0.86, 0.78, 0.64), "hair", 53)
	var dark := B.mat(Color(0.1, 0.08, 0.07))
	var torso := B.mesh(body, B.capsule(0.16, 0.62), Vector3(0, 0.38, 0), fur, Vector3(90, 0, 0))
	torso.scale = Vector3(1.0, 1.0, 1.05)
	head = Node3D.new()
	head.position = Vector3(0, 0.55, -0.38)
	body.add_child(head)
	B.mesh(head, B.sphere(0.13, 8, 6), Vector3.ZERO, fur)
	var snout := B.mesh(head, B.capsule(0.06, 0.18), Vector3(0, -0.03, -0.12), light, Vector3(90, 0, 0))
	snout.scale = Vector3.ONE
	B.mesh(head, B.sphere(0.03, 5, 3), Vector3(0, -0.01, -0.22), dark)
	for s in [-1, 1]:
		B.mesh(head, B.sphere(0.018, 5, 3), Vector3(s * 0.05, 0.04, -0.11), dark)
		var ear := B.mesh(head, B.prism(Vector3(0.07, 0.12, 0.03)), Vector3(s * 0.08, 0.1, 0.02), fur, Vector3(0, 0, -s * 25))
		ear.scale = Vector3.ONE
	tail = Node3D.new()
	tail.position = Vector3(0, 0.45, 0.36)
	body.add_child(tail)
	B.mesh(tail, B.cyl(0.025, 0.04, 0.26, 5), Vector3(0, 0.1, 0.06), fur, Vector3(35, 0, 0))
	for lz in [-0.24, 0.24]:
		for s in [-1, 1]:
			var leg := Node3D.new()
			leg.position = Vector3(s * 0.09, 0.28, lz)
			body.add_child(leg)
			B.mesh(leg, B.cyl(0.045, 0.04, 0.28, 5), Vector3(0, -0.14, 0), fur)
			B.mesh(leg, B.sphere(0.045, 5, 3), Vector3(0, -0.27, -0.02), light)
			legs.append(leg)


func build_cat() -> void:
	body = Node3D.new()
	add_child(body)
	var cols := [Color(0.45, 0.45, 0.46), Color(0.85, 0.55, 0.25), Color(0.15, 0.14, 0.14)]
	var fur := B.paint_mat(cols[randi() % cols.size()], "hair", 54)
	var pink := B.mat(Color(0.9, 0.6, 0.6))
	var torso := B.mesh(body, B.capsule(0.09, 0.42), Vector3(0, 0.25, 0), fur, Vector3(90, 0, 0))
	torso.scale = Vector3.ONE
	head = Node3D.new()
	head.position = Vector3(0, 0.36, -0.24)
	body.add_child(head)
	B.mesh(head, B.sphere(0.095, 8, 6), Vector3.ZERO, fur)
	for s in [-1, 1]:
		B.mesh(head, B.prism(Vector3(0.05, 0.08, 0.02)), Vector3(s * 0.05, 0.09, 0.0), fur)
		B.mesh(head, B.sphere(0.014, 5, 3), Vector3(s * 0.035, 0.015, -0.085), B.glow(Color(0.7, 0.85, 0.3)))
	B.mesh(head, B.sphere(0.012, 4, 3), Vector3(0, -0.015, -0.095), pink)
	tail = Node3D.new()
	tail.position = Vector3(0, 0.3, 0.24)
	body.add_child(tail)
	B.mesh(tail, B.cyl(0.018, 0.022, 0.32, 5), Vector3(0, 0.15, 0.04), fur, Vector3(15, 0, 0))
	for lz in [-0.15, 0.15]:
		for s in [-1, 1]:
			var leg := Node3D.new()
			leg.position = Vector3(s * 0.05, 0.2, lz)
			body.add_child(leg)
			B.mesh(leg, B.cyl(0.022, 0.02, 0.2, 4), Vector3(0, -0.1, 0), fur)
			legs.append(leg)


# ------------------------------------------------------------------ behaviour

func pick_target() -> void:
	var a := randf() * TAU
	var r := sqrt(randf()) * home_r
	target = home + Vector3(sin(a) * r, 0, cos(a) * r)
	pause_t = 0.0


func blocked(dir: Vector3) -> bool:
	var from := global_position + Vector3(0, 0.3, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 0.9, 1)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _physics_process(delta: float) -> void:
	t += delta
	var pl = main.player
	var to_pl: Vector3 = pl.global_position - global_position
	to_pl.y = 0
	var d_pl := to_pl.length()
	var want_speed := 0.0
	var dir := Vector3.ZERO
	var near_hero: bool = d_pl < 30.0 and absf(pl.global_position.y - global_position.y) < 5.0

	if kind == "hen" and loose and near_hero and d_pl < 3.2:
		# flap away from the hero
		dir = -to_pl.normalized()
		want_speed = 3.9
		pause_t = 0.0
		if sound_t > 1.0:
			sound_t = 0.0
			main.sfx.play_at("cluck", global_position)
	elif kind == "dog" and near_hero and d_pl > 3.0 and d_pl < 9.0 and follow_t > 0.0:
		dir = to_pl.normalized()
		want_speed = 4.6 if d_pl > 5.0 else 2.4
	else:
		var to_t := target - global_position
		to_t.y = 0
		if pause_t > 0.0:
			pause_t -= delta
		elif to_t.length() < 0.4:
			pause_t = randf_range(1.0, 4.0) if kind != "cat" else randf_range(4.0, 12.0)
			pick_target()
		else:
			dir = to_t.normalized()
			want_speed = {"hen": 1.3, "dog": 2.2, "cat": 0.9}[kind] * (1.6 if loose else 1.0)
	if kind == "dog":
		follow_t -= delta
		if d_pl < 6.0 and near_hero and follow_t < -6.0:
			follow_t = randf_range(6.0, 12.0)   # he takes a liking to the hero for a while
	if dir != Vector3.ZERO and blocked(dir):
		# turn aside along the obstacle
		var side := dir.rotated(Vector3.UP, PI * 0.5 * (1.0 if randf() < 0.5 else -1.0))
		dir = side if not blocked(side) else -dir
		if not loose:
			pick_target()
	speed = move_toward(speed, want_speed, delta * 8.0)
	if dir != Vector3.ZERO and speed > 0.05:
		var p := global_position + dir * speed * delta
		# stay near home (pen hens stay inside the pen, everyone stays in the village)
		var off := p - home
		off.y = 0
		if off.length() > home_r + 0.5:
			p = home + off.normalized() * (home_r + 0.5) + Vector3(0, p.y - home.y, 0)
			pick_target()
		global_position = p
		rotation.y = lerp_angle(rotation.y, B.yaw_of(dir), minf(1.0, 10.0 * delta))
	animate(delta)
	sound_t += delta
	if near_hero and d_pl < 12.0 and sound_t > 9.0 and randf() < delta * 0.25:
		sound_t = 0.0
		main.sfx.play_at({"hen": "cluck", "dog": "bark", "cat": "meow"}[kind], global_position)


func animate(delta: float) -> void:
	var moving := speed > 0.1
	step += delta * speed * (14.0 if kind == "hen" else 7.0)
	for i in legs.size():
		var leg: Node3D = legs[i]
		var ph := step + (PI if i % 2 == 1 else 0.0) + (PI * 0.5 if i >= 2 else 0.0)
		leg.rotation.x = sin(ph) * 0.6 if moving else lerpf(leg.rotation.x, 0.0, 10.0 * delta)
	match kind:
		"hen":
			# peck at the ground while standing about, bob while walking
			if moving:
				head.rotation.x = sin(step * 2.0) * 0.15
				body.position.y = absf(sin(step)) * 0.02
			else:
				var peck := maxf(0.0, sin(t * 2.3)) if fmod(t, 3.0) < 1.4 else 0.0
				head.rotation.x = peck * 0.9
				head.position.z = -0.14 - peck * 0.05
				head.position.y = 0.42 - peck * 0.12
		"dog":
			tail.rotation.y = sin(t * (14.0 if follow_t > 0.0 else 6.0)) * 0.6
			head.rotation.x = sin(t * 1.3) * 0.1 if not moving else sin(step) * 0.06
			body.position.y = absf(sin(step)) * 0.03 if moving else 0.0
		_:
			tail.rotation.z = sin(t * 1.5) * 0.4
			if not moving and pause_t > 2.0:
				body.position.y = lerpf(body.position.y, -0.08, 4.0 * delta)   # settle down to sit
			else:
				body.position.y = lerpf(body.position.y, 0.0, 6.0 * delta)


## Farmer Hobb's escaped hens can be grabbed when the hero gets close.
func catchable_by(p: Vector3) -> bool:
	var d := global_position - p
	d.y = 0
	return loose and d.length() < 1.4
