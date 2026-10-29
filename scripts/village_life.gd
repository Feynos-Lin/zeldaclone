extends Node3D
## Village life: the animals, Farmer Hobb's hen pen, Tamsin's archery range,
## and the side quests the villagers hand out.
##
## Quests (main.quests):
##   hens     Farmer Hobb   catch his 5 escaped hens        -> bigger bomb bag
##   archery  Tamsin        hit all 3 targets in 45 seconds -> bigger quiver
##   cull     Old Brannoc   put 10 zombies back in the ground -> heart charm
##   shards   Dorran        bring 5 bone shards             -> sharpened sword
## (Wenna's satchel lives in main.gd: quest_state.)

const B = preload("res://scripts/build.gd")
const AnimalScript = preload("res://scripts/animal.gd")
const TargetScript = preload("res://scripts/target.gd")

const PEN := Vector3(-19.5, 0, -1.0)
const PEN_SIZE := Vector2(5.0, 4.0)
const HENS_NEEDED := 5
const TARGET_SPOTS := [Vector3(21.0, 0, -5.0), Vector3(-6.0, 0, -22.0), Vector3(-21.5, 0, 10.0)]
const ARCHERY_TIME := 45.0
const CULL_NEEDED := 10
const SHARDS_NEEDED := 5

var main
var hens_caught := 0
var targets: Array = []
var archery_active := false
var archery_time := 0.0
var cull_start := 0


func build() -> void:
	build_pen()
	for i in 3:
		spawn_animal("hen", PEN + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.2, 1.2)), PEN, 1.5, false)
	var loose_spots := [Vector3(-8, 0, 18), Vector3(16, 0, 4), Vector3(-2, 0, -10), Vector3(9, 0, -18), Vector3(-17, 0, -12)]
	for p in loose_spots:
		spawn_animal("hen", p, Vector3.ZERO, 21.0, true)
	spawn_animal("dog", Vector3(4, 0, 6), Vector3.ZERO, 19.0, false)
	spawn_animal("cat", Vector3(-6, 0, -6), Vector3(-4, 0, -4), 10.0, false)
	spawn_animal("cat", Vector3(9, 0, 10), Vector3(8, 0, 6), 8.0, false)
	for s in TARGET_SPOTS:
		var tg = TargetScript.new()
		tg.position = s
		tg.rotation.y = B.yaw_of(-Vector3(s.x, 0, s.z)) + PI   # face the village square
		tg.on_hit = _on_target_hit
		main.world.add_child(tg)
		targets.append(tg)


func spawn_animal(kind: String, p: Vector3, home: Vector3, r: float, loose: bool) -> void:
	var a = AnimalScript.new()
	a.main = main
	a.kind = kind
	a.loose = loose
	a.home = home
	a.home_r = r
	a.position = p
	main.world.add_child(a)


func build_pen() -> void:
	var wood := B.paint_mat(Color(0.55, 0.4, 0.25), "leather", 63)
	var straw := B.paint_mat(Color(0.82, 0.7, 0.42), "hair", 64)
	var root := Node3D.new()
	root.position = PEN
	main.world.add_child(root)
	B.mesh(root, B.box_mesh(Vector3(PEN_SIZE.x, 0.03, PEN_SIZE.y)), Vector3(0, 0.015, 0), straw)
	var hx := PEN_SIZE.x * 0.5
	var hz := PEN_SIZE.y * 0.5
	for side in [[Vector3(0, 0, -hz), PEN_SIZE.x, 0.0], [Vector3(0, 0, hz), PEN_SIZE.x, 0.0], [Vector3(-hx, 0, 0), PEN_SIZE.y, PI * 0.5], [Vector3(hx, 0, 0), PEN_SIZE.y, PI * 0.5]]:
		var seg := Node3D.new()
		seg.position = side[0]
		seg.rotation.y = side[2]
		root.add_child(seg)
		var n := int(side[1] / 0.8)
		for i in n + 1:
			B.mesh(seg, B.box_mesh(Vector3(0.09, 0.75, 0.09)), Vector3(-side[1] * 0.5 + i * side[1] / n, 0.37, 0), wood)
		for ry in [0.25, 0.55]:
			B.mesh(seg, B.box_mesh(Vector3(side[1], 0.07, 0.05)), Vector3(0, ry, 0), wood)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(side[1], 0.8, 0.15)
		cs.shape = sh
		cs.position.y = 0.4
		body.add_child(cs)
		seg.add_child(body)
	# little hen house in the corner
	var coop := Vector3(-hx + 0.8, 0, -hz + 0.7)
	B.mesh(root, B.box_mesh(Vector3(1.2, 0.8, 1.0)), coop + Vector3(0, 0.6, 0), wood)
	var roof := B.mesh(root, B.prism(Vector3(1.0, 0.5, 1.4)), coop + Vector3(0, 1.25, 0), straw)
	roof.rotation.y = PI * 0.5
	for k in 4:
		B.mesh(root, B.box_mesh(Vector3(0.06, 0.2, 0.06)), coop + Vector3(-0.45 + (k % 2) * 0.9, 0.1, -0.35 + (k / 2) * 0.7), wood)
	B.merge_children(root)


