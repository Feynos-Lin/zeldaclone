extends Node3D
## Lazy-follow third-person camera with lock-on framing, recenter,
## wall collision, screen shake, and the big pale moon that hangs in the sky.

const B = preload("res://scripts/build.gd")

var main
var player
var cam: Camera3D
var yaw := 0.0
var pitch := -0.3
var distance := 6.2
var height := 1.5
var focus := Vector3.ZERO
var recentering := false
var recenter_yaw := 0.0
var shake_time := 0.0
var moon: MeshInstance3D
var manual_cooldown := 0.0


func _ready() -> void:
	process_physics_priority = 10
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.1
	cam.far = 95.0
	add_child(cam)
	cam.current = true
	var mm := B.glow(Color(0.93, 0.91, 0.82))
	mm.disable_fog = true
	moon = B.mesh(self, B.sphere(5.5, 10, 6), Vector3.ZERO, mm)
	var crater := B.glow(Color(0.8, 0.78, 0.68))
	crater.disable_fog = true
	B.mesh(moon, B.sphere(1.2, 6, 4), Vector3(1.8, 1.4, -4.6), crater)
	B.mesh(moon, B.sphere(0.9, 6, 4), Vector3(-2.0, -1.2, -4.8), crater)
	B.mesh(moon, B.sphere(0.7, 6, 4), Vector3(-0.6, 2.3, -4.7), crater)


func snap() -> void:
	focus = player.global_position + Vector3(0, height, 0)


func recenter(dir: Vector3) -> void:
	recenter_yaw = B.yaw_of(dir)
	recentering = true


func shake(amount: float) -> void:
	shake_time = maxf(shake_time, amount)


func _physics_process(delta: float) -> void:
	var turn := Input.get_axis("cam_left", "cam_right")
	var touch = main.touch
	if touch != null and touch.cam_drag != 0.0:
		yaw -= touch.cam_drag * 0.014
		touch.cam_drag = 0.0
		manual_cooldown = 1.5
		recentering = false
	if absf(turn) > 0.05:
		yaw -= turn * 2.4 * delta
		manual_cooldown = 1.5
		recentering = false
	manual_cooldown = maxf(manual_cooldown - delta, 0.0)

	var tgt = player.target
	if tgt != null and is_instance_valid(tgt):
		var to: Vector3 = tgt.global_position - player.global_position
		to.y = 0
		if to.length() > 0.2:
			yaw = lerp_angle(yaw, B.yaw_of(to), 7.0 * delta)
	elif recentering:
		yaw = lerp_angle(yaw, recenter_yaw, 10.0 * delta)
		if absf(angle_difference(yaw, recenter_yaw)) < 0.02:
			recentering = false
	elif manual_cooldown <= 0.0 and player.state == "move":
		# Lazy follow: drift behind the hero when running away from the camera.
		var v := Vector3(player.velocity.x, 0, player.velocity.z)
		if v.length() > 1.0:
			var face_yaw := B.yaw_of(v)
			if absf(angle_difference(yaw, face_yaw)) < 1.9:
				yaw = lerp_angle(yaw, face_yaw, 0.9 * delta)

	var want: Vector3 = player.global_position + Vector3(0, height, 0)
	focus = focus.lerp(want, minf(1.0, 10.0 * delta))
	var p := pitch - (0.08 if tgt != null else 0.0)
	var back := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, p) * Vector3(0, 0, 1)
	var desired := focus + back * distance

	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(focus, desired, 1)
	var hit := space.intersect_ray(q)
	if not hit.is_empty():
		desired = hit.position + (focus - hit.position).normalized() * 0.35

	var offset := Vector3.ZERO
	if shake_time > 0.0:
		shake_time -= delta
		offset = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.12
	cam.global_position = desired + offset
	cam.look_at(focus + Vector3(0, 0.2, 0), Vector3.UP)

	# The moon: always far away, huge, rising and setting with the clock.
	var hour: float = main.time_of_day
	var night_t := fposmod(hour - 18.0, 24.0) / 13.0   # 18:00 -> 0, 07:00 -> 1
	moon.visible = night_t < 1.0
	if moon.visible:
		var elev := sin(night_t * PI) * 0.75 + 0.08
		var dir := Vector3(0.35, elev, 1.0).normalized()
		moon.global_position = cam.global_position + dir * 80.0
		moon.look_at(cam.global_position, Vector3.UP)
