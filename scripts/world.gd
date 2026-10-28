extends RefCounted
## Builds the forest world: Wrenmoor's clearing (no walls, just a ring of
## ward-stones), timber-and-thatch cottages, painted woods, a winding trail
## north to a rocky hill, and Hollow Cave at the top of it.

const B = preload("res://scripts/build.gd")

const TOWN_R := 22.0
const WARD_R := 27.0
const MIN_X := -46.0
const MAX_X := 46.0
const MIN_Z := -42.0
const MAX_Z := 114.0
const PATH_N := [Vector3(0, 0, 6), Vector3(0, 0, 24), Vector3(-5, 0, 38), Vector3(-7, 0, 52), Vector3(-1, 0, 66), Vector3(7, 0, 80), Vector3(8, 0, 96), Vector3(8, 0, 114)]
const PATH_W := [Vector3(-6, 0, -1), Vector3(-22, 0, -6), Vector3(-34, 0, -13), Vector3(-52, 0, -18)]
const CAVE_CLEARING := Vector3(8, 0, 95)
const CAVE_MOUTH := Vector3(8, 0, 109)
const LAYER_TREES := 4

var main
var world: Node3D
var rng := RandomNumberGenerator.new()
var trunks := []
var blobs := []
var cones := []
var tufts := []
var flowers := []
var stems := []
var caps := []
var tree_body: StaticBody3D
var tree_spots := []
var detail_nodes := []   # grass, flowers, mushrooms: draw distance follows the Graphics setting
var tree_nodes := []     # forest chunks: draw distance follows the Graphics setting


func build(m) -> void:
	main = m
	world = m.world
	rng.seed = 2024
	tree_body = StaticBody3D.new()
	tree_body.collision_layer = LAYER_TREES
	tree_body.collision_mask = 0
	world.add_child(tree_body)
	build_town()
	build_ward_ring()
	build_cave()
	build_forest()
	build_decor()
	build_ground()
	build_bounds()
	flush_all()
	merge_static()


# ------------------------------------------------------------------ helpers

func dist_to_polyline(p: Vector3, pts: Array) -> float:
	var best := 1e9
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, Vector2(p.x - (a.x + ab.x * t), p.z - (a.z + ab.z * t)).length())
	return best


func dist_to_path(p: Vector3) -> float:
	return minf(dist_to_polyline(p, PATH_N), dist_to_polyline(p, PATH_W))


func flat_len(p: Vector3) -> float:
	return Vector2(p.x, p.z).length()


func in_bounds(p: Vector3, margin: float = 0.0) -> bool:
	return p.x > MIN_X - margin and p.x < MAX_X + margin and p.z > MIN_Z - margin and p.z < MAX_Z + margin


func add_collider_cyl(p: Vector3, radius: float, height: float, body: StaticBody3D = null) -> void:
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = height
	cs.shape = sh
	cs.position = p + Vector3(0, height * 0.5, 0)
	(body if body != null else tree_body).add_child(cs)


func xf(pos: Vector3, scale: Vector3, yaw: float = 0.0, tilt: Vector3 = Vector3.ZERO) -> Transform3D:
	var b: Basis = Basis.from_euler(Vector3(tilt.x, yaw, tilt.z)) if tilt != Vector3.ZERO else Basis(Vector3.UP, yaw)
	return Transform3D(b * Basis.from_scale(scale), pos)


## Batches instances into 24 m chunks so off-screen and far-away parts of the
## forest are culled instead of drawn every frame.
func flush(mesh: Mesh, mat: Material, items: Array, view_range: float = 64.0, detail: bool = false, shadows: bool = true) -> void:
	var groups := {}
	for it in items:
		var o: Vector3 = (it[0] as Transform3D).origin
		var key := Vector2i(floori(o.x / 24.0), floori(o.z / 24.0))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(it)
	for key in groups:
		var list: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i][0])
			mm.set_instance_color(i, list[i][1])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = view_range
		mmi.visibility_range_end_margin = 6.0
		world.add_child(mmi)
		if detail:
			detail_nodes.append(mmi)
		else:
			tree_nodes.append(mmi)


func vc_mat(tex_color: Color, kind: String, seed_value: int = 7, double_sided: bool = false) -> StandardMaterial3D:
	var m := B.paint_mat(tex_color, kind, seed_value)
	m.vertex_color_use_as_albedo = true
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func tuft_mesh() -> ArrayMesh:
	# Three crossed blades of grass.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := k * PI / 3.0
		var d := Vector3(cos(a), 0, sin(a)) * 0.16
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0, 1))
		st.add_vertex(-d)
		st.set_uv(Vector2(1, 1))
		st.add_vertex(d)
		st.set_uv(Vector2(0.5, 0))
		st.add_vertex(Vector3(d.z * 0.4, 0.38, -d.x * 0.4))
	return st.commit()


func flush_all() -> void:
	var white := Color(0.95, 0.95, 0.95)
	flush(B.cyl(0.62, 1.0, 1.0, 8), vc_mat(white, "hair", 51), trunks)
	flush(B.sphere(1.0, 10, 6), vc_mat(white, "leaf", 52), blobs)
	flush(B.cyl(0.0, 1.0, 1.0, 8), vc_mat(white, "leaf", 53), cones)
	flush(tuft_mesh(), vc_mat(white, "grass", 54, true), tufts, 40.0, true, false)
	flush(B.sphere(1.0, 6, 4), vc_mat(white, "skin", 55), flowers, 36.0, true, false)
	flush(B.cyl(0.7, 1.0, 1.0, 7), vc_mat(white, "skin", 56), stems, 36.0, true, false)
	flush(B.sphere(1.0, 8, 5), vc_mat(white, "leaf", 57), caps, 36.0, true, false)