# ------------------------------------------------------------------ hens

## The hero pressed the action button: grab an escaped hen if one is close.
func try_catch_hen(p: Vector3) -> bool:
	for a in get_tree().get_nodes_in_group("animals"):
		if a.catchable_by(p):
			if main.quests.hens != 1:
				main.hud.toast("The hen squawks and flaps out of reach. Whose is it, anyway?")
				main.sfx.play_at("cluck", a.global_position)
				a.speed = 4.0
				return true
			a.loose = false
			a.home = PEN
			a.home_r = 1.5
			main.spawn_flash(a.global_position + Vector3(0, 0.4, 0))
			a.global_position = PEN + Vector3(randf_range(-1.2, 1.2), 0, randf_range(-1.0, 1.0))
			a.pick_target()
			hens_caught += 1
			main.sfx.play("shard")
			main.sfx.play_at("cluck", a.global_position)
			if hens_caught >= HENS_NEEDED:
				main.hud.toast("That's all five hens back in the pen! Tell Farmer Hobb.")
			else:
				main.hud.toast("Caught a hen! (%d / %d)" % [hens_caught, HENS_NEEDED])
			return true
	return false


# ------------------------------------------------------------------ archery

func start_archery() -> void:
	archery_active = true
	archery_time = ARCHERY_TIME
	for tg in targets:
		tg.set_lit(false)
	main.player.arrows = maxi(main.player.arrows, 10)


func _on_target_hit(tg) -> void:
	if not archery_active:
		main.sfx.play_at("block", tg.centre())
		return
	if tg.lit:
		return
	tg.set_lit(true)
	main.sfx.play("charged")
	var hit := 0
	for t in targets:
		if t.lit:
			hit += 1
	if hit >= targets.size():
		archery_active = false
		main.quests.archery = 2
		main.hud.toast("All three targets! Go tell Tamsin.")
	else:
		main.hud.toast("Target %d of %d!" % [hit, targets.size()])


func _process(delta: float) -> void:
	if archery_active:
		archery_time -= delta
		if archery_time <= 0.0:
			archery_active = false
			for tg in targets:
				tg.set_lit(false)
			main.hud.toast("Time's up! Talk to Tamsin to try again.")
			main.sfx.play("blip", 0.6)


# ------------------------------------------------------------------ quest log and dialog

func quest_lines() -> Array:
	var out := []
	match int(main.quests.hens):
		1:
			out.append("Catch Farmer Hobb's hens (%d/%d)" % [hens_caught, HENS_NEEDED] if hens_caught < HENS_NEEDED else "Tell Farmer Hobb his hens are home")
	if archery_active:
		out.append("Hit all three targets! %d s" % ceili(archery_time))
	elif int(main.quests.archery) == 1:
		out.append("Talk to Tamsin to try the archery range")
	elif int(main.quests.archery) == 2:
		out.append("Tell Tamsin you hit every target")
	if int(main.quests.cull) == 1:
		var n: int = mini(main.kills - cull_start, CULL_NEEDED)
		out.append("Defeat zombies for Brannoc (%d/%d)" % [n, CULL_NEEDED] if n < CULL_NEEDED else "Report back to Old Brannoc")
	if int(main.quests.shards) == 1:
		out.append("Bring Dorran bone shards (%d/%d)" % [mini(main.shards, SHARDS_NEEDED), SHARDS_NEEDED])
	return out


## Lines for an NPC this module looks after, or an empty array.
func lines_for(npc) -> Array:
	match npc.npc_name:
		"Farmer Hobb":
			return hobb_lines()
		"Tamsin the Hunter":
			return tamsin_lines()
		"Old Brannoc":
			return brannoc_lines(npc.lines)
		"Dorran the Trader":
			return dorran_lines(npc.lines)
	return []


