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
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if tex != null:
		m.albedo_texture = tex
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * tri_scale
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func glow(color: Color) -> StandardMaterial3D:
	return mat(color, null, 0.25, true)


static func mesh(parent: Node, m: Mesh, pos: Vector3, material: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	var unlit := material is BaseMaterial3D and ((material as BaseMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED or (material as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if unlit else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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
	m.albedo_color = Color(0, 0, 0, 0.28)
	var c := cyl(radius, radius, 0.02, 10)
	return mesh(parent, c, Vector3(0, 0.09, 0), m)


## Sweeps a smooth closed shape through elliptical cross-sections.
## rings: [y, radius_x, radius_z, (z offset)] listed bottom to top.
## UV u = 0.5 is the front (-Z); v = 0 is the top ring.
static func loft(rings: Array, segs: int = 10, uv_by_height: bool = false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := rings.size()
	var y0: float = float(rings[0][0])
	var y1: float = float(rings[n - 1][0])
	for i in n:
		var r: Array = rings[i]
		var cz: float = r[3] if r.size() > 3 else 0.0
		var v := 1.0 - float(i) / float(n - 1)
		if uv_by_height:
			v = (y1 - float(r[0])) / maxf(y1 - y0, 0.001)
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
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
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
	var hi := kind in ["cloth", "skin", "hair", "leather", "rope", "metal"]
	var W := 128 if hi else 64
	var H := W
	var ks := W / 64
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
	var strokes := (30 if kind == "skin" or kind == "grass" else 110) * ks * ks
	if kind == "cloth":
		strokes = 70 * ks * ks
	for i in strokes:
		var x0 := rng.randi_range(0, W - 1)
		var y0 := rng.randi_range(0, H - 1)
		var length := rng.randi_range(4, 16) * ks
		if kind == "cloth":
			length = rng.randi_range(2, 6) * ks
		var amt := rng.randf_range(-0.14, 0.14) * (0.4 if kind == "skin" or kind == "grass" else (0.45 if kind == "cloth" else 1.0))
		var horizontal := kind == "metal" or kind == "leather"
		for k in length:
			var px := posmod(x0 + (k if horizontal else 0), W)
			var py := clampi(y0 + (0 if horizontal else k), 0, H - 1)
			var c := img.get_pixel(px, py)
			img.set_pixel(px, py, c.lightened(amt) if amt > 0.0 else c.darkened(-amt))
	match kind:
		"cloth":
			# Broad soft folds: a shadowed trough with a lit ridge beside it, fading upward.
			for f in 6:
				var fx := rng.randf_range(0.0, float(W))
				var width := rng.randf_range(3.0, 6.0) * ks
				var y_start := rng.randi_range(int(H * 0.15), int(H * 0.6))
				for y in range(y_start, H):
					var fade := clampf(float(y - y_start) / (H * 0.3), 0.0, 1.0)
					var cxp := fx + sin(y * 0.06 / ks + f * 2.0) * 2.0 * ks
					for dx in range(int(-width * 2.0), int(width * 2.0) + 1):
						var x := posmod(int(cxp) + dx, W)
						var tt := float(dx) / width
						var shade := exp(-tt * tt) * 0.16 - exp(-(tt - 1.6) * (tt - 1.6)) * 0.08
						var c := img.get_pixel(x, y)
						img.set_pixel(x, y, c.darkened(shade * fade) if shade > 0.0 else c.lightened(-shade * fade))
			# Stitched hem along the bottom edge (cuffs, tunic hem, trouser legs)
			for x in W:
				for t in ks:
					img.set_pixel(x, H - 2 - t, img.get_pixel(x, H - 2 - t).darkened(0.18))
				if x % (4 * ks) < 2 * ks:
					img.set_pixel(x, H - 4 * ks, img.get_pixel(x, H - 4 * ks).darkened(0.32))
		"rope":
			for y in H:
				for x in W:
					if posmod(x + y, 8) < 3:
						img.set_pixel(x, y, img.get_pixel(x, y).darkened(0.32))
					elif posmod(x + y, 8) == 4:
						img.set_pixel(x, y, img.get_pixel(x, y).lightened(0.15))
		"hair":
			for i in 40 * ks:
				var x := rng.randi_range(0, W - 1)
				var amt := rng.randf_range(0.1, 0.3)
				for y in H:
					var c := img.get_pixel(x, y)
					img.set_pixel(x, y, c.darkened(amt) if i % 2 == 0 else c.lightened(amt * 0.6))
		"leather":
			for x in W:
				img.set_pixel(x, 6 * ks, img.get_pixel(x, 6 * ks).darkened(0.35))
				if x % (4 * ks) < 2 * ks:
					img.set_pixel(x, 8 * ks, img.get_pixel(x, 8 * ks).lightened(0.2))
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
			# Soft painted dabs rather than scratches, so it reads well up close at high resolution.
			for i in 160:
				var cx := rng.randi_range(0, W - 1)
				var cy := rng.randi_range(0, H - 1)
				var r := rng.randf_range(1.5, 4.5)
				var amt := rng.randf_range(0.03, 0.08)
				var light := rng.randf() < 0.5
				for yy in range(cy - 5, cy + 6):
					for xx in range(cx - 5, cx + 6):
						var d := Vector2(xx - cx, (yy - cy) * 1.6).length()
						if d <= r:
							var px := posmod(xx, W)
							var py := posmod(yy, H)
							var c := img.get_pixel(px, py)
							var a := amt * (1.0 - d / r)
							img.set_pixel(px, py, c.lightened(a) if light else c.darkened(a))
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
			for y in range(18 * ks, 26 * ks):
				for x in W:
					img.set_pixel(x, y, img.get_pixel(x, y).lightened(0.22 * (1.0 - absf(y - 22.0 * ks) / (4.0 * ks))))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


static func paint_mat(base: Color, kind: String = "cloth", seed_value: int = 7) -> StandardMaterial3D:
	var m := tex_mat(paint_tex(base, kind, seed_value))
	return m


static var _face_cache := {}


## Soft-edged blended dab, in face-layout units (256 x 96), scaled by S.
static func _soft(img: Image, S: float, cx: float, cy: float, rx: float, ry: float, col: Color, strength: float) -> void:
	for y in range(int((cy - ry) * S), int((cy + ry) * S) + 1):
		for x in range(int((cx - rx) * S), int((cx + rx) * S) + 1):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var d := Vector2((x / S - cx) / rx, (y / S - cy) / ry).length()
			if d < 1.0:
				var t := (1.0 - d * d) * strength
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(col, t))


## Hard-edged ellipse with a one-pixel antialiased rim.
static func _fill(img: Image, S: float, cx: float, cy: float, rx: float, ry: float, col: Color) -> void:
	for y in range(int((cy - ry) * S) - 1, int((cy + ry) * S) + 2):
		for x in range(int((cx - rx) * S) - 1, int((cx + rx) * S) + 2):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var d := Vector2((x / S - cx) / rx, (y / S - cy) / ry).length()
			var edge := 1.0 / (minf(rx, ry) * S)
			if d < 1.0 + edge:
				var a := clampf((1.0 + edge - d) / (2.0 * edge), 0.0, 1.0)
				img.set_pixel(x, y, img.get_pixel(x, y).lerp(col, a))


## Tapered brush stroke along a polyline (thickness in layout units).
static func _stroke(img: Image, S: float, pts: Array, w0: float, w1: float, col: Color) -> void:
	var total := 0.0
	for i in pts.size() - 1:
		total += (pts[i + 1] as Vector2).distance_to(pts[i])
	var run := 0.0
	for i in pts.size() - 1:
		var p0: Vector2 = pts[i]
		var p1: Vector2 = pts[i + 1]
		var seg := p0.distance_to(p1)
		var n := maxi(2, int(seg * S * 2.0))
		for j in n:
			var t := float(j) / float(n)
			var p := p0.lerp(p1, t)
			var w := lerpf(w0, w1, (run + seg * t) / maxf(total, 0.001))
			_fill(img, S, p.x, p.y, w * 0.5, w * 0.5, col)
		run += seg


## Paints a stylized face (big shaded eyes, tapered brows, nose, mouth) plus the
## hairline onto the head's wrap-around texture. u = 0.5 is the front.
static func face_tex(c: Dictionary) -> ImageTexture:
	var res: int = c.get("face_res", 2)
	var key := str([c.skin, c.hair, c.get("face", ""), c.get("hair_style", "") == "long", c.get("hair_style", "") == "none", c.get("eye_color"), c.has("smudge"), c.get("beard"), res])
	if _face_cache.has(key):
		return _face_cache[key]
	var S := float(res)
	var W := 256 * res
	var H := 96 * res
	var img := Image.create_empty(W, H, false, Image.FORMAT_RGB8)
	var skin: Color = c.skin
	var hair: Color = c.hair
	var face: String = c.get("face", "")
	var style: String = c.get("hair_style", "short")
	var fx := 128.0
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)

	# Base skin with painted form shading: lit brow, shadowed jaw and sides.
	for y in H:
		var v := y / S
		for x in W:
			var u := x / S
			var col := skin
			col = col.lightened(maxf(0.0, (40.0 - v) / 40.0) * 0.06)
			if v > 74.0:
				col = col.darkened((v - 74.0) * 0.007)
			var du := absf(u - fx) / 256.0
			col = col.darkened(clampf((du - 0.07) * 0.9, 0.0, 0.2))
			if face == "zombie" and rng.randf() < 0.05:
				col = col.darkened(rng.randf_range(0.08, 0.25))
			img.set_pixel(x, y, col)
	# Cheekbone and temple shadows give the face some structure
	for side in [-1.0, 1.0]:
		_soft(img, S, fx + side * 30.0, 64.0, 9.0, 14.0, skin.darkened(0.3), 0.35)
		_soft(img, S, fx + side * 27.0, 44.0, 7.0, 8.0, skin.darkened(0.2), 0.25)
	_soft(img, S, fx, 82.0, 22.0, 8.0, skin.darkened(0.3), 0.4)
	if face == "zombie":
		for i in 14:
			_soft(img, S, rng.randf_range(80, 176), rng.randf_range(30, 88), rng.randf_range(3, 7), rng.randf_range(2, 5), skin.darkened(0.35), 0.35)
	else:
		for side in [-1.0, 1.0]:
			_soft(img, S, fx + side * 22.0, 62.0, 9.0, 5.0, Color(0.93, 0.5, 0.45), 0.16)
	if c.has("smudge"):
		var dirt := Color(0.5, 0.38, 0.3)
		_soft(img, S, fx - 22.0, 60.5, 8.0, 3.6, dirt, 0.32)
		_soft(img, S, fx + 23.0, 59.5, 7.0, 3.2, dirt, 0.26)
		_soft(img, S, fx + 27.0, 64.0, 2.5, 1.6, dirt, 0.3)

	# Ears
	for ex in [fx - 64.0, fx + 64.0]:
		_soft(img, S, ex, 50.0, 6.0, 9.0, skin.darkened(0.2), 0.7)
		_soft(img, S, ex, 50.0, 2.8, 5.0, skin.darkened(0.35), 0.6)

	# Hair painted on the scalp under the hair meshes.
	if style != "none":
		for x in W:
			var u := x / S
			var du := absf(u - fx) / 256.0
			var line := 30.0 + sin(u * 0.45) * 1.5
			if du > 0.16:
				line = lerpf(30.0, 48.0, clampf((du - 0.16) / 0.06, 0.0, 1.0))
			if du > 0.22:
				line = lerpf(48.0, 84.0 if style != "long" else 96.0, clampf((du - 0.22) / 0.08, 0.0, 1.0))
			line += sin(u * 0.9) * 1.2
			for y in int(clampf(line * S, 0, H)):
				var shade := rng.randf_range(0.0, 0.16) + y / S / 320.0
				img.set_pixel(x, y, hair.darkened(shade))
			# soft shadow the hair casts onto the forehead
			for t in int(4 * S):
				var yy := int(line * S) + t
				if yy < H:
					img.set_pixel(x, yy, img.get_pixel(x, yy).darkened(0.18 * (1.0 - t / (4.0 * S))))

	var eye_col: Color = c.get("eye_color", Color(0.22, 0.2, 0.25))
	var brow := hair.darkened(0.42)
	var lash := Color(0.11, 0.07, 0.06)
	for side in [-1.0, 1.0]:
		var ex: float = fx + side * 16.0
		var ey := 51.0
		if face == "zombie":
			_soft(img, S, ex, ey - 1.0, 10.0, 8.0, skin.darkened(0.6), 0.9)
			_fill(img, S, ex, ey, 3.6, 3.2, Color(1.0, 0.25, 0.12))
			_fill(img, S, ex, ey, 1.5, 1.5, Color(1.0, 0.85, 0.5))
			_stroke(img, S, [Vector2(ex - side * 6.0, 43.0), Vector2(ex + side * 6.0, 41.0)], 1.2, 0.6, brow)
			continue
		var big := 1.05 if face == "kid" else 0.88
		var rx := 6.8 * big
		var ry := 5.5 * big
		# Socket shading and lid crease
		_soft(img, S, ex, ey - 4.0, 10.0, 6.0, skin.darkened(0.3), 0.32)
		_stroke(img, S, [Vector2(ex - rx, ey - ry - 1.2), Vector2(ex, ey - ry - 2.6), Vector2(ex + rx, ey - ry - 1.2)], 0.7, 0.5, skin.darkened(0.3))
		# White of the eye, shaded under the lid
		_fill(img, S, ex, ey, rx, ry, Color(0.96, 0.95, 0.92))
		_soft(img, S, ex, ey - ry * 0.8, rx * 1.05, ry * 0.65, Color(0.62, 0.56, 0.56), 0.55)
		# Iris: darker rim, lighter at the bottom, then pupil and highlights
		var ix: float = ex - side * 0.5
		var iy := ey + 0.6
		var irx := 4.4 * big
		var iry := 5.0 * big
		for y in range(int((iy - iry) * S), int((iy + iry) * S) + 1):
			for x in range(int((ix - irx) * S), int((ix + irx) * S) + 1):
				var d := Vector2((x / S - ix) / irx, (y / S - iy) / iry).length()
				var dw := Vector2((x / S - ex) / rx, (y / S - ey) / ry).length()
				if d < 1.0 and dw < 1.0:
					var low := clampf((y / S - iy) / iry, 0.0, 1.0)
					var col := eye_col.lerp(eye_col.lightened(0.45), low * 0.7).darkened(d * d * d * 0.55)
					img.set_pixel(x, y, col)
		_fill(img, S, ix, iy + 0.2, 2.1 * big, 2.5 * big, Color(0.03, 0.02, 0.03))
		_soft(img, S, ix, iy - iry * 0.5, irx, iry * 0.55, Color(0.0, 0.0, 0.0), 0.35)
		_fill(img, S, ex - 1.9 - side * 0.5, ey - 1.9, 1.45, 1.45, Color(1, 1, 1))
		_fill(img, S, ex + 1.7, ey + 2.5, 0.7, 0.7, Color(0.92, 0.93, 0.98))
		# Heavy upper lash line with a little flick at the outer corner, softer lower lid
		var lid := []
		for i in 9:
			var t := -1.0 + i * 0.25
			lid.append(Vector2(ex + t * rx * side, ey - ry * sqrt(maxf(0.0, 1.0 - t * t)) * 0.97 + 0.2))
		_stroke(img, S, lid, 1.0, 1.9, lash)
		_stroke(img, S, [Vector2(ex + rx * side, ey - 0.6), Vector2(ex + (rx + 2.2) * side, ey - 2.8)], 1.3, 0.3, lash)
		var low_lid := []
		for i in 5:
			var t := 0.15 + i * 0.2
			low_lid.append(Vector2(ex + t * rx * side, ey + ry * sqrt(maxf(0.0, 1.0 - t * t)) * 0.95))
		_stroke(img, S, low_lid, 0.4, 0.8, skin.darkened(0.35))
		if face == "worried":
			_soft(img, S, ex, ey + ry + 2.0, rx, 1.8, skin.darkened(0.25), 0.3)
		# Brows: thick at the inner end, tapering outward
		var inner_y := 42.0
		var mid_y := 40.5
		var outer_y := 41.5
		match face:
			"worried":
				inner_y = 38.6
				mid_y = 40.2
				outer_y = 42.6
			"stern":
				inner_y = 43.8
				mid_y = 41.0
				outer_y = 39.6
			"old":
				inner_y = 40.5
				mid_y = 40.0
				outer_y = 42.5
			"kid":
				inner_y = 41.5
				mid_y = 39.2
				outer_y = 41.0
		var bw := 2.6 if face != "old" else 1.8
		_stroke(img, S, [Vector2(ex - side * 6.5, inner_y), Vector2(ex + side * 1.0, mid_y), Vector2(ex + side * 8.5, outer_y)], bw, 0.8, brow)
		if face == "old":
			_stroke(img, S, [Vector2(ex + side * 8.0, ey + 1.0), Vector2(ex + side * 11.0, ey + 3.0)], 0.6, 0.3, skin.darkened(0.3))
			_stroke(img, S, [Vector2(ex + side * 8.0, ey + 3.5), Vector2(ex + side * 10.5, ey + 5.5)], 0.6, 0.3, skin.darkened(0.25))
	if face == "worried":
		_stroke(img, S, [Vector2(fx - 4.0, 41.5), Vector2(fx - 1.5, 44.0)], 0.6, 0.3, skin.darkened(0.2))
		_stroke(img, S, [Vector2(fx + 4.0, 41.5), Vector2(fx + 1.5, 44.0)], 0.6, 0.3, skin.darkened(0.2))
	if face == "old":
		for i in 2:
			_stroke(img, S, [Vector2(fx - 9.0, 33.0 + i * 2.5), Vector2(fx, 32.5 + i * 2.5), Vector2(fx + 9.0, 33.0 + i * 2.5)], 0.5, 0.5, skin.darkened(0.16))

	# Nose: shadowed side, lit bridge and tip, small nostrils
	_soft(img, S, fx + 3.2, 56.0, 2.4, 6.5, skin.darkened(0.28), 0.45)
	_soft(img, S, fx - 0.8, 54.0, 1.4, 5.0, skin.lightened(0.18), 0.35)
	_soft(img, S, fx - 0.4, 59.5, 2.4, 1.8, skin.lightened(0.15), 0.4)
	_fill(img, S, fx - 2.4, 61.3, 1.0, 0.6, skin.darkened(0.45))
	_fill(img, S, fx + 2.4, 61.3, 1.0, 0.6, skin.darkened(0.45))

	# Mouth
	var lip := skin.lerp(Color(0.66, 0.26, 0.24), 0.45)
	match face:
		"zombie":
			_fill(img, S, fx, 70.5, 8.0, 4.0, Color(0.12, 0.03, 0.03))
			for t in [-5.5, -2.5, 1.0, 4.0]:
				_fill(img, S, fx + t, 67.6, 1.0, 1.2, Color(0.85, 0.8, 0.6))
			_fill(img, S, fx - 0.5, 73.0, 1.0, 1.0, Color(0.85, 0.8, 0.6))
		"worried":
			_stroke(img, S, [Vector2(fx - 7.5, 72.4), Vector2(fx - 3.5, 70.6), Vector2(fx, 70.2), Vector2(fx + 3.5, 70.6), Vector2(fx + 7.5, 72.4)], 0.9, 1.0, lip.darkened(0.45))
			_soft(img, S, fx, 73.4, 4.6, 1.5, lip, 0.55)
			_soft(img, S, fx - 0.5, 73.0, 2.0, 0.6, lip.lightened(0.25), 0.4)
		"kid":
			_stroke(img, S, [Vector2(fx - 7.0, 69.5), Vector2(fx - 3.0, 71.4), Vector2(fx, 71.7), Vector2(fx + 3.0, 71.4), Vector2(fx + 7.0, 69.5)], 0.9, 0.9, lip.darkened(0.45))
			_soft(img, S, fx, 73.0, 4.0, 1.3, lip, 0.45)
		"stern":
			_stroke(img, S, [Vector2(fx - 6.5, 71.2), Vector2(fx, 70.8), Vector2(fx + 6.5, 71.2)], 1.0, 1.0, lip.darkened(0.45))
		_:
			_stroke(img, S, [Vector2(fx - 6.0, 70.6), Vector2(fx, 71.2), Vector2(fx + 6.0, 70.6)], 0.9, 0.9, lip.darkened(0.42))
			_soft(img, S, fx, 72.8, 4.0, 1.3, lip, 0.45)
	if face == "old":
		_stroke(img, S, [Vector2(fx - 9.0, 63.0), Vector2(fx - 10.5, 69.0)], 0.6, 0.4, skin.darkened(0.22))
		_stroke(img, S, [Vector2(fx + 9.0, 63.0), Vector2(fx + 10.5, 69.0)], 0.6, 0.4, skin.darkened(0.22))
	if c.has("beard"):
		var bc: Color = c.beard
		for y in H:
			var v := y / S
			if v < 60.0:
				continue
			for x in W:
				var u := x / S
				var inside := absf(u - fx) < 36.0 - maxf(0.0, v - 84.0) * 2.0
				var mouth := v >= 68.0 and v <= 74.0 and absf(u - fx) < 8.0
				if inside and not mouth and (v > 64.0 or absf(u - fx) < 11.0 or absf(u - fx) > 23.0):
					img.set_pixel(x, y, bc.darkened(rng.randf_range(0.0, 0.25)))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_face_cache[key] = tex
	return tex


const HEAD_RINGS := [
	[1.485, 0.025, 0.025, -0.01],
	[1.5, 0.045, 0.052, -0.026],
	[1.53, 0.066, 0.08, -0.018],
	[1.575, 0.089, 0.103, -0.004],
	[1.63, 0.103, 0.114, 0.0],
	[1.68, 0.107, 0.116, 0.005],
	[1.73, 0.1, 0.112, 0.01],
	[1.77, 0.078, 0.092, 0.012],
	[1.795, 0.042, 0.052, 0.01],
	[1.805, 0.002, 0.002, 0.01],
]

const HAIR_CAP := [
	[1.6, 0.102, 0.102, 0.038],
	[1.66, 0.112, 0.122, 0.03],
	[1.72, 0.114, 0.126, 0.018],
	[1.75, 0.106, 0.122, 0.006],
	[1.77, 0.09, 0.105, 0.0],
	[1.81, 0.047, 0.057, 0.0],
	[1.822, 0.002, 0.002, 0.0],
]

# Chunky hair spikes: [azimuth° (0 front, 90 right), elevation°, length, base radius, upward tilt]
const SPIKES_HERO := [
	[-64, 50, 0.14, 0.05, -0.1, 0.1, 0.5], [62, 52, 0.14, 0.05, -0.05, 0.1, 0.5], [-10, 64, 0.13, 0.055, 0.45, -0.2], [18, 62, 0.12, 0.05, 0.4, -0.15],
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


static var _clump_cache := {}


## A tapered, slightly flattened lock of hair that curls along local +Z.
static func clump_mesh(length: float, radius: float, bend: float, flat: float = 0.6) -> ArrayMesh:
	var key := "%.3f_%.3f_%.2f_%.2f" % [length, radius, bend, flat]
	if _clump_cache.has(key):
		return _clump_cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 6
	var segs := 7
	for i in steps + 1:
		var t := float(i) / float(steps)
		var ctr := Vector3(0, t * length, bend * length * t * t)
		var r := radius * pow(1.0 - t, 0.8) + 0.0015
		for k in segs + 1:
			var a := -PI + TAU * float(k) / float(segs)
			st.set_uv(Vector2(float(k) / float(segs), 1.0 - t))
			st.add_vertex(ctr + Vector3(sin(a) * r, 0, -cos(a) * r * flat))
	for i in steps:
		for k in segs:
			var a0 := i * (segs + 1) + k
			var b0 := a0 + segs + 1
			st.add_index(a0)
			st.add_index(a0 + 1)
			st.add_index(b0)
			st.add_index(a0 + 1)
			st.add_index(b0 + 1)
			st.add_index(b0)
	st.generate_normals()
	var m := st.commit()
	_clump_cache[key] = m
	return m


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = maxf(height, radius * 2.0)
	c.radial_segments = 8
	c.rings = 3
	return c


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
		var bend: float = float(sp[6]) if sp.size() > 6 else 0.35
		var mi := mesh(head, clump_mesh(snappedf(length, 0.005), float(sp[3]) * size, bend, 0.62), base - dir * length * 0.08, m)
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
	], 16), Vector3.ZERO, pants)
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
	], 16), Vector3.ZERO, torso_mat)
	mesh(body, cyl(0.048, 0.056, 0.11, 12), Vector3(0, 1.48, 0.006), skin)

	for side in [-1, 1]:
		var sfx := "_l" if side < 0 else "_r"
		# Leg: hip -> knee -> foot. Trousers bag out at the knee and bunch over the boot.
		var hip := Node3D.new()
		hip.position = Vector3(0.085 * side * hipw, 0.86, 0)
		body.add_child(hip)
		var L := leg_len
		mesh(hip, cyl(0.07 * baggy * limb, 0.088 * maxf(1.0, baggy * 0.95) * limb, 0.44 * L, 12), Vector3(0, -0.21 * L, 0), pants)
		var knee := Node3D.new()
		knee.position.y = -0.42 * L
		hip.add_child(knee)
		mesh(knee, sphere(0.072 * baggy * limb, 8, 5), Vector3(0, 0.0, 0), pants)
		mesh(knee, cyl(0.064 * baggy * limb, 0.07 * baggy * limb, 0.3 * L, 12), Vector3(0, -0.15 * L, 0), pants)
		mesh(knee, cyl(0.06 * limb, 0.066 * limb, 0.17 * L, 12), Vector3(0, -0.4 * L + 0.085 * L, 0), boots)
		mesh(knee, cyl(0.074 * limb, 0.066 * limb, 0.05, 12), Vector3(0, -0.4 * L + 0.165 * L, 0), boots)
		var foot := mesh(knee, sphere(1.0, 12, 8), Vector3(0, -0.4 * L, -0.05), boots)
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
		var cap := mesh(splay, sphere(1.0, 12, 8), Vector3(0, -0.035, 0), sleeve)
		cap.scale = Vector3(0.044, 0.048, 0.046) * limb
		var A := arm_len
		mesh(splay, cyl(0.046 * limb, 0.057 * limb, 0.3 * A, 12), Vector3(0, -0.15 * A, 0), sleeve)
		var el := Node3D.new()
		el.position.y = -0.29 * A
		el.rotation.x = 0.12
		splay.add_child(el)
		mesh(el, cyl(0.038 * limb, 0.047 * limb, 0.24 * A, 12), Vector3(0, -0.12 * A, 0), forearm)
		if c.has("cuffs"):
			mesh(el, cyl(0.048 * limb, 0.043 * limb, 0.045, 12), Vector3(0, -0.225 * A, 0), forearm)
		# Hand: palm, four curled fingers and a thumb
		var palm := mesh(el, sphere(1.0, 10, 7), Vector3(0, -0.29 * A, -0.006), hand)
		palm.scale = Vector3(0.041, 0.048, 0.05) * hand_s
		for f in 4:
			var fxp := (-0.023 + f * 0.0153) * hand_s
			var fing := mesh(el, capsule(0.0108 * hand_s, 0.05 * hand_s), Vector3(fxp, -0.33 * A, -0.026 * hand_s), hand)
			fing.rotation = Vector3(1.05, 0, 0)
		var thumb := mesh(el, capsule(0.0122 * hand_s, 0.046 * hand_s), Vector3(-0.034 * side * hand_s, -0.3 * A, -0.026 * hand_s), hand)
		thumb.rotation = Vector3(0.75, 0, -0.55 * side)
		parts["arm" + sfx] = sh
		parts["forearm" + sfx] = el

	# Head: smooth skull with a painted face, small nose and ears.
	var head := Node3D.new()
	head.position.y = 1.5
	body.add_child(head)
	var hs: float = c.get("head_scale", 1.25)
	head.scale = Vector3.ONE * hs
	mesh(head, loft(rings_offset(HEAD_RINGS, -1.5), 22, true), Vector3.ZERO, tex_mat(face_tex(c)))
	var nose := mesh(head, sphere(1.0, 10, 6), Vector3(0, 0.098, -0.106), skin)
	nose.scale = Vector3(0.011, 0.017, 0.01)
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
		mesh(head, loft(rings_offset(HAIR_CAP, -1.5), 18), Vector3.ZERO, hair)
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


## Merges sibling meshes that share a material under each joint of a character,
## so detailed models stay cheap: one draw per material per moving part.
static func merge_children(root: Node) -> void:
	var nodes: Array = [root]
	var i := 0
	while i < nodes.size():
		var n: Node = nodes[i]
		i += 1
		var groups := {}
		for ch in n.get_children():
			if ch is MeshInstance3D and ch.get_child_count() == 0 and ch.material_override != null and not ch.has_meta("keep"):
				if not groups.has(ch.material_override):
					groups[ch.material_override] = []
				groups[ch.material_override].append(ch)
			elif ch is Node3D:
				nodes.append(ch)
		for key in groups:
			var list: Array = groups[key]
			if list.size() < 2:
				continue
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for mi in list:
				st.append_from(mi.mesh, 0, mi.transform)
			var merged := MeshInstance3D.new()
			merged.mesh = st.commit()
			merged.material_override = key
			merged.cast_shadow = list[0].cast_shadow
			n.add_child(merged)
			for mi in list:
				n.remove_child(mi)
				mi.free()
