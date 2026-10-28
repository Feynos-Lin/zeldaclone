extends Control
## Pause menu (Start / Back / Esc / P) and the controller setup wizard.
## Works with a controller, keyboard, mouse or touch.

var main
var controls
var open := false
var items: Array = []
var selected := 0
var item_rects: Array = []
var status := ""
var status_time := 0.0
var opened_frame := 0

# Wizard state
var wiz_active := false
var wiz_device := -1
var wiz_step := 0
var wiz_table := {}
var wiz_used := {}
var wiz_rest := {}
var wiz_timer := 0.0
var wiz_waiting_release := false
var wiz_release_time := 0.0
var wiz_flash := 0.0
var cancel_rect := Rect2()
const STEP_TIME := 8.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _process(delta: float) -> void:
	var vr := get_viewport_rect().size
	if size != vr:
		size = vr
	status_time = maxf(status_time - delta, 0.0)
	wiz_flash = maxf(wiz_flash - delta, 0.0)

	if not open:
		if Input.is_action_just_pressed("pause") and not main.game_over_active and not main.dialog_active:
			show_menu()
		return

	if wiz_active:
		wizard_process(delta)
	elif Engine.get_process_frames() > opened_frame:
		var back_pressed := Input.is_action_just_pressed("attack") and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		if Input.is_action_just_pressed("pause") or back_pressed:
			hide_menu()
			return
		if Input.is_action_just_pressed("move_forward"):
			selected = posmod(selected - 1, items.size())
			main.sfx.play("blip")
		if Input.is_action_just_pressed("move_back"):
			selected = posmod(selected + 1, items.size())
			main.sfx.play("blip")
		if Input.is_action_just_pressed("action"):
			choose(selected)
		elif Input.is_action_just_pressed("move_left"):
			choose(selected, -1)
		elif Input.is_action_just_pressed("move_right") and items[selected] in ["Graphics", "Resolution", "Display"]:
			choose(selected, 1)
	queue_redraw()


func build_items() -> void:
	items = ["Resume", "Graphics", "Resolution"]
	if not main.graphics.mobile:
		items.append("Display")
	items.append_array(["Controller setup", "Reset controller mapping", "Quit game"])


func item_label(i: int) -> String:
	match items[i]:
		"Graphics":
			return "Graphics:  < %s >" % main.graphics.quality_name()
		"Resolution":
			return "Resolution:  < %s >" % main.graphics.resolution_name()
		"Display":
			return "Display:  < %s >" % main.graphics.display_name()
	return items[i]


func show_menu() -> void:
	build_items()
	open = true
	visible = true
	selected = 0
	opened_frame = Engine.get_process_frames()
	get_tree().paused = true
	main.sfx.play("lock")


func hide_menu() -> void:
	open = false
	visible = false
	wiz_active = false
	get_tree().paused = false


func set_status(text: String) -> void:
	status = text
	status_time = 4.0


func pad_device() -> int:
	if controls.last_pad >= 0 and controls.pad_devices().has(controls.last_pad):
		return controls.last_pad
	var pads: Array = controls.pad_devices()
	return pads[0] if not pads.is_empty() else -1


func choose(i: int, dir: int = 1) -> void:
	if dir < 0 and not items[i] in ["Graphics", "Resolution", "Display"]:
		return
	main.sfx.play("shard")
	match items[i]:
		"Resume":
			hide_menu()
		"Graphics":
			main.graphics.cycle_quality(dir)
		"Resolution":
			main.graphics.cycle_resolution(dir)
		"Display":
			main.graphics.toggle_fullscreen()

		"Controller setup":
			var d := pad_device()
			if d < 0:
				set_status("Connect a controller first.")
			else:
				start_wizard(d)
		"Reset controller mapping":
			var d2 := pad_device()
			if d2 < 0:
				set_status("No controller connected.")
			else:
				controls.clear_remap(d2)
				set_status("%s is back to its default layout." % Input.get_joy_name(d2))
		"Quit game":
			get_tree().quit()


# ------------------------------------------------------------------ wizard

