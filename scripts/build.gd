extends RefCounted
## Helpers for building low-poly, N64-style geometry entirely from code.

static var _tex_cache := {}


static func noise_tex(variance: float, pattern: String = "", seed_value: int = 1, size_px: int = 32) -> ImageTexture:
	var key := "%s_%s_%s_%s" % [variance, pattern, seed_value, size_px]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := Image.create_empty(size_px, size_px, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for y in size_px:
		for x in size_px:
			var v := 0.82 + rng.randf_range(-variance, variance)
			var c := Color(v, v, v)
			match pattern:
				"bricks":
					var row := int(y / 8)
					var off := 8 if row % 2 == 1 else 0
					if y % 8 == 0 or (x + off) % 16 == 0:
						c = c.darkened(0.35)
				"planks":
					if x % 8 == 0:
						c = c.darkened(0.45)
					elif (y + int(x / 8) * 11) % 32 == 0:
						c = c.darkened(0.3)
				"cobble":
					var col := int(x / 8)
					if x % 8 == 0 or (y + (col % 2) * 4) % 8 == 0:
						c = c.darkened(0.3)
				"grass":
					if rng.randf() < 0.08:
						c = c.lightened(0.15)
			img.set_pixel(x, y, c.clamp())
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


static func mat(color: Color, tex: Texture2D = null, tri_scale: float = 0.25, unshaded: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if tex != null:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * tri_scale
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


static func glow(color: Color) -> StandardMaterial3D:
	return mat(color, null, 0.25, true)


static func mesh(parent: Node, m: Mesh, pos: Vector3, material: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func box_mesh(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func cyl(top: float, bottom: float, height: float, segs: int = 6) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segs
	c.rings = 0
	return c


static func sphere(radius: float, segs: int = 6, rings: int = 4) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = segs
	s.rings = rings
	return s


static func prism(size: Vector3) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = size
	return p


static func solid_box(parent: Node, size: Vector3, pos: Vector3, material: Material, rot_y: float = 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees.y = rot_y
	parent.add_child(body)
	mesh(body, box_mesh(size), Vector3.ZERO, material)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	return body


static func solid_cylinder(parent: Node, radius: float, height: float, pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	parent.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = radius
	sh.height = height
	cs.shape = sh
	cs.position.y = height * 0.5
	body.add_child(cs)
	return body


static func blob_shadow(parent: Node3D, radius: float = 0.45) -> MeshInstance3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0, 0, 0, 0.45)
	var c := cyl(radius, radius, 0.02, 10)
	return mesh(parent, c, Vector3(0, 0.09, 0), m)


## Sweeps a smooth closed shape through elliptical cross-sections.
## rings: [y, radius_x, radius_z, (z offset)] listed bottom to top.
## UV u = 0.5 is the front (-Z); v = 0 is the top ring.
static func loft(rings: Array, segs: int = 10) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := rings.size()
	for i in n:
		var r: Array = rings[i]
		var cz: float = r[3] if r.size() > 3 else 0.0
		var v := 1.0 - float(i) / float(n - 1)
		for s in segs + 1:
			var a := -PI + TAU * float(s) / float(segs)
			st.set_uv(Vector2(float(s) / float(segs), v))
			st.add_vertex(Vector3(sin(a) * float(r[1]), float(r[0]), -cos(a) * float(r[2]) + cz))
	for i in n - 1:
		for s in segs:
			var a0 := i * (segs + 1) + s
			var b0 := a0 + segs + 1
			st.add_index(a0)
			st.add_index(a0 + 1)
			st.add_index(b0)
			st.add_index(a0 + 1)
			st.add_index(b0 + 1)
			st.add_index(b0)
	st.generate_normals()
	return st.commit()


static func tex_mat(tex: Texture2D, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	return m


static func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
	for y in range(int(cy - ry - 1), int(cy + ry + 2)):
		for x in range(int(cx - rx - 1), int(cx + rx + 2)):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, col)


static func _rect(img: Image, x0: int, y0: int, w: int, h: int, col: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
				img.set_pixel(x, y, col)


## Paints an N64-style face (and hairline) onto the head's wrap-around texture.
static func face_tex(c: Dictionary) -> ImageTexture:
	var W := 256
	var H := 96
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGB8)
	var skin: Color = c.skin
	var hair: Color = c.hair
	var face: String = c.get("face", "")
	var style: String = c.get("hair_style", "short")
	img.fill(skin)
	var fx := W / 2
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(c))

	# Gentle shading: cheek warmth and a darker jaw underside.
	for y in H:
		for x in W:
			var du := absf(float(x - fx)) / float(W)
			var col := skin
			if y > 78:
				col = col.darkened(0.12)
			if face != "zombie":
				for cx in [fx - 20, fx + 20]:
					var d := Vector2(float(x - cx) / 7.0, float(y - 60) / 4.0).length()
					if d < 1.0:
						col = col.lerp(Color(0.95, 0.5, 0.45), 0.1 * (1.0 - d))
			if face == "zombie" and rng.randf() < 0.05:
				col = col.darkened(rng.randf_range(0.1, 0.3))
			img.set_pixel(x, y, col)

	# Ears
	for ex in [fx - 64, fx + 64]:
		_ellipse(img, ex, 52, 5, 7, skin.darkened(0.18))
		_ellipse(img, ex, 52, 2.5, 4, skin.darkened(0.3))

	# Hair painted over the scalp, temples and back of the head.
	if style != "none":
		for x in W:
			var du := absf(float(x - fx)) / float(W)
			var line := 31.0 + sin(x * 0.45) * 1.5
			if du > 0.17:
				line = lerpf(31.0, 50.0, clampf((du - 0.17) / 0.06, 0.0, 1.0))
			if du > 0.23:
				line = lerpf(50.0, 82.0 if style != "long" else 96.0, clampf((du - 0.23) / 0.08, 0.0, 1.0))
			line += sin(x * 0.9) * 1.2
			for y in int(clampf(line, 0, H)):
				img.set_pixel(x, y, hair.darkened(rng.randf_range(0.0, 0.18)))

	var eye_col: Color = c.get("eye_color", Color(0.25, 0.35, 0.55))
	var brow := hair.darkened(0.35)
	for side in [-1, 1]:
		var ex: int = fx + side * 16
		if face == "zombie":
			_ellipse(img, ex, 49, 7.5, 5.5, skin.darkened(0.55))
			_ellipse(img, ex, 50, 3.0, 2.5, Color(1.0, 0.25, 0.12))
			_ellipse(img, ex, 50, 1.2, 1.2, Color(1.0, 0.85, 0.5))
			continue
		# Brow
		for i in 12:
			var bx := ex - 6 + i
			var by := 42 - int(side * (i - 6) * 0.15) if face == "stern" else 42 - (1 if i > 3 and i < 9 else 0)
			_rect(img, bx, by, 1, 2, brow)
		# Eye white, iris, pupil, highlight, upper lash line
		_ellipse(img, ex, 50, 5.5, 3.4, Color(0.97, 0.96, 0.93))
		_ellipse(img, ex + side * 0.5, 50.3, 2.6, 2.9, eye_col)
		_ellipse(img, ex + side * 0.5, 50.3, 1.2, 1.4, Color(0.05, 0.04, 0.05))
		img.set_pixel(ex - 1, 49, Color(1, 1, 1))
		for i in 12:
			var lx := ex - 6 + i
			_rect(img, lx, 46 + (1 if i == 0 or i == 11 else 0), 1, 1, Color(0.12, 0.08, 0.07))
		if face == "old":
			for i in 4:
				img.set_pixel(ex + side * (7 + i), 51 + i % 2, skin.darkened(0.25))
				img.set_pixel(ex + side * (7 + i), 54 + i % 2, skin.darkened(0.2))

	# Nose shading and nostrils
	for y in range(52, 60):
		img.set_pixel(fx + 2, y, skin.darkened(0.1))
		img.set_pixel(fx - 2, y, skin.darkened(0.06))
	img.set_pixel(fx - 2, 60, skin.darkened(0.35))
	img.set_pixel(fx + 2, 60, skin.darkened(0.35))

	# Mouth
	if face == "zombie":
		_rect(img, fx - 7, 67, 14, 7, Color(0.12, 0.03, 0.03))
		for t in [-5, -2, 2, 5]:
			_rect(img, fx + t, 67, 1, 2, Color(0.85, 0.8, 0.6))
		_rect(img, fx - 1, 72, 2, 2, Color(0.85, 0.8, 0.6))
	else:
		var lip := skin.lerp(Color(0.65, 0.22, 0.2), 0.5)
		_rect(img, fx - 6, 69, 13, 1, lip.darkened(0.35))
		_rect(img, fx - 4, 70, 9, 1, lip)
		if face == "kid":
			img.set_pixel(fx - 7, 68, lip.darkened(0.35))
			img.set_pixel(fx + 7, 68, lip.darkened(0.35))
		if face == "old":
			_rect(img, fx - 9, 64, 1, 5, skin.darkened(0.2))
			_rect(img, fx + 9, 64, 1, 5, skin.darkened(0.2))
	if c.has("beard"):
		var bc: Color = c.beard
		for y in range(60, H):
			for x in range(fx - 34, fx + 35):
				var inside := absf(float(x - fx)) < 34.0 - maxf(0.0, float(y - 85)) * 2.0
				var mouth := y >= 68 and y <= 71 and absf(float(x - fx)) < 7
				if inside and not mouth and (y > 64 or absf(float(x - fx)) < 10 or absf(float(x - fx)) > 22):
					img.set_pixel(x, y, bc.darkened(rng.randf_range(0.0, 0.2)))
	return ImageTexture.create_from_image(img)


const HEAD_RINGS := [
	[1.49, 0.03, 0.03, 0.0],
	[1.505, 0.055, 0.06, -0.02],
	[1.535, 0.08, 0.09, -0.012],
	[1.58, 0.097, 0.108, 0.0],
	[1.63, 0.104, 0.115, 0.0],
	[1.68, 0.105, 0.115, 0.005],
	[1.73, 0.097, 0.11, 0.01],
	[1.77, 0.075, 0.09, 0.012],
	[1.795, 0.04, 0.05, 0.01],
	[1.805, 0.002, 0.002, 0.01],
]

const HAIR_CAP := [
	[1.6, 0.1, 0.1, 0.035],
	[1.66, 0.11, 0.12, 0.02],
	[1.72, 0.111, 0.124, 0.004],
	[1.77, 0.088, 0.103, 0.0],
	[1.81, 0.045, 0.055, 0.0],
	[1.822, 0.002, 0.002, 0.0],
]


## Shifts a ring list's y values (lofts are authored in body space).
static func rings_offset(rings: Array, dy: float, scale_r: float = 1.0) -> Array:
	var out := []
	for r in rings:
		var nr: Array = r.duplicate()
		nr[0] = float(r[0]) + dy
		nr[1] = float(r[1]) * scale_r
		nr[2] = float(r[2]) * scale_r
		out.append(nr)
	return out


## Builds a smooth low-poly person facing -Z with feet at the origin.
## Joints: pivot (whole-body), body, head, arm_l/r (shoulder), forearm_l/r (elbow),
## leg_l/r (hip), shin_l/r (knee).
static func humanoid(model: Node3D, c: Dictionary) -> Dictionary:
	var pivot := Node3D.new()
	pivot.position.y = 0.85
	model.add_child(pivot)
	var body := Node3D.new()
	body.position.y = -0.85
	pivot.add_child(body)
	var bulk: float = c.get("bulk", 1.0)
	var hipw: float = c.get("hips", 1.0)
	var skin := mat(c.skin)
	var shirt := mat(c.shirt)
	var pants := mat(c.pants)
	var hair := mat(c.hair)
	var boots := mat(c.get("boots", Color(0.2, 0.14, 0.1)))
	var sleeve := mat(c.get("arm", c.shirt))
	var forearm := mat(c.get("forearm", c.get("arm", c.shirt)))
	var hand := mat(c.get("hand", c.skin))
	var parts := {"pivot": pivot, "body": body}

	# Pelvis and torso
	mesh(body, loft([
		[0.78, 0.12 * hipw, 0.085], [0.84, 0.15 * hipw, 0.105], [0.94, 0.152 * hipw, 0.105], [1.02, 0.138, 0.096],
	], 10), Vector3.ZERO, pants)
	parts["torso"] = mesh(body, loft([
		[0.97, 0.137, 0.097], [1.08, 0.142 * bulk, 0.1], [1.2, 0.168 * bulk, 0.118, -0.008],
		[1.31, 0.188 * bulk, 0.114, -0.004], [1.39, 0.185 * bulk, 0.1], [1.44, 0.12, 0.075], [1.47, 0.055, 0.05],
	], 10), Vector3.ZERO, shirt)
	mesh(body, cyl(0.046, 0.054, 0.12, 8), Vector3(0, 1.49, 0.006), skin)

	for side in [-1, 1]:
		var sfx := "_l" if side < 0 else "_r"
		# Leg: hip -> knee -> foot
		var hip := Node3D.new()
		hip.position = Vector3(0.085 * side * hipw, 0.86, 0)
		body.add_child(hip)
		mesh(hip, cyl(0.062, 0.086, 0.44, 8), Vector3(0, -0.21, 0), pants)
		var knee := Node3D.new()
		knee.position.y = -0.42
		hip.add_child(knee)
		mesh(knee, cyl(0.046, 0.062, 0.36, 8), Vector3(0, -0.18, 0), pants)
		mesh(knee, cyl(0.056, 0.062, 0.2, 8), Vector3(0, -0.3, 0), boots)
		var foot := mesh(knee, sphere(1.0, 8, 5), Vector3(0, -0.405, -0.045), boots)
		foot.scale = Vector3(0.058, 0.045, 0.125)
		parts["leg" + sfx] = hip
		parts["shin" + sfx] = knee
		# Arm: shoulder -> elbow -> hand
		var sh := Node3D.new()
		sh.position = Vector3(0.19 * bulk * side, 1.375, 0)
		body.add_child(sh)
		var splay := Node3D.new()
		splay.rotation.z = 0.09 * side
		sh.add_child(splay)
		var cap := mesh(splay, sphere(1.0, 8, 5), Vector3(0, -0.01, 0), sleeve)
		cap.scale = Vector3(0.052, 0.058, 0.056)
		mesh(splay, cyl(0.043, 0.054, 0.3, 8), Vector3(0, -0.15, 0), sleeve)
		var el := Node3D.new()
		el.position.y = -0.29
		el.rotation.x = 0.12
		splay.add_child(el)
		mesh(el, cyl(0.034, 0.044, 0.26, 8), Vector3(0, -0.13, 0), forearm)
		var hd := mesh(el, sphere(1.0, 8, 5), Vector3(0, -0.3, -0.005), hand)
		hd.scale = Vector3(0.036, 0.058, 0.046)
		parts["arm" + sfx] = sh
		parts["forearm" + sfx] = el

	# Head: smooth skull with a painted face, small nose and ears.
	var head := Node3D.new()
	head.position.y = 1.5
	body.add_child(head)
	var hs: float = c.get("head_scale", 1.0)
	head.scale = Vector3.ONE * hs
	mesh(head, loft(rings_offset(HEAD_RINGS, -1.5), 14), Vector3.ZERO, tex_mat(face_tex(c)))
	var nose := mesh(head, sphere(1.0, 6, 4), Vector3(0, 0.108, -0.106), skin)
	nose.scale = Vector3(0.012, 0.022, 0.016)
	for side in [-1, 1]:
		var ear := mesh(head, sphere(1.0, 6, 4), Vector3(0.102 * side, 0.135, 0.008), skin)
		ear.scale = Vector3(0.016, 0.034, 0.024)
	if c.has("glow_eyes"):
		var g := glow(c.glow_eyes)
		for side in [-1, 1]:
			mesh(head, sphere(0.011, 6, 3), Vector3(0.04 * side, 0.146, -0.104), g)

	var style: String = c.get("hair_style", "short")
	if style != "none":
		mesh(head, loft(rings_offset(HAIR_CAP, -1.5), 12), Vector3.ZERO, hair)
	match style:
		"short":
			# Swept, slightly messy fringe
			for i in 5:
				var x := -0.07 + i * 0.035
				mesh(head, prism(Vector3(0.055, 0.085, 0.03)), Vector3(x, 0.235, -0.105), hair, Vector3(-150, 0, -14 + i * 4))
			for side in [-1, 1]:
				mesh(head, prism(Vector3(0.04, 0.09, 0.05)), Vector3(0.1 * side, 0.18, -0.03), hair, Vector3(180, 0, 12 * side))
		"long":
			mesh(head, loft([
				[-0.16, 0.08, 0.03, 0.09], [-0.06, 0.105, 0.045, 0.095], [0.06, 0.112, 0.06, 0.07], [0.2, 0.105, 0.07, 0.05],
			], 10), Vector3.ZERO, hair)
			for i in 4:
				mesh(head, prism(Vector3(0.06, 0.08, 0.03)), Vector3(-0.055 + i * 0.037, 0.235, -0.105), hair, Vector3(-155, 0, -8 + i * 5))
		"bun":
			mesh(head, sphere(0.058, 8, 5), Vector3(0, 0.25, 0.085), hair)
		"cropped":
			pass
	parts["head"] = head
	return parts


static func yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)
