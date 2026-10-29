extends Node
var W := OS.get_environment("HERO_WORK").path_join("")
func readf(n: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(W + n)
func _ready():
	var p := readf("pos.bin").to_float32_array()
	var nrm := readf("nrm.bin").to_float32_array()
	var idx := readf("idx.bin").to_int32_array()
	var P := PackedVector3Array(); P.resize(p.size() / 3)
	var Nn := PackedVector3Array(); Nn.resize(p.size() / 3)
	for i in P.size():
		P[i] = Vector3(p[i*3], p[i*3+1], p[i*3+2])
		Nn[i] = Vector3(nrm[i*3], nrm[i*3+1], nrm[i*3+2])
	# glTF winding is counter-clockwise; Godot's is clockwise
	for t in idx.size() / 3:
		var a := idx[t*3+1]
		idx[t*3+1] = idx[t*3+2]
		idx[t*3+2] = a
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = P
	arrays[Mesh.ARRAY_NORMAL] = Nn
	arrays[Mesh.ARRAY_INDEX] = idx
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var t0 := Time.get_ticks_msec()
	im.generate_lods(25.0, 60.0, [])
	print("[D] lods in %d ms" % (Time.get_ticks_msec() - t0))
	var n := im.get_surface_lod_count(0)
	for i in n:
		var li := im.get_surface_lod_indices(0, i)
		print("[D] lod %d size %.4f tris %d" % [i, im.get_surface_lod_size(0, i), li.size() / 3])
		var f := FileAccess.open(W + "lod_%d.bin" % i, FileAccess.WRITE)
		f.store_buffer(li.to_byte_array())
		f.close()
	get_tree().quit()