# ------------------------------------------------------------------ ground

func ground_height(p: Vector3) -> float:
	var dx := maxf(maxf(MIN_X - 3.0 - p.x, p.x - MAX_X - 3.0), 0.0)
	var dz := maxf(maxf(MIN_Z - 3.0 - p.z, p.z - MAX_Z - 3.0), 0.0)
	var d := maxf(dx, dz)
	if d <= 0.0:
		return 0.0
	var bumps := sin(p.x * 0.21) * 1.4 + sin(p.z * 0.17 + 2.0) * 1.2
	return minf(d * d * 0.05 + d * 0.5, 16.0) + bumps * clampf(d / 6.0, 0.0, 1.0)


func ground_color(p: Vector3) -> Color:
	var n := (sin(p.x * 0.13) + sin(p.z * 0.17 + 1.0) + sin((p.x + p.z) * 0.071) + sin(p.x * 0.41 - p.z * 0.37) * 0.5) / 3.5
	var grass := Color(0.42, 0.6, 0.28).lerp(Color(0.56, 0.66, 0.3) if n > 0.0 else Color(0.3, 0.48, 0.25), absf(n))
	var town_d := flat_len(p)
	var forest := clampf((town_d - 26.0) / 8.0, 0.0, 1.0)
	forest *= clampf(p.distance_to(CAVE_CLEARING) / 6.0 - 1.6, 0.0, 1.0)
	var floor_col := Color(0.3, 0.42, 0.22).lerp(Color(0.44, 0.36, 0.22), clampf(n * 0.5 + 0.5, 0.0, 1.0) * 0.6)
	var col := grass.lerp(floor_col, forest * 0.75)
	# Packed dirt in the village square
	col = col.lerp(Color(0.66, 0.56, 0.4), 1.0 - smoothstep(7.0, 11.0, town_d))
	# Dead, trampled ground before the cave
	var cave_d := p.distance_to(CAVE_CLEARING)
	col = col.lerp(Color(0.46, 0.45, 0.3), (1.0 - smoothstep(8.0, 15.0, cave_d)) * 0.7)
	# Trails
	var pd := dist_to_path(p)
	col = col.lerp(Color(0.63, 0.5, 0.34), 1.0 - smoothstep(1.3, 2.9, pd))
	# Hills beyond the woods
	var h := ground_height(p)
	if h > 0.5:
		col = col.lerp(Color(0.38, 0.5, 0.3), clampf(h / 8.0, 0.0, 0.6))
	return col


func build_ground() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var x0 := -84.0
	var z0 := -76.0
	var step := 1.5
	var nx := int(168.0 / step)
	var nz := int(232.0 / step)
	for j in nz + 1:
		for i in nx + 1:
			var p := Vector3(x0 + i * step, 0, z0 + j * step)
			st.set_color(ground_color(p))
			st.set_uv(Vector2(p.x, p.z) * 0.22)
			st.add_vertex(Vector3(p.x, ground_height(p), p.z))
	for j in nz:
		for i in nx:
			var a := j * (nx + 1) + i
			var c := a + nx + 1
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(c)
			st.add_index(a + 1)
			st.add_index(c + 1)
			st.add_index(c)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.set_meta("no_merge", true)
	mi.material_override = vc_mat(Color(0.95, 0.95, 0.95), "grass", 60)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)

	var ground := StaticBody3D.new()
	world.add_child(ground)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(200, 1, 260)
	cs.shape = sh
	cs.position = Vector3(0, -0.5, 36)
	ground.add_child(cs)


func build_bounds() -> void:
	# Invisible edges of the woods (the camera passes through them).
	var walls := StaticBody3D.new()
	walls.collision_layer = LAYER_TREES
	walls.collision_mask = 0
	world.add_child(walls)
	for w in [
		[Vector3(2, 10, MAX_Z - MIN_Z + 10), Vector3(MIN_X - 1, 5, (MIN_Z + MAX_Z) * 0.5)],
		[Vector3(2, 10, MAX_Z - MIN_Z + 10), Vector3(MAX_X + 1, 5, (MIN_Z + MAX_Z) * 0.5)],
		[Vector3(MAX_X - MIN_X + 10, 10, 2), Vector3(0, 5, MIN_Z - 1)],
	]:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = w[0]
		cs.shape = sh
		cs.position = w[1]
		walls.add_child(cs)


# ------------------------------------------------------------------ trees

