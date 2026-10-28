extends Node
## Display and graphics settings, applied live and remembered per device.
##
## Resolution: on desktop, standard resolutions up to 1440p in 16:9, 16:10, 4:3,
## 5:4 and 21:9, windowed or fullscreen. In fullscreen a ratio that doesn't match
## the monitor is shown with black bars instead of stretched, and the 3D is
## rendered at the chosen size (above-screen sizes are supersampled). On Android
## the screen is fixed, so the setting picks the 3D render height instead.
##
## Quality: Low (no shadows or bloom), Medium (sun shadows, bloom),
## High (2x MSAA, longer shadows, denser grass).

const SAVE_PATH := "user://settings.cfg"
const QUALITY_NAMES := ["Low", "Medium", "High"]
const BASE_H := 240   # UI layout height; the HUD is drawn in this space and scaled up crisply

const DESKTOP_RES := [
	[0, 0, "Native"],
	[1280, 720, "16:9"], [1600, 900, "16:9"], [1920, 1080, "16:9"], [2560, 1440, "16:9"],
	[1280, 800, "16:10"], [1440, 900, "16:10"], [1680, 1050, "16:10"], [1920, 1200, "16:10"],
	[1024, 768, "4:3"], [1280, 960, "4:3"], [1600, 1200, "4:3"], [1920, 1440, "4:3"],
	[1280, 1024, "5:4"],
	[2560, 1080, "21:9"], [3440, 1440, "21:9"],
]
const MOBILE_RES := [[0, 0, "Native"], [0, 480, "480p"], [0, 720, "720p"], [0, 1080, "1080p"], [0, 1440, "1440p"]]

var main
var quality := 2
var res_index := 0
var fullscreen := false
var mobile := false


func _ready() -> void:
	mobile = OS.has_feature("android") or OS.has_feature("mobile")
	quality = 1 if mobile else 2
	res_index = 2 if mobile else 0
	fullscreen = mobile
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		quality = clampi(int(cfg.get_value("graphics", "quality", quality)), 0, 2)
		res_index = clampi(int(cfg.get_value("graphics", "resolution", res_index)), 0, res_list().size() - 1)
		fullscreen = bool(cfg.get_value("graphics", "fullscreen", fullscreen))
	get_viewport().size_changed.connect(_on_size_changed)


func res_list() -> Array:
	return MOBILE_RES if mobile else DESKTOP_RES


func quality_name() -> String:
	return QUALITY_NAMES[quality]


func resolution_name() -> String:
	var r: Array = res_list()[res_index]
	if mobile or r[0] == 0:
		return r[2]
	return "%d x %d (%s)" % [r[0], r[1], r[2]]


func display_name() -> String:
	return "Fullscreen" if fullscreen else "Windowed"


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "resolution", res_index)
	cfg.set_value("graphics", "fullscreen", fullscreen)
	cfg.save(SAVE_PATH)


func cycle_quality(dir: int = 1) -> void:
	quality = posmod(quality + dir, QUALITY_NAMES.size())
	save()
	apply()


func cycle_resolution(dir: int = 1) -> void:
	res_index = posmod(res_index + dir, res_list().size())
	save()
	apply_display()


func toggle_fullscreen() -> void:
	if mobile:
		return
	fullscreen = not fullscreen
	save()
	apply_display()


## Window mode, window size and aspect handling, then the 3D render scale.
func apply_display() -> void:
	var win := get_window()
	var r: Array = res_list()[res_index]
	var want := Vector2i(int(r[0]), int(r[1]))
	if not mobile:
		var screen := DisplayServer.screen_get_size()
		if fullscreen:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		else:
			if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			if want.x > 0:
				var size := want
				var usable := DisplayServer.screen_get_usable_rect().size
				if usable.x > 0 and (size.x > usable.x or size.y > usable.y):
					var k := minf(float(usable.x) / size.x, float(usable.y) / size.y)
					size = Vector2i(int(size.x * k), int(size.y * k))
				DisplayServer.window_set_size(size)
				var pos := DisplayServer.screen_get_position() + (screen - size) / 2
				DisplayServer.window_set_position(pos)
		# A fixed aspect in fullscreen gets black bars instead of being stretched.
		if fullscreen and want.x > 0:
			var aspect := float(want.x) / float(want.y)
			win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
			win.content_scale_size = Vector2i(int(round(BASE_H * aspect)), BASE_H)
		else:
			win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
			win.content_scale_size = Vector2i(426, BASE_H)
	apply()


func _on_size_changed() -> void:
	apply()


## Effects and the 3D render scale (safe to call any time).
func apply() -> void:
	var vp := get_viewport()
	# How many pixels tall the game picture actually is on screen right now.
	var win_size := Vector2(DisplayServer.window_get_size())
	var shown_h := win_size.y
	var win := get_window()
	if win.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP:
		var aspect := float(win.content_scale_size.x) / float(win.content_scale_size.y)
		shown_h = minf(win_size.y, win_size.x / aspect)
	var r: Array = res_list()[res_index]
	var target_h: float = float(r[1]) if r[1] > 0 else shown_h
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = clampf(target_h / maxf(shown_h, 1.0), 0.25, 2.0 if not mobile else 1.0)
	vp.msaa_3d = Viewport.MSAA_2X if quality == 2 else Viewport.MSAA_DISABLED
	if main == null or main.sun == null:
		return
	main.sun.shadow_enabled = quality >= 1
	main.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if quality == 2 else DirectionalLight3D.SHADOW_ORTHOGONAL
	main.sun.directional_shadow_max_distance = 36.0 if quality == 2 else 22.0
	main.env.glow_enabled = quality >= 1
	var detail_range: float = [16.0, 28.0, 40.0][quality]
	var tree_range: float = [44.0, 64.0, 72.0][quality]
	main.env.fog_depth_end = [44.0, 66.0, 74.0][quality]
	main.env.fog_depth_begin = [10.0, 16.0, 18.0][quality]
	if main.world_builder != null:
		for n in main.world_builder.detail_nodes:
			if is_instance_valid(n):
				n.visibility_range_end = detail_range
		for n in main.world_builder.tree_nodes:
			if is_instance_valid(n):
				n.visibility_range_end = tree_range
