extends Node3D
## Cottage interiors. Every village door leads to its own furnished room, built
## out of sight deep under the village. Walk into a door to go in; walk back
## out through it to leave. One house is Wenna's, sick in bed.

const B = preload("res://scripts/build.gd")
const NpcScript = preload("res://scripts/npc.gd")

const W := 11.0      # room width (x)
const D := 9.0       # room depth (z); the door is in the +Z wall
const H := 4.2
const DEPTH := -60.0
const SICK_HOUSE := 3
const SLOTS := [Vector3(-14, 0, -14), Vector3(0, 0, -14), Vector3(14, 0, -14), Vector3(-14, 0, 0),
	Vector3(14, 0, 0), Vector3(-14, 0, 14), Vector3(0, 0, 14), Vector3(14, 0, 14), Vector3(0, 0, 0)]

var main
var rooms: Array = []        # {origin, door_index}
var inside := -1             # room index the hero is in, -1 outdoors
var cooldown := 0.0
var fade: ColorRect
var fires: Array = []        # [OmniLight3D, base energy, flame mesh]
var rng := RandomNumberGenerator.new()


func build(doors: Array) -> void:
	rng.seed = 77
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(fade)
	for i in doors.size():
		var origin: Vector3 = SLOTS[i % SLOTS.size()] + Vector3(0, DEPTH, 0)
		var root := Node3D.new()
		root.position = origin
		add_child(root)
		build_room(root, i, doors[i])
		B.merge_children(root)
		rooms.append({"origin": origin, "door": i})


# ------------------------------------------------------------------ room building

func solid(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_y: float = 0.0) -> void:
	B.solid_box(parent, size, pos, mat, rot_y)