func add_tree(p: Vector3, s: float, kind: String = "", collide: bool = true) -> void:
	if kind == "":
		kind = "pine" if rng.randf() < 0.28 else "oak"
	var yaw := rng.randf() * TAU
	var bark := Color(0.5, 0.36, 0.24).lerp(Color(0.38, 0.3, 0.24), rng.randf())
	if kind == "oak":
		var h := 2.4 * s
		var r := 0.32 * s
		trunks.append([xf(p + Vector3(0, h * 0.5, 0), Vector3(r, h, r), yaw), bark])
		trunks.append([xf(p + Vector3(0, 0.15 * s, 0), Vector3(r * 1.5, 0.3 * s, r * 1.5), yaw), bark.darkened(0.1)])
		var leaf: Color
		var roll := rng.randf()
		if roll < 0.08:
			leaf = Color(0.85, 0.55, 0.22)
		elif roll < 0.14:
			leaf = Color(0.75, 0.7, 0.28)
		else:
			leaf = Color(0.36, 0.56, 0.26).lerp(Color(0.24, 0.44, 0.24), rng.randf())
		blobs.append([xf(p + Vector3(0, h + 0.8 * s, 0), Vector3(1.9, 1.45, 1.9) * s, yaw), leaf])
		for k in 2:
			var a := yaw + k * PI + rng.randf_range(-0.5, 0.5)
			var o := Vector3(cos(a), 0, sin(a)) * 1.15 * s
			blobs.append([xf(p + o + Vector3(0, h + 0.2 * s, 0), Vector3(1.3, 1.05, 1.3) * s * rng.randf_range(0.85, 1.1), a), leaf.darkened(0.06)])
		blobs.append([xf(p + Vector3(0.2, h + 1.8 * s, -0.1) * Vector3(s, 1, s), Vector3(1.15, 0.95, 1.15) * s, yaw), leaf.lightened(0.08)])
		if collide:
			add_collider_cyl(p, r * 1.25, h)
	elif kind == "pine":
		var h := 1.6 * s
		var r := 0.26 * s
		trunks.append([xf(p + Vector3(0, h * 0.5, 0), Vector3(r, h, r), yaw), bark])
		var green := Color(0.2, 0.42, 0.32).lerp(Color(0.16, 0.34, 0.26), rng.randf())
		for k in 3:
			var cr := (1.7 - k * 0.42) * s
			var ch := (2.0 - k * 0.3) * s
			cones.append([xf(p + Vector3(0, h + k * 1.05 * s + ch * 0.5 - 0.2 * s, 0), Vector3(cr, ch, cr), yaw + k), green.lightened(k * 0.05)])
		if collide:
			add_collider_cyl(p, r * 1.3, h)
	elif kind == "dead":
		var h := 3.0 * s
		var col := Color(0.42, 0.38, 0.34)
		trunks.append([xf(p + Vector3(0, h * 0.5, 0), Vector3(0.24, h, 0.24) * Vector3(s, 1, s), yaw), col])
		for k in 3:
			var a := yaw + k * 2.1
			var tilt := Vector3(0.9, 0, 0)
			var bp := p + Vector3(cos(a) * 0.35, h * (0.55 + k * 0.13), sin(a) * 0.35) * Vector3(s, 1, s)
			var bt := Transform3D(Basis(Vector3.UP, -a + PI * 0.5) * Basis(Vector3.RIGHT, 0.95) * Basis.from_scale(Vector3(0.09, 1.2, 0.09) * s), bp)
			trunks.append([bt, col.darkened(0.05)])
		if collide:
			add_collider_cyl(p, 0.3 * s, h)


func build_forest() -> void:
	var step := 4.8
	var z := MIN_Z - 12.0
	while z < MAX_Z + 6.0:
		var x := MIN_X - 12.0
		while x < MAX_X + 12.0:
			var p := Vector3(x + rng.randf_range(-1.7, 1.7), 0, z + rng.randf_range(-1.7, 1.7))
			x += step
			var td := flat_len(p)
			if td < WARD_R + 3.0 + rng.randf_range(0.0, 3.0):
				continue
			if dist_to_path(p) < 3.0:
				continue
			if p.distance_to(CAVE_CLEARING) < 13.0 or (p.z > 98.0 and absf(p.x - CAVE_MOUTH.x) < 12.0):
				continue
			if p.z > MAX_Z - 2.0 and absf(p.x) < 50.0:
				continue
			var inside := in_bounds(p, -1.0)
			var s := rng.randf_range(0.85, 1.3) * (1.0 if inside else rng.randf_range(1.1, 1.5))
			p.y = ground_height(p) - 0.2
			add_tree(p, s, "", inside)
			tree_spots.append(p)
		z += step
	# A few gnarled oaks on the edge of the clearing
	for a in [35.0, 150.0, 205.0, 280.0]:
		var r := deg_to_rad(a)
		add_tree(Vector3(sin(r) * 24.5, 0, cos(r) * 24.5), 1.2, "oak")


# ------------------------------------------------------------------ village

func add_lantern(p: Vector3) -> void:
	var post := B.paint_mat(Color(0.3, 0.22, 0.16), "leather")
	B.solid_cylinder(world, 0.15, 2.8, p)
	B.mesh(world, B.cyl(0.08, 0.11, 2.8, 6), p + Vector3(0, 1.4, 0), post)
	B.mesh(world, B.box_mesh(Vector3(0.12, 0.12, 0.6)), p + Vector3(0, 2.75, -0.25), post)
	var lamp := B.glow(Color(1.0, 0.78, 0.4))
	B.mesh(world, B.box_mesh(Vector3(0.3, 0.36, 0.3)), p + Vector3(0, 2.45, -0.5), lamp)
	B.mesh(world, B.prism(Vector3(0.42, 0.22, 0.42)), p + Vector3(0, 2.74, -0.5), post)
	var light := OmniLight3D.new()
	light.position = p + Vector3(0, 2.4, -0.5)
	light.light_color = Color(1.0, 0.72, 0.4)
	light.omni_range = 9.0
	light.omni_attenuation = 1.2
	world.add_child(light)
	main.lanterns.append([light, 1.6, 0.05])


