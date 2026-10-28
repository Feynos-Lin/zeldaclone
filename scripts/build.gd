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


## Hand-painted texture: baked top-light gradient, brushstrokes, and per-kind detail
## (cloth folds, rope twist, hair strands, leather seams, metal sheen, skin).
static func paint_tex(base: Color, kind: String = "cloth", seed_value: int = 7) -> ImageTexture:
	var key := "paint_%s_%s_%s" % [base.to_html(), kind, seed_value]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var W := 64
	var H := 64
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + hash(kind)
	var top := 1.14
	var bottom := 0.76
	if kind == "skin":
		top = 1.06
		bottom = 0.92
	elif kind == "hair":
		top = 1.3
		bottom = 0.7
	elif kind == "metal":
		top = 1.25
		bottom = 0.7
	elif kind == "grass" or kind == "stone":
		top = 1.0
		bottom = 1.0
	for y in H:
		for x in W:
			var g := lerpf(top, bottom, float(y) / float(H - 1))
			img.set_pixel(x, y, Color(base.r * g, base.g * g, base.b * g).clamp())
	var strokes := 30 if kind == "skin" else 110
	for i in strokes:
		var x0 := rng.randi_range(0, W - 1)
		var y0 := rng.randi_range(0, H - 1)
		var length := rng.randi_range(4, 16)
		var amt := rng.randf_range(-0.14, 0.14) * (0.4 if kind == "skin" else 1.0)
		var horizontal := kind == "metal" or kind == "leather"
		for k in length:
			var px := posmod(x0 + (k if horizontal else 0), W)
			var py := clampi(y0 + (0 if horizontal else k), 0, H - 1)
			var c := img.get_pixel(px, py)
			img.set_pixel(px, py, c.lightened(amt) if amt > 0.0 else c.darkened(-amt))
	match kind:
		"cloth":
			for f in 7:
				var fx := rng.randf_range(0.0, float(W))
				var y_start := rng.randi_range(int(H * 0.25), H - 14)
				for y in range(y_start, H):
					var x := posmod(int(fx + sin(y * 0.25 + f) * 1.8), W)
					img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.2))
					var x2 := posmod(x + 1, W)
					img.set_pixel(x2, y, img.get_pixel(x2, y).lightened(0.1))
		"rope":
			for y in H:
				for x in W:
					if posmod(x + y, 8) < 3:
						img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.32))
					elif posmod(x + y, 8) == 4:
						img.set_pixel(x, y, img.get_pixel(x, y).lightened(0.15))
		"hair":
			for i in 40:
				var x := rng.randi_range(0, W - 1)
				var amt := rng.randf_range(0.1, 0.3)
				for y in H:
					var c := img.get_pixel(x, y)
					img.set_pixel(x, y, c.darkened(amt) if i % 2 == 0 else c.lightened(amt * 0.6))
		"leather":
			for x in W:
				img.set_pixel(x, 6, img.get_pixel(x, 6).darkened(0.35))
				if x % 4 < 2:
					img.set_pixel(x, 8, img.get_pixel(x, 8).lightened(0.2))
		"leaf":
			for i in 70:
				var cx := rng.randi_range(0, W - 1)
				var cy := rng.randi_range(0, H - 1)
				var r := rng.randf_range(1.5, 4.0)
				var amt := rng.randf_range(0.08, 0.22)
				var light := rng.randf() < 0.45
				for yy in range(cy - 4, cy + 5):
					for xx in range(cx - 4, cx + 5):
						if Vector2(xx - cx, yy - cy).length() <= r:
							var px := posmod(xx, W)
							var py := clampi(yy, 0, H - 1)
							var c := img.get_pixel(px, py)
							img.set_pixel(px, py, c.lightened(amt) if light else c.darkened(amt))
		"grass":
			for i in 260:
				var x := rng.randi_range(0, W - 1)
				var y := rng.randi_range(0, H - 1)
				var amt := rng.randf_range(0.06, 0.18)
				for k in 3:
					var py := posmod(y - k, H)
					var c := img.get_pixel(x, py)
					img.set_pixel(x, py, c.lightened(amt) if i % 3 == 0 else c.darkened(amt))
		"stone":
			for i in 50:
				var cx := rng.randi_range(0, W - 1)
				var cy := rng.randi_range(0, H - 1)
				var r := rng.randf_range(2.0, 6.0)
				var amt := rng.randf_range(-0.12, 0.12)
				for yy in range(cy - 6, cy + 7):
					for xx in range(cx - 6, cx + 7):
						if Vector2(xx - cx, yy - cy).length() <= r:
							var px := posmod(xx, W)
							var py := clampi(yy, 0, H - 1)
							var c := img.get_pixel(px, py)
							img.set_pixel(px, py, c.lightened(amt) if amt > 0.0 else c.darkened(-amt))
			for i in 6:
				var x := rng.randi_range(0, W - 1)
				var y := rng.randi_range(0, H - 1)
				for k in 10:
					x = posmod(x + rng.randi_range(-1, 1), W)
					y = clampi(y + 1, 0, H - 1)
					img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.3))
		"metal":
			for y in range(18, 26):
				for x in W:
					img.set_pixel(x, y, img.get_pixel(x, y).lightened(0.22 * (1.0 - absf(y - 22.0) / 4.0)))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


