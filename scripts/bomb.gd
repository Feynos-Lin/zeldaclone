extends Node3D
## A lit bomb: held over the hero's head, thrown, bouncing and rolling, then a
## blast that hurts every zombie nearby (and the hero, if he's too close).

const B = preload("res://scripts/build.gd")
const MESH_PATH := "res://assets/items/bomb_mesh.res"
const FUSE := 3.4
const BLAST_R := 3.4

var main
var held := true
var vel := Vector3.ZERO
var fuse := FUSE
var radius := 0.16
var fuse_tip := Vector3(0.1, 0.3, 0.0)
var mat: ShaderMaterial
var spark: MeshInstance3D
var on_ground := false


func _ready() -> void:
	var mesh: ArrayMesh = load(MESH_PATH)
	var rig: Dictionary = mesh.get_meta("rig", {})
	radius = rig.get("radius", 0.16)
	var ft: Array = rig.get("fuse_tip", [0.1, 0.3, 0.0])
	fuse_tip = Vector3(ft[0], ft[1], ft[2])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mat = (mesh.surface_get_material(0) as ShaderMaterial).duplicate()
	mi.material_override = mat
	add_child(mi)
	spark = B.mesh(self, B.sphere(0.035, 6, 3), fuse_tip, B.glow(Color(1.0, 0.75, 0.3)))
	spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func throw(v: Vector3) -> void:
	held = false
	vel = v


func _physics_process(delta: float) -> void:
	fuse -= delta
	# fizzing spark, and the bomb flashes faster as the fuse burns down
	var rate := lerpf(4.0, 22.0, 1.0 - clampf(fuse / FUSE, 0.0, 1.0))
	spark.scale = Vector3.ONE * randf_range(0.6, 1.4)
	mat.set_shader_parameter("glow", 0.6 * maxf(0.0, sin(Time.get_ticks_msec() * 0.001 * rate)) if fuse < FUSE * 0.6 else 0.0)
	if fuse <= 0.0:
		explode()
		return
	if held:
		return
	vel.y -= 20.0 * delta
	var from := global_position
	var to := from + vel * delta
	var q := PhysicsRayQueryParameters3D.create(from, to + vel.normalized() * radius, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var n: Vector3 = hit.normal
		vel = vel.bounce(n) * 0.4
		if n.y > 0.6:
			vel.x *= 0.7
			vel.z *= 0.7
			if absf(vel.y) < 1.0:
				vel.y = 0.0
				on_ground = true
		to = hit.position + n * radius
	if to.y < radius:
		to.y = radius
		if vel.y < 0.0:
			vel.y = -vel.y * 0.35 if vel.y < -1.5 else 0.0
		vel.x *= 0.92
		vel.z *= 0.92
	global_position = to
	if Vector2(vel.x, vel.z).length() > 0.05:
		rotate(Vector3(vel.z, 0, -vel.x).normalized(), Vector2(vel.x, vel.z).length() * delta / radius)


func explode() -> void:
	var p := global_position
	main.sfx.play_at("boom", p)
	var pl = main.player
	var dist_pl: float = pl.global_position.distance_to(p)
	main.cam_rig.shake(clampf(0.6 - dist_pl * 0.04, 0.12, 0.6))
	main.controls.rumble(0.8, 1.0, 0.35 if dist_pl < 8.0 else 0.15)
	for z in get_tree().get_nodes_in_group("zombies"):
		if not z.is_alive():
			continue
		var to: Vector3 = z.global_position - p
		to.y = 0
		if to.length() < BLAST_R:
			z.take_hit(3, to.normalized() if to.length() > 0.05 else Vector3.FORWARD)
	if dist_pl < BLAST_R * 0.75 and pl.is_alive():
		var d: Vector3 = pl.global_position - p
		d.y = 0
		pl.take_damage(2, d if d.length() > 0.05 else Vector3.BACK)
	if held and pl.held_bomb == self:
		pl.held_bomb = null
	_fireball(p)
	queue_free()


func _fireball(p: Vector3) -> void:
	var parent := get_parent()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.7, 0.3, 0.9)
	m.disable_fog = true
	var ball := MeshInstance3D.new()
	ball.mesh = B.sphere(0.5, 14, 8)
	ball.material_override = m
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(ball)
	ball.global_position = p + Vector3(0, 0.3, 0)
	ball.scale = Vector3.ONE * 0.4
	var smoke_m := m.duplicate()
	smoke_m.albedo_color = Color(0.25, 0.23, 0.22, 0.6)
	var smoke := MeshInstance3D.new()
	smoke.mesh = B.sphere(0.5, 12, 6)
	smoke.material_override = smoke_m
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(smoke)
	smoke.global_position = p + Vector3(0, 0.5, 0)
	smoke.scale = Vector3.ONE * 0.6
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.35)
	light.light_energy = 6.0
	light.omni_range = 9.0
	parent.add_child(light)
	light.global_position = p + Vector3(0, 0.8, 0)
	var tw := ball.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ball, "scale", Vector3.ONE * BLAST_R * 1.6, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.35)
	tw.tween_property(light, "light_energy", 0.0, 0.4)
	tw.tween_property(smoke, "scale", Vector3.ONE * BLAST_R * 1.3, 1.2).set_ease(Tween.EASE_OUT)
	tw.tween_property(smoke, "position:y", smoke.position.y + 1.5, 1.2)
	tw.tween_property(smoke_m, "albedo_color:a", 0.0, 1.2)
	tw.chain().tween_callback(func():
		ball.queue_free()
		smoke.queue_free()
		light.queue_free())