func build_town() -> void:
	var houses := [
		[40.0, 15.0, 6.4, 5.6, 3.4, Color(0.9, 0.84, 0.7)],
		[88.0, 16.0, 7.0, 6.0, 3.6, Color(0.86, 0.8, 0.66)],
		[135.0, 15.5, 6.0, 5.4, 3.2, Color(0.92, 0.86, 0.74)],
		[180.0, 17.0, 8.4, 6.0, 4.0, Color(0.84, 0.78, 0.66)],
		[222.0, 15.5, 6.2, 5.6, 3.4, Color(0.9, 0.82, 0.68)],
		[302.0, 15.0, 6.0, 5.2, 3.2, Color(0.88, 0.84, 0.72)],
		[333.0, 16.5, 5.6, 5.0, 3.2, Color(0.9, 0.86, 0.76)],
	]
	for h in houses:
		var a := deg_to_rad(float(h[0]))
		build_cottage(Vector3(sin(a) * h[1], 0, cos(a) * h[1]), h[2], h[3], h[4], h[5])

	# The great tree in the square, with a bench around it
	add_tree(Vector3(-3, 0, -4), 1.75, "oak")
	var bench := B.paint_mat(Color(0.52, 0.36, 0.22), "leather")
	B.mesh(world, B.cyl(1.25, 1.25, 0.1, 10), Vector3(-3, 0.45, -4), bench)
	B.mesh(world, B.cyl(1.0, 1.0, 0.45, 10), Vector3(-3, 0.22, -4), B.paint_mat(Color(0.42, 0.3, 0.2), "leather"))

	# Well
	var stone := B.paint_mat(Color(0.62, 0.6, 0.56), "stone", 3)
	var wood := B.paint_mat(Color(0.48, 0.33, 0.2), "leather", 4)
	var thatch := B.paint_mat(Color(0.78, 0.64, 0.36), "hair", 5)
	var well := Vector3(6, 0, 2)
	B.solid_cylinder(world, 1.2, 1.0, well)
	B.mesh(world, B.cyl(1.15, 1.25, 0.9, 10), well + Vector3(0, 0.45, 0), stone)
	B.mesh(world, B.cyl(0.95, 0.95, 0.04, 10), well + Vector3(0, 0.88, 0), B.glow(Color(0.05, 0.08, 0.15)))
	for wx in [-1.0, 1.0]:
		B.mesh(world, B.box_mesh(Vector3(0.16, 2.1, 0.16)), well + Vector3(wx, 1.6, 0), wood)
	B.mesh(world, B.cyl(0.06, 0.06, 2.1, 6), well + Vector3(0, 2.3, 0), wood, Vector3(0, 0, 90))
	B.mesh(world, B.prism(Vector3(2.8, 1.0, 2.0)), well + Vector3(0, 3.0, 0), thatch)

	# Market stall with a striped awning
	var stall := Vector3(10, 0, -7.5)
	B.solid_box(world, Vector3(3.2, 0.95, 1.3), stall + Vector3(0, 0.475, 0), wood)
	for sx in [-1.45, 1.45]:
		B.mesh(world, B.box_mesh(Vector3(0.13, 2.5, 0.13)), stall + Vector3(sx, 1.25, 0.6), wood)
	for i in 5:
		var col := Color(0.82, 0.3, 0.25) if i % 2 == 0 else Color(0.92, 0.86, 0.72)
		B.mesh(world, B.box_mesh(Vector3(0.72, 0.06, 2.0)), stall + Vector3(-1.45 + i * 0.725, 2.45, 0.2), B.paint_mat(col, "cloth", 70 + i), Vector3(14, 0, 0))
	for i in 4:
		B.mesh(world, B.sphere(0.17, 7, 4), stall + Vector3(-1.0 + i * 0.66, 1.1, -0.1), B.paint_mat([Color(0.85, 0.25, 0.18), Color(0.95, 0.65, 0.15), Color(0.45, 0.65, 0.22), Color(0.62, 0.3, 0.5)][i], "skin"))

	# Garden plots with fences
	for g in [[Vector3(-12, 0, 9), 0.5], [Vector3(13, 0, 10), -0.6]]:
		build_garden(g[0], g[1])

	# Crates, barrels, a haystack
	for c in [Vector3(12.3, 0, -9.2), Vector3(12.9, 0, -8.0), Vector3(-9.5, 0, -11), Vector3(4, 0, 13.5)]:
		B.solid_box(world, Vector3(0.9, 0.9, 0.9), c + Vector3(0, 0.45, 0), wood, rng.randf_range(0, 40))
	for b in [Vector3(-10.4, 0, -10.2), Vector3(9.4, 0, 12.4), Vector3(-14, 0, -2)]:
		B.solid_cylinder(world, 0.42, 1.0, b)
		B.mesh(world, B.cyl(0.4, 0.42, 1.0, 9), b + Vector3(0, 0.5, 0), wood)
		B.mesh(world, B.cyl(0.43, 0.43, 0.06, 9), b + Vector3(0, 0.75, 0), B.paint_mat(Color(0.45, 0.44, 0.42), "metal"))
	var hay := B.mesh(world, B.sphere(1.0, 9, 5), Vector3(-15, 0.5, -6.5), thatch)
	hay.scale = Vector3(1.2, 0.85, 1.0)
	add_collider_cyl(Vector3(-15, 0, -6.5), 1.1, 1.4)

	add_lantern(Vector3(-2.6, 0, 20.5))
	add_lantern(Vector3(2.6, 0, 20.5))
	add_lantern(Vector3(0, 0, -11))
	add_lantern(Vector3(-9, 0, 4))
	add_lantern(Vector3(10, 0, 4))