func start_wizard(device: int) -> void:
	wiz_active = true
	wiz_device = device
	wiz_step = 0
	wiz_table = {}
	wiz_used = {}
	begin_step()


func begin_step() -> void:
	wiz_timer = STEP_TIME
	wiz_waiting_release = true
	wiz_release_time = 0.0


func sample_rest() -> void:
	wiz_rest = {}
	for axis in 10:
		wiz_rest[axis] = Input.get_joy_axis(wiz_device, axis)


func all_released() -> bool:
	for b in 40:
		if Input.is_joy_button_pressed(wiz_device, b):
			return false
	for axis in wiz_rest:
		if absf(Input.get_joy_axis(wiz_device, axis) - float(wiz_rest[axis])) > 0.3:
			return false
	return true


func wizard_process(delta: float) -> void:
	if not controls.pad_devices().has(wiz_device):
		wiz_active = false
		set_status("Controller disconnected. Setup cancelled.")
		return
	if wiz_waiting_release:
		# Wait until nothing is held, then remember where the sticks and triggers rest.
		if wiz_rest.is_empty():
			sample_rest()
		if all_released():
			wiz_release_time += delta
		else:
			wiz_release_time = 0.0
		if wiz_release_time > 0.25:
			sample_rest()
			wiz_waiting_release = false
		return
	wiz_timer -= delta
	if wiz_timer <= 0.0:
		var control: String = controls.WIZARD_STEPS[wiz_step][0]
		if not Input.is_joy_known(wiz_device):
			wiz_table[control] = {"type": "none"}
		next_step()


func next_step() -> void:
	wiz_step += 1
	if wiz_step >= controls.WIZARD_STEPS.size():
		controls.save_remap(wiz_device, wiz_table)
		wiz_active = false
		set_status("Saved! %s is set up." % Input.get_joy_name(wiz_device))
		main.sfx.play("heart")
		return
	begin_step()


func record(src: Dictionary, used_key: String) -> void:
	if wiz_used.has(used_key):
		return
	var control: String = controls.WIZARD_STEPS[wiz_step][0]
	wiz_table[control] = src
	wiz_used[used_key] = true
	wiz_flash = 0.3
	main.sfx.play("blip")
	next_step()