static func paint_mat(base: Color, kind: String = "cloth", seed_value: int = 7) -> StandardMaterial3D:
	var m := tex_mat(paint_tex(base, kind, seed_value))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return m


## Paints a stylized face (big expressive eyes, brows, nose, mouth) plus the
## hairline onto the head's wrap-around texture. u = 0.5 is the front.
static func face_tex(c: Dictionary) -> ImageTexture:
	var W := 256
	var H := 96
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGB8)
	var skin: Color = c.skin
	var hair: Color = c.hair
	var face: String = c.get("face", "")
	var style: String = c.get("hair_style", "short")
	var fx := W / 2
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(c))

	for y in H:
		for x in W:
			var col := skin
			# soft painted shading: lit forehead, shadow under jaw and toward the back
			col = col.lightened(maxf(0.0, (40.0 - y) / 40.0) * 0.06)
			if y > 76:
				col = col.darkened(0.06 + (y - 76) * 0.006)
			var du := absf(float(x - fx)) / float(W)
			col = col.darkened(clampf((du - 0.12) * 0.35, 0.0, 0.1))
			if face == "zombie" and rng.randf() < 0.07:
				col = col.darkened(rng.randf_range(0.1, 0.3))
			img.set_pixel(x, y, col)
	if face != "zombie":
		for cx in [fx - 21, fx + 21]:
			for y in range(54, 68):
				for x in range(cx - 9, cx + 10):
					var d := Vector2(float(x - cx) / 9.0, float(y - 61) / 5.0).length()
					if d < 1.0:
						img.set_pixel(x, y, img.get_pixel(x, y).lerp(Color(0.92, 0.48, 0.42), 0.14 * (1.0 - d)))
	if c.has("smudge"):
		# dirt smudges / tired eyes, like a kid who's been out in the fields
		for cx in [fx - 22, fx + 23]:
			for y in range(55, 66):
				for x in range(cx - 9, cx + 10):
					var d := Vector2(float(x - cx) / 9.0, float(y - 60) / 4.0).length()
					if d < 1.0:
						img.set_pixel(x, y, img.get_pixel(x, y).lerp(Color(0.55, 0.4, 0.32), 0.3 * (1.0 - d)))
		for side in [-1, 1]:
			for i in 9:
				img.set_pixel(fx + side * 16 - 4 + i, 56, img.get_pixel(fx + side * 16 - 4 + i, 56).darkened(0.12))

	# Ears
	for ex in [fx - 64, fx + 64]:
		_ellipse(img, ex, 50, 5, 8, skin.darkened(0.16))
		_ellipse(img, ex, 50, 2.5, 4.5, skin.darkened(0.3))

	# Hair painted on the scalp under the hair meshes.
	if style != "none":
		for x in W:
			var du := absf(float(x - fx)) / float(W)
			var line := 30.0 + sin(x * 0.45) * 1.5
			if du > 0.16:
				line = lerpf(30.0, 48.0, clampf((du - 0.16) / 0.06, 0.0, 1.0))
			if du > 0.22:
				line = lerpf(48.0, 84.0 if style != "long" else 96.0, clampf((du - 0.22) / 0.08, 0.0, 1.0))
			line += sin(x * 0.9) * 1.2
			for y in int(clampf(line, 0, H)):
				img.set_pixel(x, y, hair.darkened(rng.randf_range(0.0, 0.2) + float(y) / 300.0))

	var eye_col: Color = c.get("eye_color", Color(0.22, 0.2, 0.25))
	var brow := hair.darkened(0.4)
	for side in [-1, 1]:
		var ex: int = fx + side * 16
		if face == "zombie":
			_ellipse(img, ex, 49, 8.0, 6.5, skin.darkened(0.55))
			_ellipse(img, ex, 50, 3.5, 3.0, Color(1.0, 0.25, 0.12))
			_ellipse(img, ex, 50, 1.4, 1.4, Color(1.0, 0.85, 0.5))
			for i in 10:
				img.set_pixel(ex - 5 + i, 42 + int(absf(i - 5) * 0.3), brow)
			continue
		var big := 1.15 if face == "kid" else 1.0
		# Brows: worried (inner ends up), stern (inner ends down), soft otherwise
		for i in 15:
			var t := float(i) / 14.0                    # 0 = outer end, 1 = inner end
			var bx: int = ex - side * 7 + side * i
			var lift := 0.0
			match face:
				"worried":
					lift = t * t * 4.5
				"stern":
					lift = -t * 3.0
				"old":
					lift = t * 2.0
				_:
					lift = sin(t * PI) * 1.5
			var by := int(41.0 - lift)
			_rect(img, bx, by, 1, 3 if face != "old" else 2, brow)
		# Eye: white, big iris, pupil, two highlights, heavy upper lash line
		var rx := 6.5 * big
		var ry := 5.2 * big
		_ellipse(img, ex, 50, rx, ry, Color(0.97, 0.96, 0.93))
		_ellipse(img, ex - side * 0.5, 50.5, 4.2 * big, 4.8 * big, eye_col)
		_ellipse(img, ex - side * 0.5, 50.8, 2.2 * big, 2.8 * big, Color(0.03, 0.02, 0.03))
		_rect(img, ex - 2, 47, 2, 2, Color(1, 1, 1))
		img.set_pixel(ex + 2, 53, Color(0.9, 0.9, 0.95))
		for i in range(-7, 8):
			var yy := 50.0 - ry * sqrt(maxf(0.0, 1.0 - pow(float(i) / 7.2, 2.0)))
			_rect(img, ex + i, int(yy) - 1, 1, 2, Color(0.1, 0.06, 0.05))
		if face == "worried":
			for i in range(-5, 6):
				img.set_pixel(ex + i, 56, img.get_pixel(ex + i, 56).darkened(0.18))
		if face == "old":
			for i in 4:
				img.set_pixel(ex + side * (8 + i), 52 + i % 2, skin.darkened(0.25))
				img.set_pixel(ex + side * (8 + i), 55 + i % 2, skin.darkened(0.2))
			for i in 16:
				img.set_pixel(fx - 8 + i, 34, skin.darkened(0.15))

	# Nose: shaded side, highlight on the bridge, nostrils
	for y in range(52, 61):
		img.set_pixel(fx + 3, y, img.get_pixel(fx + 3, y).darkened(0.14))
		img.set_pixel(fx - 1, y, img.get_pixel(fx - 1, y).lightened(0.06))
	_rect(img, fx - 3, 61, 2, 1, skin.darkened(0.4))
	_rect(img, fx + 2, 61, 2, 1, skin.darkened(0.4))

	# Mouth
	var lip := skin.lerp(Color(0.62, 0.22, 0.2), 0.5)
	match face:
		"zombie":
			_rect(img, fx - 8, 67, 16, 8, Color(0.12, 0.03, 0.03))
			for t in [-6, -3, 1, 4]:
				_rect(img, fx + t, 67, 2, 2, Color(0.85, 0.8, 0.6))
			_rect(img, fx - 1, 73, 2, 2, Color(0.85, 0.8, 0.6))
		"worried":
			for i in range(-8, 9):
				_rect(img, fx + i, 69 + int(absf(i) / 2.5), 1, 2, lip.darkened(0.45))
			_rect(img, fx - 4, 71, 9, 2, lip)
		"kid":
			for i in range(-7, 8):
				_rect(img, fx + i, 71 - int(absf(i) / 3.0), 1, 1, lip.darkened(0.4))
			_rect(img, fx - 4, 72, 9, 1, lip)
		_:
			_rect(img, fx - 6, 70, 13, 1, lip.darkened(0.4))
			_rect(img, fx - 4, 71, 9, 1, lip)
	if face == "old":
		_rect(img, fx - 10, 64, 1, 6, skin.darkened(0.2))
		_rect(img, fx + 10, 64, 1, 6, skin.darkened(0.2))
	if c.has("beard"):
		var bc: Color = c.beard
		for y in range(60, H):
			for x in range(fx - 36, fx + 37):
				var inside := absf(float(x - fx)) < 36.0 - maxf(0.0, float(y - 84)) * 2.0
				var mouth := y >= 68 and y <= 73 and absf(float(x - fx)) < 8
				if inside and not mouth and (y > 64 or absf(float(x - fx)) < 11 or absf(float(x - fx)) > 23):
					img.set_pixel(x, y, bc.darkened(rng.randf_range(0.0, 0.25)))
	return ImageTexture.create_from_image(img)


