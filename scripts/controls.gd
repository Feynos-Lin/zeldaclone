extends Node
## All input bindings. Keyboard and mouse are bound once; controllers are bound
## per connected device, so each controller can carry its own remap.
##
## Controllers Godot recognizes (XInput / Xbox-style, PlayStation, Nintendo, and
## the DInput pads in its built-in database) already report standard buttons and
## use the default layout. Anything else can be fixed with the setup wizard in
## the pause menu, which records which raw button/axis the player pressed for
## each standard control. Remaps are saved per controller and work on Linux and
## Android alike because they are applied as InputMap bindings, not OS mappings.

signal device_changed(kind: String)      # "keyboard", "gamepad" or "touch"
signal message(text: String)

const SAVE_PATH := "user://controls.cfg"

## Standard controls, named like SDL's game-controller layout.
const BUTTONS := {
	"a": JOY_BUTTON_A, "b": JOY_BUTTON_B, "x": JOY_BUTTON_X, "y": JOY_BUTTON_Y,
	"back": JOY_BUTTON_BACK, "start": JOY_BUTTON_START,
	"leftstick": JOY_BUTTON_LEFT_STICK, "rightstick": JOY_BUTTON_RIGHT_STICK,
	"leftshoulder": JOY_BUTTON_LEFT_SHOULDER, "rightshoulder": JOY_BUTTON_RIGHT_SHOULDER,
	"dpup": JOY_BUTTON_DPAD_UP, "dpdown": JOY_BUTTON_DPAD_DOWN, "dpleft": JOY_BUTTON_DPAD_LEFT, "dpright": JOY_BUTTON_DPAD_RIGHT,
}
const AXES := {
	"leftx": JOY_AXIS_LEFT_X, "lefty": JOY_AXIS_LEFT_Y, "rightx": JOY_AXIS_RIGHT_X, "righty": JOY_AXIS_RIGHT_Y,
	"lefttrigger": JOY_AXIS_TRIGGER_LEFT, "righttrigger": JOY_AXIS_TRIGGER_RIGHT,
}

## Game actions -> standard controls. "leftx-" means the left stick pushed left.
const PAD_LAYOUT := {
	"move_left": ["leftx-", "dpleft"],
	"move_right": ["leftx+", "dpright"],
	"move_forward": ["lefty-", "dpup"],
	"move_back": ["lefty+", "dpdown"],
	"cam_left": ["rightx-"],
	"cam_right": ["rightx+"],
	"cam_up": ["righty-"],
	"cam_down": ["righty+"],
	"attack": ["x", "b"],
	"action": ["a"],
	"target": ["lefttrigger+", "leftshoulder"],
	"recenter": ["y", "rightstick"],
	"pause": ["start", "back"],
}

## Order and wording of the setup wizard. Each entry: [control, prompt].
const WIZARD_STEPS := [
	["a", "Press the BOTTOM face button\n(A on Xbox, Cross on PlayStation)\nRoll · Talk · Confirm"],
	["b", "Press the RIGHT face button\n(B on Xbox, Circle on PlayStation)\nSword · Back"],
	["x", "Press the LEFT face button\n(X on Xbox, Square on PlayStation)\nSword"],
	["y", "Press the TOP face button\n(Y on Xbox, Triangle on PlayStation)\nRecenter camera"],
	["leftshoulder", "Press the LEFT BUMPER\n(LB / L1)\nLock on"],
	["rightshoulder", "Press the RIGHT BUMPER\n(RB / R1)"],
	["lefttrigger", "Pull the LEFT TRIGGER\n(LT / L2)\nLock on"],
	["righttrigger", "Pull the RIGHT TRIGGER\n(RT / R2)"],
	["start", "Press START / OPTIONS\nPause"],
	["back", "Press BACK / SELECT / SHARE\nPause"],
	["dpup", "Press D-PAD UP"],
	["dpdown", "Press D-PAD DOWN"],
	["dpleft", "Press D-PAD LEFT"],
	["dpright", "Press D-PAD RIGHT"],
	["leftx", "Push the LEFT STICK to the LEFT"],
	["lefty", "Push the LEFT STICK UP"],
	["rightx", "Push the RIGHT STICK to the LEFT"],
	["righty", "Push the RIGHT STICK UP"],
	["leftstick", "CLICK the left stick in (L3)"],
	["rightstick", "CLICK the right stick in (R3)\nRecenter camera"],
]