func hobb_lines() -> Array:
	match int(main.quests.hens):
		0:
			main.quests.hens = 1
			return [
				"Oh, thank the wardstones, someone with young legs!",
				"When the bell cracked the whole flock went mad. Five of my best hens flew the pen, and they've been running loose through the village ever since.",
				"The brown ones, see? Chase one down, grab it, and I'll pop it straight back in the pen.",
				"Catch all five and I'll make it worth your while. I've a stout old pouch that'd hold a good few more of those bombs of yours.",
			]
		1:
			if hens_caught >= HENS_NEEDED:
				main.quests.hens = 2
				main.pending_call = func():
					main.player.max_bombs += 5
					main.player.bombs = main.player.max_bombs
					main.sfx.play("heart")
					main.hud.toast("Bigger bomb bag! You can carry %d bombs." % main.player.max_bombs)
				return [
					"All five! Listen to them, chattering away like nothing happened.",
					"Here, as promised. My old powder pouch. Holds a fair few more bombs than that little bag of yours.",
				]
			return [
				"%d down, %d to go. They're quick, but they're not clever." % [hens_caught, HENS_NEEDED - hens_caught],
				"Corner one against a wall and grab it.",
			]
	return [
		"The hens are laying again. Good thing, too. Eggs are about all the trade we've got left.",
		"That dog of the Mellors' keeps sniffing round my pen. Harmless, mostly.",
	]


func tamsin_lines() -> Array:
	match int(main.quests.archery):
		0:
			main.quests.archery = 1
			main.pending_call = start_archery
			return [
				"You carry that bow like a shovel. Let's fix that.",
				"I've set three straw targets around the village: one past the market, one behind the north houses, one out west by the trees.",
				"Hit all three in forty-five seconds. The clock starts when you walk away. Go!",
			]
		1:
			main.pending_call = start_archery
			return [
				"Again? Good. Forty-five seconds, three targets. Go!",
				"Tip: lock on doesn't work on straw. Face the target and let the arrow fly a touch high.",
			]
		2:
			main.quests.archery = 3
			main.pending_call = func():
				main.player.max_arrows = 50
				main.player.arrows = main.player.max_arrows
				main.sfx.play("heart")
				main.hud.toast("Bigger quiver! You can carry 50 arrows.")
			return [
				"All three. Not bad at all.",
				"Take my spare quiver. The dead don't stop coming, so neither should your arrows.",
			]
	if archery_active:
		return ["Stop talking and shoot!"]
	return [
		"Keep your elbow up and breathe out when you loose. The arrow knows when you're nervous.",
		"If you want, I'll run the range again. Just say so.",
	]


func brannoc_lines(base: Array) -> Array:
	match int(main.quests.cull):
		0:
			main.quests.cull = 1
			cull_start = main.kills
			var l := base.duplicate()
			l.append("One more thing. If you're going out there anyway, put ten of them back in the ground and come tell me. I'll make it worth your while.")
			return l
		1:
			if main.kills - cull_start >= CULL_NEEDED:
				main.quests.cull = 2
				main.pending_call = func():
					main.player.max_hp += 2
					main.player.hp = main.player.max_hp
					main.sfx.play("heart")
					main.sfx.play("charged")
					main.hud.toast("Brannoc's charm! Your hearts grew by one.")
				return [
					"Ten? Ha! I heard the racket from here.",
					"My old captain gave me this charm when I first took the gate. It's kept my heart beating forty years. Your turn.",
				]
			return [
				"%d so far. Ten, I said. The trail past the gate is thick with them after dark." % (main.kills - cull_start),
			]
	return [
		"Heading out again? Keep your shield up, lad.",
		"The ward-stones still hold. As long as they do, so do I.",
	]


func dorran_lines(base: Array) -> Array:
	match int(main.quests.shards):
		0:
			main.quests.shards = 1
			var l := base.duplicate()
			l.append("Bone shards. The dead leave them behind. Bring me five and I'll grind them into a paste that puts an edge on a blade like nothing else.")
			return l
		1:
			if main.shards >= SHARDS_NEEDED:
				main.quests.shards = 2
				main.pending_call = func():
					main.shards -= SHARDS_NEEDED
					main.player.sword_bonus = 1
					main.sfx.play("charged")
					main.hud.toast("Sharpened sword! Every swing hits harder.")
				return [
					"Five shards, as promised. Hand over that sword.",
					"*scrape* *scrape* ...There. Keener than the day it was forged. Mind your fingers.",
				]
			return ["%d shards. I need five. The dead out by the cave are full of them." % main.shards]
	return [
		"That edge holding up? Good shard-paste, that.",
		"Business is slow. Folk don't buy much when they're boarding up their windows.",
	]