const HEAD_RINGS := [
	[1.49, 0.03, 0.03, 0.0],
	[1.505, 0.055, 0.06, -0.022],
	[1.535, 0.082, 0.09, -0.014],
	[1.58, 0.099, 0.108, -0.002],
	[1.63, 0.106, 0.115, 0.0],
	[1.68, 0.107, 0.116, 0.005],
	[1.73, 0.1, 0.112, 0.01],
	[1.77, 0.078, 0.092, 0.012],
	[1.795, 0.042, 0.052, 0.01],
	[1.805, 0.002, 0.002, 0.01],
]

const HAIR_CAP := [
	[1.6, 0.102, 0.102, 0.035],
	[1.66, 0.112, 0.122, 0.02],
	[1.72, 0.114, 0.126, 0.004],
	[1.77, 0.09, 0.105, 0.0],
	[1.81, 0.047, 0.057, 0.0],
	[1.822, 0.002, 0.002, 0.0],
]

# Chunky hair spikes: [azimuth° (0 front, 90 right), elevation°, length, base radius, upward tilt]
const SPIKES_HERO := [
	[-38, 30, 0.12, 0.05, -0.55, -0.1], [36, 32, 0.12, 0.05, -0.5, -0.1], [-8, 58, 0.13, 0.055, 0.25, -0.35], [16, 56, 0.12, 0.05, 0.2, -0.3],
	[-2, 72, 0.17, 0.065, 0.7, 0.2], [-16, 82, 0.26, 0.05, 1.5, 0.3], [10, 84, 0.2, 0.045, 1.2, 0.5], [40, 62, 0.17, 0.06, 0.55, 0.4], [-44, 60, 0.17, 0.06, 0.55, 0.4],
	[-82, 34, 0.18, 0.055, 0.45, 0.35], [82, 34, 0.18, 0.055, 0.45, 0.35], [-74, 10, 0.13, 0.05, -0.15, 0.1], [74, 10, 0.13, 0.05, -0.15, 0.1],
	[-115, 44, 0.17, 0.058, 0.45, 0.4], [115, 44, 0.17, 0.058, 0.45, 0.4], [180, 44, 0.16, 0.065, 0.35, 0.3], [150, 18, 0.15, 0.06, -0.15, 0.2],
	[-150, 18, 0.15, 0.06, -0.15, 0.2], [180, 8, 0.12, 0.055, -0.45, 0.0], [140, 64, 0.16, 0.06, 0.6, 0.45], [-140, 64, 0.16, 0.06, 0.6, 0.45],
]
const SPIKES_SHORT := [
	[-25, 40, 0.07, 0.045, -0.3], [10, 44, 0.07, 0.045, -0.3], [35, 38, 0.06, 0.04, -0.2], [0, 75, 0.08, 0.05, 0.4],
	[-50, 60, 0.08, 0.05, 0.3], [50, 60, 0.08, 0.05, 0.3], [-85, 30, 0.07, 0.045, 0.0], [85, 30, 0.07, 0.045, 0.0],
	[180, 40, 0.08, 0.05, 0.0], [-135, 50, 0.08, 0.05, 0.1], [135, 50, 0.08, 0.05, 0.1],
]
const SPIKES_STRINGY := [
	[-80, 20, 0.2, 0.03, -1.6], [80, 20, 0.22, 0.03, -1.6], [150, 25, 0.24, 0.035, -1.4], [-150, 25, 0.2, 0.035, -1.5],
	[180, 40, 0.18, 0.03, -1.2], [-30, 60, 0.12, 0.03, -0.6], [110, 50, 0.15, 0.03, -1.0],
]