func build_room(root: Node3D, idx: int, door: Dictionary) -> void:
	var plaster := B.paint_mat((door.plaster as Color).darkened(0.08), "skin", 300 + idx)
	var beam := B.paint_mat(Color(0.33, 0.22, 0.14), "leather", 301)
	var floor_mat := B.paint_mat(Color(0.5, 0.36, 0.24), "leather", 302 + idx)
	var stone := B.paint_mat(Color(0.5, 0.48, 0.45), "stone", 303)
	var wood := B.paint_mat(Color(0.52, 0.36, 0.22), "leather", 304)
	var hw := W * 0.5
	var hd := D * 0.5
	# Floor planks, walls, ceiling with rafters
	solid(root, Vector3(W + 1, 0.4, D + 1), Vector3(0, -0.2, 0), floor_mat)
	for k in 10:
		B.mesh(root, B.box_mesh(Vector3(0.03, 0.01, D)), Vector3(-hw + 0.55 + k * 1.1, 0.005, 0), beam)
	solid(root, Vector3(W + 1, H, 0.4), Vector3(0, H * 0.5, -hd - 0.2), plaster)
	solid(root, Vector3(0.4, H, D + 1), Vector3(-hw - 0.2, H * 0.5, 0), plaster)
	solid(root, Vector3(0.4, H, D + 1), Vector3(hw + 0.2, H * 0.5, 0), plaster)
	# front wall in two halves around the doorway, and a lintel
	solid(root, Vector3(hw - 0.7, H, 0.4), Vector3(-(hw + 0.7) * 0.5, H * 0.5, hd + 0.2), plaster)
	solid(root, Vector3(hw - 0.7, H, 0.4), Vector3((hw + 0.7) * 0.5, H * 0.5, hd + 0.2), plaster)
	solid(root, Vector3(1.4, H - 2.3, 0.4), Vector3(0, 2.3 + (H - 2.3) * 0.5, hd + 0.2), plaster)
	# the doorway glows with daylight / night outside, and a mat in front of it
	var outside := B.glow(Color(0.85, 0.8, 0.65))
	main.window_mats.append(outside)
	B.mesh(root, B.box_mesh(Vector3(1.4, 2.3, 0.1)), Vector3(0, 1.15, hd + 0.42), outside)
	solid(root, Vector3(1.4, 2.3, 0.2), Vector3(0, 1.15, hd + 0.55), beam)
	B.mesh(root, B.box_mesh(Vector3(1.5, 0.02, 0.9)), Vector3(0, 0.01, hd - 0.6), B.paint_mat(Color(0.55, 0.42, 0.3), "rope"))
	solid(root, Vector3(W + 1, 0.3, D + 1), Vector3(0, H + 0.15, 0), plaster)
	for k in 5:
		B.mesh(root, B.box_mesh(Vector3(W, 0.25, 0.22)), Vector3(0, H - 0.15, -hd + 0.9 + k * 1.8), beam)
	for cx in [-hw + 0.12, hw - 0.12]:
		for cz in [-hd + 0.12, hd - 0.12]:
			B.mesh(root, B.box_mesh(Vector3(0.26, H, 0.26)), Vector3(cx, H * 0.5, cz), beam)
	# windows on the side walls
	var win := B.glow(Color(0.95, 0.8, 0.5))
	main.window_mats.append(win)
	for side in [-1, 1]:
		for wz in [-1.6, 1.6]:
			B.mesh(root, B.box_mesh(Vector3(0.05, 0.9, 0.8)), Vector3(side * (hw - 0.02), 2.0, wz), win)
			B.mesh(root, B.box_mesh(Vector3(0.08, 0.06, 0.9)), Vector3(side * (hw - 0.04), 2.0, wz), beam)
			B.mesh(root, B.box_mesh(Vector3(0.08, 1.0, 0.06)), Vector3(side * (hw - 0.04), 2.0, wz), beam)
	# Fireplace on the back wall, with a flickering fire
	var fx := -2.6 if idx % 2 == 0 else 2.6
	solid(root, Vector3(2.4, 2.4, 1.0), Vector3(fx, 1.2, -hd + 0.5), stone)
	B.mesh(root, B.box_mesh(Vector3(1.3, 1.0, 0.1)), Vector3(fx, 0.6, -hd + 1.02), B.glow(Color(0.06, 0.03, 0.02)))
	B.mesh(root, B.box_mesh(Vector3(0.7, 1.8, 0.7)), Vector3(fx, 3.3, -hd + 0.4), stone)
	B.mesh(root, B.box_mesh(Vector3(2.8, 0.15, 1.2)), Vector3(fx, 2.45, -hd + 0.55), beam)
	for lk in 2:
		B.mesh(root, B.cyl(0.08, 0.08, 0.8, 6), Vector3(fx, 0.18 + lk * 0.1, -hd + 1.15), wood, Vector3(0, 30 - lk * 60, 90))
	var flame := B.mesh(root, B.prism(Vector3(0.6, 0.6, 0.3)), Vector3(fx, 0.5, -hd + 1.15), B.glow(Color(1.0, 0.55, 0.15)))
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flame.set_meta("keep", true)
	var light := OmniLight3D.new()
	light.position = Vector3(fx, 1.0, -hd + 1.8)
	light.light_color = Color(1.0, 0.62, 0.32)
	light.omni_range = 11.0
	light.light_energy = 2.4
	light.shadow_enabled = true
	root.add_child(light)
	fires.append([light, 2.4, flame])
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, H - 0.6, 0.5)
	fill.light_color = Color(0.95, 0.85, 0.7)
	fill.omni_range = 12.0
	fill.light_energy = 0.7
	root.add_child(fill)
	# Furniture: bed, table and stools, shelves, chest, barrels, rug
	var mirror := -1.0 if idx % 2 == 0 else 1.0     # bed opposite the fireplace
	var blanket_cols := [Color(0.62, 0.22, 0.2), Color(0.25, 0.4, 0.58), Color(0.35, 0.5, 0.3), Color(0.6, 0.48, 0.25)]
	var bed_pos := Vector3(-mirror * 3.6, 0, -hd + 1.6)
	if idx == SICK_HOUSE:
		bed_pos = Vector3(-mirror * 3.4, 0, -1.2)
	build_bed(root, bed_pos, blanket_cols[idx % blanket_cols.size()], wood)
	var table := Vector3(mirror * 0.8, 0, 0.6)
	solid(root, Vector3(1.9, 0.1, 1.1), table + Vector3(0, 0.78, 0), wood)
	for lx in [-0.8, 0.8]:
		for lz in [-0.45, 0.45]:
			B.mesh(root, B.box_mesh(Vector3(0.1, 0.78, 0.1)), table + Vector3(lx, 0.39, lz), wood)
	for sx in [-1.35, 1.35]:
		B.solid_cylinder(root, 0.25, 0.5, table + Vector3(sx, 0, 0))
		B.mesh(root, B.cyl(0.24, 0.24, 0.08, 8), table + Vector3(sx, 0.48, 0), wood)
		B.mesh(root, B.cyl(0.05, 0.05, 0.45, 5), table + Vector3(sx, 0.22, 0), wood)
	B.mesh(root, B.cyl(0.18, 0.12, 0.1, 8), table + Vector3(0.3, 0.88, 0.1), B.paint_mat(Color(0.75, 0.68, 0.55), "skin"))
	B.mesh(root, B.cyl(0.04, 0.04, 0.16, 6), table + Vector3(-0.4, 0.91, -0.15), B.mat(Color(0.92, 0.9, 0.82)))
	var candle := B.mesh(root, B.sphere(0.03, 5, 3), table + Vector3(-0.4, 1.02, -0.15), B.glow(Color(1.0, 0.8, 0.4)))
	candle.set_meta("keep", true)
	var rug_cols := [Color(0.55, 0.25, 0.2), Color(0.3, 0.38, 0.5), Color(0.5, 0.42, 0.25)]
	B.mesh(root, B.box_mesh(Vector3(3.2, 0.02, 2.2)), table + Vector3(0, 0.012, 0), B.paint_mat(rug_cols[idx % 3], "cloth", 310 + idx))
	# shelves with pots along the side wall by the door
	var shelf := Vector3(mirror * (hw - 0.35), 0, 2.6)
	solid(root, Vector3(0.5, 2.2, 1.6), shelf + Vector3(0, 1.1, 0), wood)
	for row in 3:
		for k in 3:
			var pc := [Color(0.65, 0.45, 0.3), Color(0.55, 0.55, 0.5), Color(0.7, 0.6, 0.4)][(row + k + idx) % 3] as Color
			B.mesh(root, B.cyl(0.1, 0.13, 0.26, 7), shelf + Vector3(-mirror * 0.3, 0.6 + row * 0.6, -0.5 + k * 0.5), B.paint_mat(pc, "skin", 320 + row))
	var chest := Vector3(-mirror * (hw - 0.6), 0, 2.4)
	solid(root, Vector3(0.8, 0.6, 1.2), chest + Vector3(0, 0.3, 0), wood)
	B.mesh(root, B.box_mesh(Vector3(0.84, 0.06, 1.24)), chest + Vector3(0, 0.45, 0), B.paint_mat(Color(0.45, 0.44, 0.42), "metal"))
	for bz in [-hd + 0.5, -hd + 1.2]:
		var bp := Vector3(mirror * (hw - 0.55), 0, bz + 1.6)
		B.solid_cylinder(root, 0.38, 0.95, bp)
		B.mesh(root, B.cyl(0.36, 0.38, 0.95, 9), bp + Vector3(0, 0.47, 0), wood)
	# herbs drying from the rafters
	for k in 4:
		var hp := Vector3(rng.randf_range(-3, 3), H - 0.5, rng.randf_range(-2.5, 1.5))
		B.mesh(root, B.cyl(0.005, 0.005, 0.35, 3), hp + Vector3(0, 0.15, 0), wood)
		B.mesh(root, B.sphere(0.12, 6, 3), hp - Vector3(0, 0.08, 0), B.paint_mat(Color(0.4, 0.5, 0.28), "leaf", 330 + k))
	if idx == SICK_HOUSE:
		build_sickroom(root, bed_pos, mirror)


