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


## Builds a blocky humanoid facing -Z with its feet at the origin.
## Returns the animatable parts (pivot, body, head, arm_l/r, leg_l/r).
static func humanoid(model: Node3D, c: Dictionary) -> Dictionary:
	var pivot := Node3D.new()
	pivot.position.y = 0.85
	model.add_child(pivot)
	var body := Node3D.new()
	body.position.y = -0.85
	pivot.add_child(body)
	var skin := mat(c.skin)
	var shirt := mat(c.shirt)
	var pants := mat(c.pants)
	var hair := mat(c.hair)
	var boots := mat(c.get("boots", Color(0.2, 0.14, 0.1)))
	var sleeve := mat(c.get("arm", c.shirt))
	var parts := {"pivot": pivot, "body": body}
	for side in [-1, 1]:
		var leg := Node3D.new()
		leg.position = Vector3(0.13 * side, 0.8, 0)
		body.add_child(leg)
		mesh(leg, box_mesh(Vector3(0.2, 0.8, 0.22)), Vector3(0, -0.4, 0), pants)
		mesh(leg, box_mesh(Vector3(0.22, 0.14, 0.3)), Vector3(0, -0.74, -0.04), boots)
		parts["leg_l" if side < 0 else "leg_r"] = leg
		var arm := Node3D.new()
		arm.position = Vector3(0.36 * side, 1.4, 0)
		body.add_child(arm)
		mesh(arm, box_mesh(Vector3(0.15, 0.6, 0.16)), Vector3(0, -0.28, 0), sleeve)
		mesh(arm, box_mesh(Vector3(0.14, 0.14, 0.14)), Vector3(0, -0.63, 0), skin)
		parts["arm_l" if side < 0 else "arm_r"] = arm
	parts["torso"] = mesh(body, box_mesh(Vector3(0.55, 0.66, 0.32)), Vector3(0, 1.12, 0), shirt)
	var head := Node3D.new()
	head.position.y = 1.47
	body.add_child(head)
	mesh(head, box_mesh(Vector3(0.36, 0.38, 0.36)), Vector3(0, 0.2, 0), skin)
	mesh(head, box_mesh(Vector3(0.4, 0.13, 0.4)), Vector3(0, 0.42, 0.02), hair)
	mesh(head, box_mesh(Vector3(0.4, 0.32, 0.1)), Vector3(0, 0.27, 0.17), hair)
	var eye: StandardMaterial3D
	if c.has("eye"):
		eye = glow(c.eye)
	else:
		eye = mat(Color(0.06, 0.05, 0.05))
	mesh(head, box_mesh(Vector3(0.07, 0.07, 0.02)), Vector3(-0.08, 0.22, -0.185), eye)
	mesh(head, box_mesh(Vector3(0.07, 0.07, 0.02)), Vector3(0.08, 0.22, -0.185), eye)
	parts["head"] = head
	return parts


static func yaw_of(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)