static func hair_spikes(head: Node3D, m: Material, spikes: Array, size: float = 1.0) -> void:
	var center := Vector3(0, 0.155, 0.012)
	var radii := Vector3(0.11, 0.155, 0.12)
	var jitter := RandomNumberGenerator.new()
	jitter.seed = spikes.size() * 31
	for sp in spikes:
		var az := deg_to_rad(float(sp[0]))
		var el := deg_to_rad(float(sp[1]))
		var n := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
		var base := center + Vector3(n.x * radii.x, n.y * radii.y, n.z * radii.z) * 0.9
		var sweep: float = float(sp[5]) if sp.size() > 5 else 0.0
		var dir := (n + Vector3(0, float(sp[4]), sweep)).normalized()
		var length: float = float(sp[2]) * size * jitter.randf_range(0.85, 1.15)
		var mi := mesh(head, cyl(0.0, float(sp[3]) * size, length, 5), base + dir * length * 0.4, m)
		var up := Vector3.BACK if absf(dir.y) > 0.95 else Vector3.UP
		mi.basis = Basis.looking_at(dir, up) * Basis(Vector3.RIGHT, -PI * 0.5)


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


## Builds a stylized low-poly person facing -Z with feet at the origin.
## Joints: pivot (whole-body), body, head, arm_l/r (shoulder), forearm_l/r (elbow),
## leg_l/r (hip), shin_l/r (knee).
static func humanoid(model: Node3D, c: Dictionary) -> Dictionary:
	var pivot := Node3D.new()
	pivot.position.y = 0.85
	model.add_child(pivot)
	var leg_len: float = c.get("leg", 1.0)
	var limb: float = c.get("limb", 1.0)
	var arm_len: float = c.get("arm_len", 1.0)
	var hand_s: float = c.get("hand_scale", 1.0)
	var dy := 0.86 * (leg_len - 1.0)
	var body := Node3D.new()
	body.position.y = -0.85 + dy
	pivot.add_child(body)
	var bulk: float = c.get("bulk", 1.0)
	var hipw: float = c.get("hips", 1.0)
	var baggy: float = c.get("baggy", 1.0)
	var seed_value: int = hash(str(c.shirt)) % 97
	var skin := paint_mat(c.skin, "skin")
	var shirt_col: Color = c.shirt
	var shirt := paint_mat(shirt_col, "cloth", seed_value)
	var pants := paint_mat(c.pants, "cloth", seed_value + 3)
	var hair := paint_mat(c.hair, "hair")
	var boots := paint_mat(c.get("boots", Color(0.36, 0.24, 0.15)), "leather")
	var sleeve := paint_mat(c.get("arm", c.shirt), "cloth", seed_value + 1)
	var forearm_col: Color = c.get("forearm", c.get("arm", c.shirt))
	var forearm := paint_mat(forearm_col, "skin" if forearm_col == (c.skin as Color) else "cloth", seed_value + 2)
	var hand := paint_mat(c.get("hand", c.skin), "skin")
	var parts := {"pivot": pivot, "body": body, "body_y": -0.85 + dy}

	# Pelvis and torso. A V-neck collar is painted into the shirt if asked for.
	mesh(body, loft([
		[0.78, 0.125 * hipw, 0.09], [0.84, 0.152 * hipw, 0.108], [0.94, 0.152 * hipw, 0.106], [1.02, 0.138, 0.096],
	], 10), Vector3.ZERO, pants)
	var torso_mat := shirt
	if c.has("vneck"):
		var img := paint_tex(shirt_col, "cloth", seed_value).get_image()
		img.decompress()
		if img.has_mipmaps():
			img.clear_mipmaps()
		var skin_c: Color = c.skin
		for y in range(0, 22):
			var half := int(maxf(0.0, 6.0 - y * 0.28))
			for x in range(32 - half, 33 + half):
				img.set_pixel(x, y, skin_c.darkened(0.12 + y * 0.004))
			img.set_pixel(32 - half - 1, y, shirt_col.darkened(0.35))
			img.set_pixel(32 + half + 1, y, shirt_col.darkened(0.35))
		img.generate_mipmaps()
		torso_mat = tex_mat(ImageTexture.create_from_image(img))
		torso_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	parts["torso"] = mesh(body, loft([
		[0.97, 0.137, 0.097], [1.08, 0.142 * bulk, 0.1], [1.2, 0.168 * bulk, 0.118, -0.008],
		[1.31, 0.186 * bulk, 0.114, -0.004], [1.38, 0.18 * bulk, 0.1], [1.43, 0.115, 0.075], [1.47, 0.055, 0.05],
	], 10), Vector3.ZERO, torso_mat)
	mesh(body, cyl(0.048, 0.056, 0.11, 8), Vector3(0, 1.48, 0.006), skin)

	for side in [-1, 1]:
		var sfx := "_l" if side < 0 else "_r"
		# Leg: hip -> knee -> foot. Trousers bag out at the knee and bunch over the boot.
		var hip := Node3D.new()
		hip.position = Vector3(0.085 * side * hipw, 0.86, 0)
		body.add_child(hip)
		var L := leg_len
		mesh(hip, cyl(0.07 * baggy * limb, 0.088 * maxf(1.0, baggy * 0.95) * limb, 0.44 * L, 8), Vector3(0, -0.21 * L, 0), pants)
		var knee := Node3D.new()
		knee.position.y = -0.42 * L
		hip.add_child(knee)
		mesh(knee, sphere(0.072 * baggy * limb, 8, 5), Vector3(0, 0.0, 0), pants)
		mesh(knee, cyl(0.064 * baggy * limb, 0.07 * baggy * limb, 0.3 * L, 8), Vector3(0, -0.15 * L, 0), pants)
		mesh(knee, cyl(0.06 * limb, 0.066 * limb, 0.17 * L, 8), Vector3(0, -0.4 * L + 0.085 * L, 0), boots)
		mesh(knee, cyl(0.074 * limb, 0.066 * limb, 0.05, 8), Vector3(0, -0.4 * L + 0.165 * L, 0), boots)
		var foot := mesh(knee, sphere(1.0, 8, 5), Vector3(0, -0.4 * L, -0.05), boots)
		foot.scale = Vector3(0.068, 0.052, 0.14) * limb
		parts["leg" + sfx] = hip
		parts["shin" + sfx] = knee
		# Arm: shoulder -> elbow -> hand
		var sh := Node3D.new()
		sh.position = Vector3(0.19 * bulk * side, 1.375, 0)
		body.add_child(sh)
		var splay := Node3D.new()
		splay.rotation.z = 0.09 * side
		sh.add_child(splay)
		var cap := mesh(splay, sphere(1.0, 8, 5), Vector3(0, -0.035, 0), sleeve)
		cap.scale = Vector3(0.05, 0.055, 0.052) * limb
		var A := arm_len
		mesh(splay, cyl(0.046 * limb, 0.057 * limb, 0.3 * A, 8), Vector3(0, -0.15 * A, 0), sleeve)
		var el := Node3D.new()
		el.position.y = -0.29 * A
		el.rotation.x = 0.12
		splay.add_child(el)
		mesh(el, cyl(0.038 * limb, 0.047 * limb, 0.24 * A, 8), Vector3(0, -0.12 * A, 0), forearm)
		if c.has("cuffs"):
			mesh(el, cyl(0.048 * limb, 0.043 * limb, 0.045, 8), Vector3(0, -0.225 * A, 0), forearm)
		var hd := mesh(el, sphere(1.0, 8, 5), Vector3(0, -0.3 * A, -0.008), hand)
		hd.scale = Vector3(0.042, 0.064, 0.054) * hand_s
		var thumb := mesh(el, sphere(1.0, 6, 4), Vector3(-0.028 * side * hand_s, -0.3 * A + 0.015, -0.035 * hand_s), hand)
		thumb.scale = Vector3(0.016, 0.03, 0.016) * hand_s
		parts["arm" + sfx] = sh
		parts["forearm" + sfx] = el

	# Head: smooth skull with a painted face, small nose and ears.
	var head := Node3D.new()
	head.position.y = 1.5
	body.add_child(head)
	var hs: float = c.get("head_scale", 1.25)
	head.scale = Vector3.ONE * hs
	mesh(head, loft(rings_offset(HEAD_RINGS, -1.5), 14), Vector3.ZERO, tex_mat(face_tex(c)))
	var nose := mesh(head, sphere(1.0, 6, 4), Vector3(0, 0.104, -0.108), skin)
	nose.scale = Vector3(0.011, 0.016, 0.013)
	for side in [-1, 1]:
		if c.get("pointed_ears", false):
			var ear := mesh(head, cyl(0.0, 0.03, 0.08, 5), Vector3(0.108 * side, 0.14, 0.02), skin)
			ear.basis = (Basis.looking_at(Vector3(side * 0.9, 0.22, 0.5).normalized(), Vector3.UP) * Basis(Vector3.RIGHT, -PI * 0.5)) * Basis.from_scale(Vector3(1.0, 1.0, 0.45))
		else:
			var ear2 := mesh(head, sphere(1.0, 6, 4), Vector3(0.104 * side, 0.135, 0.008), skin)
			ear2.scale = Vector3(0.018, 0.036, 0.026)
	if c.has("glow_eyes"):
		var g := glow(c.glow_eyes)
		for side in [-1, 1]:
			mesh(head, sphere(0.012, 6, 3), Vector3(0.04 * side, 0.146, -0.106), g)

	var style: String = c.get("hair_style", "short")
	if style != "none":
		mesh(head, loft(rings_offset(HAIR_CAP, -1.5), 12), Vector3.ZERO, hair)
	match style:
		"spiky":
			hair_spikes(head, hair, SPIKES_HERO, 1.12)
		"short":
			hair_spikes(head, hair, SPIKES_SHORT, 1.1)
		"stringy":
			hair_spikes(head, hair, SPIKES_STRINGY)
		"long":
			mesh(head, loft([
				[-0.16, 0.08, 0.03, 0.09], [-0.06, 0.108, 0.048, 0.095], [0.06, 0.115, 0.062, 0.07], [0.2, 0.108, 0.072, 0.05],
			], 10), Vector3.ZERO, hair)
			hair_spikes(head, hair, [[-20, 40, 0.08, 0.045, -0.5], [15, 42, 0.08, 0.045, -0.5], [0, 70, 0.07, 0.05, 0.2]])
		"bun":
			mesh(head, sphere(0.07, 8, 5), Vector3(0, 0.27, 0.09), hair)
			hair_spikes(head, hair, [[-60, 40, 0.05, 0.04, 0.0], [60, 40, 0.05, 0.04, 0.0], [0, 60, 0.05, 0.05, 0.1]])
	parts["head"] = head
	return parts


static func yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)