func build_cottage(p: Vector3, w: float, d: float, h: float, plaster_col: Color) -> void:
	var root := Node3D.new()
	root.position = p
	root.rotation.y = atan2(-p.x, -p.z)
	world.add_child(root)
	var plaster := B.paint_mat(plaster_col, "skin", int(p.x * 7.0))
	var beam := B.paint_mat(Color(0.36, 0.24, 0.15), "leather", 8)
	var stone := B.paint_mat(Color(0.58, 0.56, 0.52), "stone", 9)
	var thatch := B.paint_mat(Color(0.8, 0.66, 0.38), "hair", 10)
	B.solid_box(root, Vector3(w, h, d), Vector3(0, h * 0.5, 0), plaster)
	B.mesh(root, B.box_mesh(Vector3(w + 0.16, 0.6, d + 0.16)), Vector3(0, 0.3, 0), stone)
	# Timber frame: corner posts, a mid rail and braces on the front
	for cx in [-w * 0.5, w * 0.5]:
		for cz in [-d * 0.5, d * 0.5]:
			B.mesh(root, B.box_mesh(Vector3(0.22, h, 0.22)), Vector3(cx, h * 0.5, cz), beam)
	B.mesh(root, B.box_mesh(Vector3(w + 0.1, 0.18, 0.08)), Vector3(0, h * 0.55, d * 0.5 + 0.03), beam)
	B.mesh(root, B.box_mesh(Vector3(w + 0.1, 0.18, 0.08)), Vector3(0, h - 0.1, d * 0.5 + 0.03), beam)
	B.mesh(root, B.box_mesh(Vector3(0.08, 0.18, d + 0.1)), Vector3(w * 0.5 + 0.03, h * 0.55, 0), beam)
	B.mesh(root, B.box_mesh(Vector3(0.08, 0.18, d + 0.1)), Vector3(-w * 0.5 - 0.03, h * 0.55, 0), beam)
	for side in [-1, 1]:
		var brace := B.mesh(root, B.box_mesh(Vector3(0.14, h * 0.55, 0.06)), Vector3(side * w * 0.36, h * 0.77, d * 0.5 + 0.04), beam)
		brace.rotation.z = 0.7 * side
	# Thick thatched roof with a deep overhang and a ridge
	var roof := B.mesh(root, B.prism(Vector3(d + 1.6, 2.3, w + 1.2)), Vector3(0, h + 1.05, 0), thatch)
	roof.rotation.y = PI * 0.5
	B.mesh(root, B.cyl(0.2, 0.2, w + 1.2, 7), Vector3(0, h + 2.18, 0), thatch.duplicate(), Vector3(0, 0, 90))
	# Door with an arched top
	B.mesh(root, B.box_mesh(Vector3(1.1, 1.75, 0.12)), Vector3(0, 0.875 + 0.05, d * 0.5 + 0.05), beam)
	B.mesh(root, B.cyl(0.55, 0.55, 0.12, 10), Vector3(0, 1.8, d * 0.5 + 0.05), beam, Vector3(90, 0, 0))
	B.mesh(root, B.sphere(0.05, 6, 3), Vector3(0.35, 1.0, d * 0.5 + 0.13), B.paint_mat(Color(0.6, 0.55, 0.4), "metal"))
	# Glowing windows with shutters and flower boxes
	var win := B.glow(Color(1.0, 0.82, 0.48))
	main.window_mats.append(win)
	for wx in [-w * 0.3, w * 0.3]:
		B.mesh(root, B.box_mesh(Vector3(0.8, 0.75, 0.1)), Vector3(wx, h * 0.33 + 0.55, d * 0.5 + 0.04), win)
		B.mesh(root, B.box_mesh(Vector3(0.06, 0.75, 0.12)), Vector3(wx, h * 0.33 + 0.55, d * 0.5 + 0.08), beam)
		for sx in [-0.55, 0.55]:
			B.mesh(root, B.box_mesh(Vector3(0.32, 0.85, 0.06)), Vector3(wx + sx, h * 0.33 + 0.55, d * 0.5 + 0.08), B.paint_mat(Color(0.3, 0.42, 0.36), "leather", 11))
		B.mesh(root, B.box_mesh(Vector3(0.9, 0.18, 0.25)), Vector3(wx, h * 0.33 + 0.1, d * 0.5 + 0.15), beam)
		for f in 4:
			var fc := [Color(0.95, 0.4, 0.4), Color(0.95, 0.85, 0.3), Color(0.8, 0.5, 0.9), Color(1, 1, 1)][(f + int(p.x)) % 4] as Color
			flowers.append([xf(root.transform * Vector3(wx - 0.3 + f * 0.2, h * 0.33 + 0.28, d * 0.5 + 0.15), Vector3.ONE * 0.07), fc])
	# Stone chimney
	B.mesh(root, B.box_mesh(Vector3(0.7, h + 1.6, 0.7)), Vector3(w * 0.32, (h + 1.6) * 0.5 + 0.6, -d * 0.25), stone)


