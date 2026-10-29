extends SceneTree
var H := OS.get_environment("HERO_DIR").path_join("")
func f32(n): return FileAccess.get_file_as_bytes(H + n).to_float32_array()
func v3(n):
	var f = f32(n); var a := PackedVector3Array(); a.resize(f.size() / 3)
	for i in a.size(): a[i] = Vector3(f[i*3], f[i*3+1], f[i*3+2])
	return a
func _init():
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v3("hero_pos.bin")
	arrays[Mesh.ARRAY_NORMAL] = v3("hero_nrm.bin")
	var uvf = f32("hero_uv.bin"); var uv := PackedVector2Array(); uv.resize(uvf.size() / 2)
	for i in uv.size(): uv[i] = Vector2(uvf[i*2], uvf[i*2+1])
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var cf = f32("hero_col.bin"); var col := PackedColorArray(); col.resize(cf.size() / 4)
	for i in col.size(): col[i] = Color(cf[i*4], cf[i*4+1], cf[i*4+2], cf[i*4+3])
	arrays[Mesh.ARRAY_COLOR] = col
	arrays[Mesh.ARRAY_BONES] = FileAccess.get_file_as_bytes(H + "hero_bones.bin").to_int32_array()
	arrays[Mesh.ARRAY_WEIGHTS] = f32("hero_weights.bin")
	arrays[Mesh.ARRAY_INDEX] = FileAccess.get_file_as_bytes(H + "hero_idx.bin").to_int32_array()
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var img := Image.load_from_file(H + "hero_front.png")
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://assets/hero/hero.gdshader")
	sm.set_shader_parameter("front_tex", tex)
	am.surface_set_material(0, sm)
	var rig = JSON.parse_string(FileAccess.get_file_as_string(H + "hero_rig.json"))
	am.set_meta("rig", rig)
	var err := ResourceSaver.save(am, "res://assets/hero/hero_mesh.res", ResourceSaver.FLAG_COMPRESS)
	print("saved ", err)
	quit()