func build_bed(root: Node3D, p: Vector3, blanket: Color, wood: Material) -> void:
	solid(root, Vector3(1.3, 0.45, 2.3), p + Vector3(0, 0.225, 0), wood)
	B.mesh(root, B.box_mesh(Vector3(1.35, 0.9, 0.12)), p + Vector3(0, 0.45, -1.15), wood)
	B.mesh(root, B.box_mesh(Vector3(1.2, 0.16, 2.15)), p + Vector3(0, 0.52, 0), B.paint_mat(Color(0.88, 0.85, 0.76), "cloth", 340))
	B.mesh(root, B.box_mesh(Vector3(1.26, 0.1, 1.5)), p + Vector3(0, 0.62, 0.35), B.paint_mat(blanket, "cloth", 341))
	var pillow := B.mesh(root, B.sphere(1.0, 8, 5), p + Vector3(0, 0.66, -0.8), B.paint_mat(Color(0.92, 0.9, 0.84), "cloth", 342))
	pillow.scale = Vector3(0.4, 0.1, 0.22)


## Wenna's room: a stool with a basin and a cold cup beside her bed.
func build_sickroom(root: Node3D, bed: Vector3, mirror: float) -> void:
	var stool := bed + Vector3(mirror * 1.1, 0, -0.5)
	B.solid_cylinder(root, 0.25, 0.5, stool)
	B.mesh(root, B.cyl(0.24, 0.24, 0.08, 8), stool + Vector3(0, 0.48, 0), B.paint_mat(Color(0.5, 0.35, 0.22), "leather"))
	B.mesh(root, B.cyl(0.17, 0.12, 0.08, 8), stool + Vector3(0, 0.56, 0), B.paint_mat(Color(0.55, 0.55, 0.55), "metal"))
	# a quilt pulled up over her
	var quilt := B.mesh(root, B.box_mesh(Vector3(1.24, 0.12, 1.45)), bed + Vector3(0, 0.84, 0.42), B.paint_mat(Color(0.42, 0.5, 0.62), "cloth", 345))
	quilt.set_meta("keep", true)
	var npc = NpcScript.new()
	npc.main = main
	npc.npc_name = "Wenna"
	npc.colors = {
		"sick": true, "skin": Color(0.86, 0.74, 0.66), "shirt": Color(0.78, 0.74, 0.66), "pants": Color(0.6, 0.55, 0.5),
		"hair": Color(0.45, 0.25, 0.14), "hair_style": "long", "face": "worried", "eye_color": Color(0.25, 0.3, 0.2),
		"head_scale": 1.4, "leg": 0.82, "limb": 1.1, "hand_scale": 1.1,
	}
	npc.lines = []
	npc.base_yaw = PI
	npc.position = root.position + bed + Vector3(0, 0, 0.1)
	main.world.add_child(npc)