func _input(event: InputEvent) -> void:
	if not open:
		return
	if wiz_active:
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			wiz_active = false
			set_status("Setup cancelled. Nothing was changed.")
			get_viewport().set_input_as_handled()
			return
		var tap: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
		if tap and cancel_rect.has_point(event.position):
			wiz_active = false
			set_status("Setup cancelled. Nothing was changed.")
			return
		if wiz_waiting_release or event.device != wiz_device:
			return
		var control: String = controls.WIZARD_STEPS[wiz_step][0]
		if event is InputEventJoypadButton and event.pressed:
			record({"type": "button", "index": event.button_index}, "b%d" % event.button_index)
		elif event is InputEventJoypadMotion:
			var rest: float = wiz_rest.get(event.axis, 0.0)
			var delta: float = event.axis_value - rest
			if absf(delta) < 0.65:
				return
			if control in ["leftx", "lefty", "rightx", "righty"]:
				# Pushing left/up should read as negative; remember if this stick is flipped.
				record({"type": "axis", "index": event.axis, "sign": 1.0 if event.axis_value < 0.0 else -1.0}, "a%d" % event.axis)
			elif control.ends_with("trigger"):
				record({"type": "axis", "index": event.axis, "sign": signf(delta), "full": absf(rest) > 0.5}, "a%d" % event.axis)
			else:
				var sgn: float = signf(event.axis_value)
				record({"type": "axis", "index": event.axis, "sign": sgn}, "a%d%s" % [event.axis, "+" if sgn > 0.0 else "-"])
		return
	# Menu: mouse and touch selection
	var p := Vector2.ZERO
	var pressed := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		p = event.position
		pressed = true
	elif event is InputEventScreenTouch and event.pressed:
		p = event.position
		pressed = true
	elif event is InputEventMouseMotion:
		for i in item_rects.size():
			if item_rects[i].has_point(event.position):
				selected = i
	if pressed:
		for i in item_rects.size():
			if item_rects[i].has_point(p):
				selected = i
				choose(i)
				get_viewport().set_input_as_handled()
				return


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var w := size.x
	var h := size.y
	var font := get_theme_default_font()
	draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.03, 0.06, 0.72))
	var pw := minf(w - 30.0, 340.0)
	var ph := 72.0 + items.size() * 20.0 + 26.0
	var panel := Rect2((w - pw) * 0.5, (h - ph) * 0.5, pw, ph)
	draw_rect(panel, Color(0.08, 0.07, 0.1, 0.92))
	draw_rect(panel, Color(0.7, 0.62, 0.45), false, 1.0)
	if wiz_active:
		draw_wizard(panel, font)
	else:
		draw_centered(font, "PAUSED", Vector2(w * 0.5, panel.position.y + 22), 16, Color(0.95, 0.88, 0.7))
		item_rects.clear()
		for i in items.size():
			var y := panel.position.y + 46 + i * 20
			var r := Rect2(panel.position.x + 20, y - 13, pw - 40, 18)
			item_rects.append(r)
			if i == selected:
				draw_rect(r, Color(0.75, 0.6, 0.3, 0.35))
				draw_string(font, Vector2(r.position.x + 6, y + 1), ">", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.9, 0.6))
			draw_centered(font, item_label(i), Vector2(w * 0.5, y + 1), 11, Color(1, 1, 1) if i == selected else Color(0.78, 0.76, 0.72))
		var pads: Array = controls.pad_devices()
		var pad_text := "No controller connected"
		if not pads.is_empty():
			var d := pad_device()
			pad_text = "Controller: %s%s" % [Input.get_joy_name(d), "" if Input.is_joy_known(d) or controls.remaps.has(controls.pad_key(d)) else " (unrecognized)"]
		draw_centered(font, pad_text, Vector2(w * 0.5, panel.end.y - 22), 8, Color(0.65, 0.65, 0.7))
	if status_time > 0.0:
		draw_centered(font, status, Vector2(w * 0.5, panel.end.y - 8), 9, Color(1.0, 0.9, 0.55, minf(status_time, 1.0)))


func draw_wizard(panel: Rect2, font: Font) -> void:
	var w := size.x
	var step: Array = controls.WIZARD_STEPS[mini(wiz_step, controls.WIZARD_STEPS.size() - 1)]
	draw_centered(font, "CONTROLLER SETUP  %d / %d" % [wiz_step + 1, controls.WIZARD_STEPS.size()], Vector2(w * 0.5, panel.position.y + 18), 10, Color(0.95, 0.88, 0.7))
	draw_centered(font, Input.get_joy_name(wiz_device), Vector2(w * 0.5, panel.position.y + 32), 8, Color(0.65, 0.65, 0.7))
	var lines: PackedStringArray = String(step[1]).split("\n")
	var col := Color(1, 1, 1) if wiz_flash <= 0.0 else Color(0.6, 1.0, 0.6)
	for i in lines.size():
		draw_centered(font, lines[i], Vector2(w * 0.5, panel.position.y + 64 + i * 16), 12 if i == 0 else 10, col if i == 0 else Color(0.8, 0.78, 0.72))
	if wiz_waiting_release:
		draw_centered(font, "Let go of everything...", Vector2(w * 0.5, panel.end.y - 40), 9, Color(0.7, 0.7, 0.75))
	else:
		draw_centered(font, "Skipping in %d s if not pressed" % ceili(wiz_timer), Vector2(w * 0.5, panel.end.y - 40), 9, Color(0.7, 0.7, 0.75))
	cancel_rect = Rect2(w * 0.5 - 60, panel.end.y - 26, 120, 18)
	draw_rect(cancel_rect, Color(0.5, 0.2, 0.18, 0.6))
	draw_centered(font, "Cancel (Esc / tap)", Vector2(w * 0.5, panel.end.y - 13), 9, Color(1, 0.9, 0.85))


func draw_centered(font: Font, text: String, pos: Vector2, fs: int, col: Color) -> void:
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string_outline(font, Vector2(pos.x - tw * 0.5, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, col.a))
	draw_string(font, Vector2(pos.x - tw * 0.5, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