var last_device := "keyboard"
var last_pad := -1
var remaps := {}          # controller key -> {control: source}
var cfg := ConfigFile.new()
var test_devices: Array = []   # simulated controllers for automated tests


func pad_devices() -> Array:
	var list: Array = Input.get_connected_joypads()
	for d in test_devices:
		if not list.has(d):
			list.append(d)
	return list


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	setup_keyboard()
	load_remaps()
	rebuild_pad_bindings()
	Input.joy_connection_changed.connect(_on_joy_connection)
	if DisplayServer.is_touchscreen_available() or OS.has_feature("android"):
		last_device = "touch"
	if not Input.get_connected_joypads().is_empty():
		last_pad = Input.get_connected_joypads()[0]
		last_device = "gamepad"


# ------------------------------------------------------------------ keyboard / mouse

func setup_keyboard() -> void:
	var keys := {
		"move_left": [KEY_A],
		"move_right": [KEY_D],
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"cam_left": [KEY_Q, KEY_LEFT],
		"cam_right": [KEY_E, KEY_RIGHT],
		"cam_up": [KEY_R],
		"cam_down": [KEY_F],
		"attack": [KEY_J],
		"action": [KEY_SPACE, KEY_K, KEY_ENTER],
		"target": [KEY_TAB, KEY_L],
		"recenter": [KEY_C],
		"pause": [KEY_ESCAPE, KEY_P],
		"fullscreen": [KEY_F11],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		for k in keys[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)
	for pair in [["attack", MOUSE_BUTTON_LEFT], ["target", MOUSE_BUTTON_RIGHT]]:
		var m := InputEventMouseButton.new()
		m.button_index = pair[1]
		InputMap.action_add_event(pair[0], m)


# ------------------------------------------------------------------ controllers

func pad_key(device: int) -> String:
	var guid := Input.get_joy_guid(device)
	if guid == "" or guid == "__XINPUT_DEVICE__":
		return "name:" + Input.get_joy_name(device)
	return guid


func source_for(device: int, control: String) -> Dictionary:
	var remap: Dictionary = remaps.get(pad_key(device), {})
	if remap.has(control):
		return remap[control]
	if BUTTONS.has(control):
		return {"type": "button", "index": BUTTONS[control]}
	if AXES.has(control):
		var full := control.ends_with("trigger")
		return {"type": "axis", "index": AXES[control], "sign": 1.0, "full": full}
	return {}


## Turns "lefty-" / "x" / "lefttrigger+" into InputMap events for one device.
func events_for(device: int, binding: String) -> Array:
	var control := binding
	var dir := 0.0
	if binding.ends_with("+") or binding.ends_with("-"):
		control = binding.substr(0, binding.length() - 1)
		dir = 1.0 if binding.ends_with("+") else -1.0
	var src := source_for(device, control)
	if src.is_empty() or src.get("type", "") == "none":
		return []
	if src.type == "button":
		var e := InputEventJoypadButton.new()
		e.device = device
		e.button_index = int(src.index)
		return [e]
	var m := InputEventJoypadMotion.new()
	m.device = device
	m.axis = int(src.index)
	var sgn: float = float(src.get("sign", 1.0))
	if dir == 0.0:
		dir = 1.0     # a d-pad or button recorded on an axis: use the recorded direction
	m.axis_value = dir * sgn
	return [m]


func rebuild_pad_bindings() -> void:
	for action in PAD_LAYOUT:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		for e in InputMap.action_get_events(action):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				InputMap.action_erase_event(action, e)
		for device in pad_devices():
			for binding in PAD_LAYOUT[action]:
				for e in events_for(device, binding):
					InputMap.action_add_event(action, e)


func _on_joy_connection(device: int, connected: bool) -> void:
	rebuild_pad_bindings()
	if connected:
		last_pad = device
		var pad_name := Input.get_joy_name(device)
		var known := Input.is_joy_known(device) or remaps.has(pad_key(device))
		if known:
			message.emit("Controller connected: %s" % pad_name)
		else:
			message.emit("Unrecognized controller: %s. Press Start/Esc > Controller setup if buttons are wrong." % pad_name)
	else:
		message.emit("Controller disconnected")
		if last_pad == device:
			last_pad = -1 if Input.get_connected_joypads().is_empty() else Input.get_connected_joypads()[0]


func _input(event: InputEvent) -> void:
	var kind := ""
	if event is InputEventJoypadButton:
		kind = "gamepad"
		last_pad = event.device
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		kind = "gamepad"
		last_pad = event.device
	elif event is InputEventKey or event is InputEventMouseButton:
		kind = "keyboard"
	elif event is InputEventScreenTouch:
		kind = "touch"
	if kind != "" and kind != last_device:
		last_device = kind
		device_changed.emit(kind)


# ------------------------------------------------------------------ remaps on disk

func load_remaps() -> void:
	if cfg.load(SAVE_PATH) != OK:
		return
	if cfg.has_section("remaps"):
		for k in cfg.get_section_keys("remaps"):
			remaps[k] = cfg.get_value("remaps", k)


func save_remap(device: int, table: Dictionary) -> void:
	remaps[pad_key(device)] = table
	cfg.set_value("remaps", pad_key(device), table)
	cfg.save(SAVE_PATH)
	rebuild_pad_bindings()


func clear_remap(device: int) -> void:
	var k := pad_key(device)
	remaps.erase(k)
	if cfg.has_section_key("remaps", k):
		cfg.erase_section_key("remaps", k)
		cfg.save(SAVE_PATH)
	rebuild_pad_bindings()


# ------------------------------------------------------------------ names and prompts

func family(device: int = -2) -> String:
	if device == -2:
		device = last_pad
	if device < 0:
		return "xbox"
	var n := Input.get_joy_name(device).to_lower()
	for w in ["playstation", "dualsense", "dualshock", "ps3", "ps4", "ps5", "sony", "wireless controller"]:
		if n.contains(w):
			return "playstation"
	for w in ["nintendo", "switch", "pro controller", "joy-con", "joycon"]:
		if n.contains(w):
			return "nintendo"
	return "xbox"


## The label printed on the player's controller for a standard control.
func button_name(control: String) -> String:
	var names := {
		"xbox": {"a": "A", "b": "B", "x": "X", "y": "Y", "leftshoulder": "LB", "rightshoulder": "RB", "lefttrigger": "LT", "righttrigger": "RT", "start": "Start", "back": "Back", "rightstick": "R3"},
		"playstation": {"a": "Cross", "b": "Circle", "x": "Square", "y": "Triangle", "leftshoulder": "L1", "rightshoulder": "R1", "lefttrigger": "L2", "righttrigger": "R2", "start": "Options", "back": "Share", "rightstick": "R3"},
		"nintendo": {"a": "B", "b": "A", "x": "Y", "y": "X", "leftshoulder": "L", "rightshoulder": "R", "lefttrigger": "ZL", "righttrigger": "ZR", "start": "+", "back": "-", "rightstick": "R-stick"},
	}
	return names[family()].get(control, control)


func confirm_name() -> String:
	match last_device:
		"gamepad":
			return button_name("a")
		"touch":
			return "A"
	return "Space"


func hint_text() -> String:
	match last_device:
		"gamepad":
			return "Left stick / D-pad: move · %s or %s: sword (hold to spin) · %s: roll / talk · %s: lock on · Right stick: camera · %s: recenter · %s: pause" % [
				button_name("x"), button_name("b"), button_name("a"), button_name("lefttrigger"), button_name("y"), button_name("start")]
		"touch":
			return "Stick: move · B: sword (hold to spin) · A: roll / talk · Z: lock on · drag right side: camera"
	return "WASD move · J / click: sword (hold to spin) · Space: roll / talk · Tab: lock on · Q/E R/F: camera · C: recenter · Esc: pause"


func rumble(weak: float, strong: float, duration: float) -> void:
	if last_device != "gamepad" or last_pad < 0:
		return
	Input.start_joy_vibration(last_pad, weak, strong, duration)