# ------------------------------------------------------------------ doors

func _physics_process(delta: float) -> void:
	cooldown = maxf(cooldown - delta, 0.0)
	for f in fires:
		var l: OmniLight3D = f[0]
		l.light_energy = f[1] * randf_range(0.85, 1.1)
		(f[2] as Node3D).scale = Vector3(randf_range(0.85, 1.1), randf_range(0.8, 1.2), 1.0)
	var p = main.player
	if cooldown > 0.0 or main.transition_active or p.state != "move" or not p.is_alive():
		return
	var v := Vector3(p.velocity.x, 0, p.velocity.z)
	if inside < 0:
		for i in main.doors.size():
			var dd: Dictionary = main.doors[i]
			var to: Vector3 = dd.pos - p.global_position
			to.y = 0
			if to.length() < 0.9 and v.dot(-(dd.out as Vector3)) > 1.5:
				go_inside(i)
				return
	else:
		var o: Vector3 = rooms[inside].origin
		var local: Vector3 = p.global_position - o
		if local.z > D * 0.5 - 0.55 and absf(local.x) < 0.9 and v.z > 1.0:
			go_outside()


func go_inside(i: int) -> void:
	var o: Vector3 = rooms[i].origin
	await transition(o + Vector3(0, 0.05, D * 0.5 - 1.3), Vector3(0, 0, -1))
	inside = i
	main.music.indoors = true


func go_outside() -> void:
	var dd: Dictionary = main.doors[rooms[inside].door]
	inside = -1
	main.music.indoors = false
	await transition(dd.pos + (dd.out as Vector3) * 1.0 + Vector3(0, 0.05, 0), dd.out)


func transition(pos: Vector3, face: Vector3) -> void:
	main.transition_active = true
	main.sfx.play("door")
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.22)
	await tw.finished
	var p = main.player
	p.global_position = pos
	p.velocity = Vector3.ZERO
	p.facing = face.normalized()
	p.target = null
	main.cam_rig.yaw = B.yaw_of(face)
	main.cam_rig.pitch = -0.32
	main.cam_rig.snap()
	await get_tree().physics_frame
	await get_tree().physics_frame
	var tw2 := create_tween()
	tw2.tween_property(fade, "color:a", 0.0, 0.3)
	await tw2.finished
	cooldown = 0.6
	main.transition_active = false


func is_inside() -> bool:
	return inside >= 0