func build_garden(p: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = p
	root.rotation.y = yaw
	world.add_child(root)
	var wood := B.paint_mat(Color(0.55, 0.4, 0.25), "leather", 12)
	B.mesh(root, B.box_mesh(Vector3(4.0, 0.08, 3.0)), Vector3(0, 0.04, 0), B.paint_mat(Color(0.42, 0.3, 0.2), "stone", 13))
	for i in 3:
		for k in 5:
			B.mesh(root, B.sphere(0.2, 6, 3), Vector3(-1.6 + k * 0.8, 0.18, -0.9 + i * 0.9), B.paint_mat(Color(0.35, 0.6, 0.25), "leaf", 14))
	for e in [[Vector3(0, 0, -1.7), 4.6, 0.0], [Vector3(0, 0, 1.7), 4.6, 0.0], [Vector3(-2.3, 0, 0), 3.4, PI * 0.5], [Vector3(2.3, 0, 0), 3.4, PI * 0.5]]:
		var seg := Node3D.new()
		seg.position = e[0]
		seg.rotation.y = e[2]
		root.add_child(seg)
		var n := int(e[1] / 0.9)
		for i in n + 1:
			B.mesh(seg, B.box_mesh(Vector3(0.1, 0.8, 0.1)), Vector3(-e[1] * 0.5 + i * e[1] / n, 0.4, 0), wood)
		B.mesh(seg, B.box_mesh(Vector3(e[1], 0.08, 0.05)), Vector3(0, 0.6, 0), wood)
		B.mesh(seg, B.box_mesh(Vector3(e[1], 0.08, 0.05)), Vector3(0, 0.3, 0), wood)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(4.7, 1.0, 3.5)
	cs.shape = sh
	var body := StaticBody3D.new()
	body.position = p + Vector3(0, 0.5, 0)
	body.rotation.y = yaw
	body.add_child(cs)
	world.add_child(body)


func build_ward_ring() -> void:
	var stone := B.paint_mat(Color(0.6, 0.62, 0.62), "stone", 21)
	var moss := B.paint_mat(Color(0.35, 0.52, 0.28), "leaf", 22)
	var rune := B.glow(Color(0.45, 0.95, 1.0))
	var a := 0.0
	while a < 360.0:
		var r := deg_to_rad(a)
		var p := Vector3(sin(r) * WARD_R, 0, cos(r) * WARD_R)
		a += 12.0
		if dist_to_path(p) < 2.6:
			continue
		var s := rng.randf_range(0.9, 1.15)
		var root := Node3D.new()
		root.position = p
		root.rotation.y = atan2(-p.x, -p.z)
		root.rotation.z = rng.randf_range(-0.06, 0.06)
		world.add_child(root)
		B.mesh(root, B.cyl(0.28, 0.42, 1.6 * s, 6), Vector3(0, 0.8 * s, 0), stone)
		var top := B.mesh(root, B.sphere(1.0, 7, 4), Vector3(0, 1.62 * s, 0), moss)
		top.scale = Vector3(0.32, 0.12, 0.32)
		B.mesh(root, B.box_mesh(Vector3(0.18, 0.4, 0.04)), Vector3(0, 0.95 * s, 0.33), rune)
		add_collider_cyl(p, 0.4, 1.6, null)


# ------------------------------------------------------------------ cave

func build_cave() -> void:
	var rock := B.paint_mat(Color(0.56, 0.53, 0.5), "stone", 31)
	var mossy := B.paint_mat(Color(0.42, 0.48, 0.36), "stone", 32)
	var dark := B.glow(Color(0.01, 0.01, 0.02))
	var mouth := CAVE_MOUTH
	# Rocky hill: big rounded boulders piled up behind the mouth
	var boulders := [
		[Vector3(-1.5, 2.5, 3.5), Vector3(6, 6, 5)], [Vector3(17.5, 2.5, 3.5), Vector3(6, 6, 5)],
		[Vector3(8, 8.5, 5), Vector3(9, 4.5, 6)], [Vector3(-10, 3, 7), Vector3(8, 7, 7)], [Vector3(26, 3, 7), Vector3(8, 7, 7)],
		[Vector3(-22, 4, 9), Vector3(10, 8, 8)], [Vector3(38, 4, 9), Vector3(10, 8, 8)], [Vector3(-36, 4, 10), Vector3(10, 9, 9)],
		[Vector3(50, 4, 10), Vector3(10, 9, 9)], [Vector3(8, 12, 12), Vector3(14, 8, 9)], [Vector3(-14, 9, 14), Vector3(12, 8, 9)],
		[Vector3(28, 9, 14), Vector3(12, 8, 9)],
	]
	for b in boulders:
		var m := B.mesh(world, B.sphere(1.0, 10, 7), mouth + b[0], rock if rng.randf() < 0.6 else mossy)
		m.scale = b[1]
		m.rotation.y = rng.randf() * TAU
	# Arch stones framing the mouth
	for k in 7:
		var a := lerpf(-1.25, 1.25, k / 6.0)
		var ap := mouth + Vector3(sin(a) * 3.4, cos(a) * 3.6 + 0.4, 0.6)
		var m2 := B.mesh(world, B.sphere(1.0, 7, 5), ap, mossy)
		m2.scale = Vector3(1.0, 0.85, 0.9) * rng.randf_range(0.9, 1.2)
	# Darkness inside
	B.mesh(world, B.box_mesh(Vector3(6.5, 6, 0.5)), mouth + Vector3(0, 3, 6), dark)
	B.mesh(world, B.box_mesh(Vector3(0.5, 6, 6)), mouth + Vector3(-3.3, 3, 3), dark)
	B.mesh(world, B.box_mesh(Vector3(0.5, 6, 6)), mouth + Vector3(3.3, 3, 3), dark)
	B.mesh(world, B.box_mesh(Vector3(6.5, 0.5, 6)), mouth + Vector3(0, 4.8, 3), dark)
	var floor_m := B.mesh(world, B.box_mesh(Vector3(6.4, 0.05, 6)), mouth + Vector3(0, 0.05, 3), dark)
	floor_m.position.y = 0.04
	# Collision: hill face with a gap for the mouth, closed at the back
	var hill := StaticBody3D.new()
	hill.collision_layer = LAYER_TREES
	world.add_child(hill)
	for c in [[Vector3(60, 12, 14), Vector3(-30 - 3.4 + mouth.x, 6, mouth.z + 7)], [Vector3(60, 12, 14), Vector3(30 + 3.4 + mouth.x, 6, mouth.z + 7)], [Vector3(8, 12, 2), Vector3(mouth.x, 6, mouth.z + 6.5)]]:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = c[0]
		cs.shape = sh
		cs.position = c[1]
		hill.add_child(cs)
	# Torches, graves, bones and dead trees in the clearing
	for tx in [-3.6, 3.6]:
		var p := mouth + Vector3(tx, 0, -2.0)
		add_collider_cyl(p, 0.15, 2.2)
		B.mesh(world, B.cyl(0.07, 0.11, 2.2, 6), p + Vector3(0, 1.1, 0), B.paint_mat(Color(0.35, 0.24, 0.15), "leather"))
		B.mesh(world, B.prism(Vector3(0.35, 0.6, 0.35)), p + Vector3(0, 2.5, 0), B.glow(Color(1.0, 0.55, 0.15)))
		var light := OmniLight3D.new()
		light.position = p + Vector3(0, 2.6, -0.4)
		light.light_color = Color(1.0, 0.5, 0.2)
		light.omni_range = 10.0
		world.add_child(light)
		main.lanterns.append([light, 2.0, 0.35])
	var grave := B.paint_mat(Color(0.6, 0.6, 0.62), "stone", 33)
	var dirt := B.paint_mat(Color(0.4, 0.32, 0.22), "stone", 34)
	for g in [Vector3(-3, 0, -6), Vector3(-1, 0, -3.5), Vector3(-4.5, 0, -1), Vector3(14, 0, -4), Vector3(15.5, 0, -1.5), Vector3(12.5, 0, -8)]:
		var gp: Vector3 = CAVE_CLEARING + g
		var stone_m := B.mesh(world, B.box_mesh(Vector3(0.75, 1.05, 0.22)), gp + Vector3(0, 0.5, 0), grave, Vector3(rng.randf_range(-10, 10), rng.randf_range(-20, 20), rng.randf_range(-6, 6)))
		var top_m := B.mesh(world, B.cyl(0.38, 0.38, 0.22, 8), gp + Vector3(0, 1.02, 0), grave, Vector3(90, 0, 0))
		top_m.scale = Vector3(1, 1, 1)
		stone_m.scale = Vector3.ONE
		var mound := B.mesh(world, B.sphere(1.0, 7, 4), gp + Vector3(0, 0.02, 1.0), dirt)
		mound.scale = Vector3(0.6, 0.22, 1.1)
	var bone := B.paint_mat(Color(0.9, 0.88, 0.78), "skin")
	for i in 16:
		var p := CAVE_CLEARING + Vector3(rng.randf_range(-6, 8), 0.06, rng.randf_range(2, 13))
		B.mesh(world, B.cyl(0.04, 0.04, rng.randf_range(0.3, 0.55), 5), p, bone, Vector3(90, rng.randf() * 360.0, 0))
	B.mesh(world, B.sphere(0.16, 6, 4), CAVE_CLEARING + Vector3(4, 0.14, 10), bone)
	for d in [Vector3(-9, 0, 4), Vector3(17, 0, 2), Vector3(-6, 0, 12)]:
		add_tree(CAVE_CLEARING + d, rng.randf_range(0.9, 1.1), "dead")


# ------------------------------------------------------------------ decoration

func build_decor() -> void:
	# Grass tufts and wildflowers everywhere it's open
	for i in 3400:
		var p := Vector3(rng.randf_range(MIN_X - 6, MAX_X + 6), 0, rng.randf_range(MIN_Z - 6, MAX_Z - 3))
		if flat_len(p) < 9.5 or dist_to_path(p) < 1.6:
			continue
		var g := Color(0.42, 0.62, 0.28).lerp(Color(0.6, 0.7, 0.32), rng.randf())
		if flat_len(p) > 30.0:
			g = g.darkened(0.15)
		tufts.append([xf(p, Vector3.ONE * rng.randf_range(0.8, 1.6), rng.randf() * TAU), g])
		if rng.randf() < 0.12 and p.distance_to(CAVE_CLEARING) > 14.0:
			var fc := [Color(1, 1, 0.95), Color(1.0, 0.85, 0.3), Color(0.75, 0.55, 0.95), Color(1.0, 0.5, 0.55)][rng.randi_range(0, 3)] as Color
			flowers.append([xf(p + Vector3(rng.randf_range(-0.3, 0.3), 0.3, rng.randf_range(-0.3, 0.3)), Vector3.ONE * 0.06), fc])
	# Bushes and ferny clumps at the forest's edge
	for i in 220:
		var p := Vector3(rng.randf_range(MIN_X - 4, MAX_X + 4), 0, rng.randf_range(MIN_Z - 4, MAX_Z - 4))
		var td := flat_len(p)
		if td < WARD_R + 1.5 or dist_to_path(p) < 2.4 or p.distance_to(CAVE_CLEARING) < 12.0:
			continue
		var s := rng.randf_range(0.5, 0.95)
		var col := Color(0.3, 0.5, 0.25).lerp(Color(0.4, 0.58, 0.28), rng.randf())
		blobs.append([xf(p + Vector3(0, s * 0.35, 0), Vector3(1.2, 0.75, 1.2) * s, rng.randf() * TAU), col])
		blobs.append([xf(p + Vector3(s * 0.6, s * 0.25, s * 0.2), Vector3(0.8, 0.6, 0.8) * s, 0.0), col.darkened(0.08)])
	# Mushrooms near tree roots
	for i in 90:
		if tree_spots.is_empty():
			break
		var t: Vector3 = tree_spots[rng.randi_range(0, tree_spots.size() - 1)]
		if not in_bounds(t, -2.0):
			continue
		var a := rng.randf() * TAU
		var p := Vector3(t.x + cos(a) * 0.75, 0, t.z + sin(a) * 0.75)
		var s := rng.randf_range(0.7, 1.3)
		stems.append([xf(p + Vector3(0, 0.08 * s, 0), Vector3(0.035, 0.16, 0.035) * s), Color(0.95, 0.92, 0.85)])
		var cap_col := Color(0.85, 0.2, 0.15) if rng.randf() < 0.6 else Color(0.75, 0.6, 0.4)
		caps.append([xf(p + Vector3(0, 0.17 * s, 0), Vector3(0.1, 0.06, 0.1) * s), cap_col])
	# Mossy boulders in the woods
	var rock := B.paint_mat(Color(0.55, 0.55, 0.52), "stone", 41)
	for i in 40:
		var p := Vector3(rng.randf_range(MIN_X, MAX_X), 0, rng.randf_range(MIN_Z, MAX_Z - 10))
		if flat_len(p) < WARD_R + 2.0 or dist_to_path(p) < 3.0 or p.distance_to(CAVE_CLEARING) < 10.0:
			continue
		var s := rng.randf_range(0.5, 1.4)
		var m := B.mesh(world, B.sphere(1.0, 8, 5), p + Vector3(0, s * 0.3, 0), rock)
		m.scale = Vector3(1.3, 0.8, 1.0) * s
		m.rotation.y = rng.randf() * TAU
		if s > 0.8:
			add_collider_cyl(p, s, s * 0.9)
	# A fallen log blocks the old west road
	var log_m := B.paint_mat(Color(0.45, 0.34, 0.24), "hair", 42)
	var lp := Vector3(-40, 0.45, -15.5)
	B.mesh(world, B.cyl(0.45, 0.5, 7.0, 9), lp, log_m, Vector3(0, 20, 90))
	B.mesh(world, B.cyl(0.4, 0.4, 0.02, 9), lp + Vector3(3.3, 0, -1.2), B.paint_mat(Color(0.75, 0.62, 0.42), "skin"), Vector3(0, 20, 90))
	var lb := StaticBody3D.new()
	lb.position = lp
	lb.rotation = Vector3(0, deg_to_rad(20), 0)
	var lcs := CollisionShape3D.new()
	var lsh := BoxShape3D.new()
	lsh.size = Vector3(7.0, 1.0, 1.0)
	lcs.shape = lsh
	lb.add_child(lcs)
	world.add_child(lb)


## Combines every static mesh that shares a material (within a 32 m area) into a
## single mesh, so the village and props cost a few dozen draw calls, not hundreds.
func merge_static() -> void:
	var found := []
	var stack: Array = [world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for ch in n.get_children():
			if ch.get_script() != null:
				continue
			if ch is MeshInstance3D and not ch.has_meta("no_merge") and ch.material_override is StandardMaterial3D and ch.mesh != null:
				found.append(ch)
			stack.append(ch)
	var groups := {}
	for mi in found:
		var mat: StandardMaterial3D = mi.material_override
		var o: Vector3 = mi.global_transform.origin
		var tex_id := mat.albedo_texture.get_rid().get_id() if mat.albedo_texture != null else 0
		var key := "%d|%s|%d|%d|%d|%d,%d" % [tex_id, mat.albedo_color.to_html(), mat.shading_mode, mat.transparency, mat.cull_mode, floori(o.x / 32.0), floori(o.z / 32.0)]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(mi)
	for key in groups:
		var list: Array = groups[key]
		if list.size() < 2:
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for mi in list:
			st.append_from(mi.mesh, 0, mi.global_transform)
		var merged := MeshInstance3D.new()
		merged.mesh = st.commit()
		merged.material_override = list[0].material_override
		merged.cast_shadow = list[0].cast_shadow
		world.add_child(merged)
		for mi in list:
			mi.get_parent().remove_child(mi)
			mi.queue_free()
