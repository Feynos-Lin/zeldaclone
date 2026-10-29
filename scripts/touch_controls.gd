extends Control
## On-screen controls for phones: floating stick on the left half,
## A (roll / talk), B (sword, hold to charge), Z (lock-on), J (jump) and
## R (hold to raise the shield) on the right,
## and drag anywhere else on the right half to turn the camera.

var cam_drag := 0.0
var joy_index := -1
var joy_center := Vector2.ZERO
var joy_knob := Vector2.ZERO
var cam_index := -1
var button_touch := {}   # touch index -> action name
const JOY_RADIUS := 32.0

var buttons := {
	"attack": {"label": "B", "color": Color(0.25, 0.7, 0.35), "r": 22.0},
	"action": {"label": "A", "color": Color(0.25, 0.45, 0.9), "r": 17.0},
	"target": {"label": "Z", "color": Color(0.85, 0.75, 0.3), "r": 14.0},
	"jump": {"label": "J", "color": Color(0.55, 0.4, 0.8), "r": 14.0},
	"shield": {"label": "R", "color": Color(0.6, 0.6, 0.65), "r": 15.0},
}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = DisplayServer.is_touchscreen_available() or OS.has_feature("android") or OS.has_feature("mobile")
	set_process_input(visible)


func _process(_delta: float) -> void:
	var vr := get_viewport_rect().size
	if size != vr:
		size = vr
		queue_redraw()


func button_center(action: String) -> Vector2:
	var w := size.x
	var h := size.y
	match action:
		"attack":
			return Vector2(w - 46, h - 58)
		"action":
			return Vector2(w - 92, h - 32)
		"target":
			return Vector2(w - 98, h - 82)
		"jump":
			return Vector2(w - 138, h - 44)
		"shield":
			return Vector2(w - 40, h - 108)
	return Vector2.ZERO


func button_at(p: Vector2) -> String:
	for a in buttons:
		if p.distance_to(button_center(a)) <= buttons[a].r + 7.0:
			return a
	return ""


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		if event.pressed:
			var b := button_at(p)
			if b != "":
				button_touch[event.index] = b
				Input.action_press(b)
			elif p.x < size.x * 0.45 and joy_index == -1:
				joy_index = event.index
				joy_center = p
				set_joy(Vector2.ZERO)
			elif cam_index == -1:
				cam_index = event.index
		else:
			if button_touch.has(event.index):
				Input.action_release(button_touch[event.index])
				button_touch.erase(event.index)
			if event.index == joy_index:
				joy_index = -1
				set_joy(Vector2.ZERO)
			if event.index == cam_index:
				cam_index = -1
		queue_redraw()
	elif event is InputEventScreenDrag:
		if event.index == joy_index:
			var off: Vector2 = event.position - joy_center
			if off.length() > JOY_RADIUS * 1.6:
				# Let the stick follow a thumb that drifts too far.
				joy_center = event.position - off.normalized() * JOY_RADIUS * 1.6
				off = event.position - joy_center
			set_joy(off)
			queue_redraw()
		elif event.index == cam_index:
			cam_drag += event.relative.x


func set_joy(off: Vector2) -> void:
	joy_knob = off.limit_length(JOY_RADIUS)
	var v := joy_knob / JOY_RADIUS
	axis("move_right", maxf(v.x, 0.0))
	axis("move_left", maxf(-v.x, 0.0))
	axis("move_back", maxf(v.y, 0.0))
	axis("move_forward", maxf(-v.y, 0.0))


func axis(action: String, strength: float) -> void:
	if strength > 0.0:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _draw() -> void:
	var base := joy_center if joy_index != -1 else Vector2(62, size.y - 58)
	draw_circle(base, JOY_RADIUS + 4, Color(0, 0, 0, 0.25))
	draw_arc(base, JOY_RADIUS + 4, 0, TAU, 24, Color(1, 1, 1, 0.35), 1.5)
	draw_circle(base + (joy_knob if joy_index != -1 else Vector2.ZERO), 14, Color(1, 1, 1, 0.45))
	var font := get_theme_default_font()
	for a in buttons:
		var c := button_center(a)
		var info: Dictionary = buttons[a]
		var pressed := button_touch.values().has(a)
		var col: Color = info.color
		col.a = 0.85 if pressed else 0.55
		draw_circle(c, info.r + 1.5, Color(0, 0, 0, 0.4))
		draw_circle(c, info.r, col)
		var fs := 14 if a == "attack" else 11
		var ts := font.get_string_size(info.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(font, c + Vector2(-ts.x * 0.5, fs * 0.36), info.label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
