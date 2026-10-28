extends Control
## Hearts, shard count, clock, lock-on letterbox, dialog box, title card, game over.

var main
var bars := 0.0
var bars_target := 0.0
var clock_label: Label
var shard_label: Label
var title: Label
var subtitle: Label
var over_title: Label
var over_sub: Label
var hint: Label
var dialog_panel: Panel
var name_label: Label
var text_label: Label
var more_label: Label
var title_time := 0.0
var hint_time := 0.0
var chars_shown := 0.0
var last_blip := 0
var toast_label: Label
var toast_time := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock_label = make_label(self, 10, HORIZONTAL_ALIGNMENT_RIGHT)
	shard_label = make_label(self, 10)
	title = make_label(self, 30, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_color_override("font_color", Color(0.93, 0.9, 0.8))
	title.add_theme_constant_override("outline_size", 6)
	title.text = "WRENMOOR"
	subtitle = make_label(self, 11, HORIZONTAL_ALIGNMENT_CENTER)
	subtitle.add_theme_color_override("font_color", Color(0.85, 0.72, 0.6))
	subtitle.text = "The First Night — the pale moon rises"
	over_title = make_label(self, 22, HORIZONTAL_ALIGNMENT_CENTER)
	over_title.add_theme_color_override("font_color", Color(0.85, 0.2, 0.18))
	over_title.text = "YOU HAVE FALLEN"
	over_sub = make_label(self, 10, HORIZONTAL_ALIGNMENT_CENTER)
	over_title.visible = false
	over_sub.visible = false
	hint = make_label(self, 8, HORIZONTAL_ALIGNMENT_CENTER)
	hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	toast_label = make_label(self, 10, HORIZONTAL_ALIGNMENT_CENTER)
	toast_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))

	dialog_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.1, 0.86)
	sb.border_color = Color(0.62, 0.6, 0.78)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	dialog_panel.add_theme_stylebox_override("panel", sb)
	dialog_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dialog_panel)
	name_label = make_label(dialog_panel, 9)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.45))
	text_label = make_label(dialog_panel, 10)
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	more_label = make_label(dialog_panel, 9)
	more_label.text = "»"
	dialog_panel.visible = false


func make_label(parent: Node, fs: int, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 3)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func set_hint(text: String) -> void:
	hint.text = text
	hint_time = 14.0


func toast(text: String) -> void:
	toast_label.text = text
	toast_time = 2.5


func show_dialog(speaker: String, text: String) -> void:
	dialog_panel.visible = true
	name_label.text = speaker
	text_label.text = text
	chars_shown = 0.0
	text_label.visible_characters = 0
	last_blip = 0


func hide_dialog() -> void:
	dialog_panel.visible = false


func dialog_typing() -> bool:
	var vc := text_label.visible_characters
	return vc >= 0 and vc < text_label.get_total_character_count()


func finish_typing() -> void:
	chars_shown = float(text_label.get_total_character_count())
	text_label.visible_characters = -1


func show_game_over(on: bool, touch: bool) -> void:
	over_title.visible = on
	over_sub.visible = on
	over_sub.text = "Tap A to rise again" if touch else "Press Space / A to rise again"


func _process(delta: float) -> void:
	var vr := get_viewport_rect().size
	if size != vr:
		size = vr
	var w := size.x
	var h := size.y
	bars = move_toward(bars, bars_target, delta * 4.0)
	title_time += delta

	clock_label.position = Vector2(w - 160, 4)
	clock_label.size = Vector2(154, 14)
	clock_label.text = main.clock_text()
	shard_label.position = Vector2(22, 24)
	shard_label.size = Vector2(80, 14)
	shard_label.text = "× %d" % main.shards

	var title_a := clampf(5.0 - title_time, 0.0, 1.0) * clampf(title_time * 1.5, 0.0, 1.0)
	title.position = Vector2(0, h * 0.28)
	title.size = Vector2(w, 40)
	subtitle.position = Vector2(0, h * 0.28 + 38)
	subtitle.size = Vector2(w, 16)
	title.modulate.a = title_a
	subtitle.modulate.a = title_a

	over_title.position = Vector2(0, h * 0.35)
	over_title.size = Vector2(w, 30)
	over_sub.position = Vector2(0, h * 0.35 + 30)
	over_sub.size = Vector2(w, 14)

	hint_time = maxf(hint_time - delta, 0.0)
	hint.position = Vector2(0, h - 34)
	hint.size = Vector2(w, 12)
	hint.modulate.a = clampf(hint_time, 0.0, 1.0) * (0.0 if dialog_panel.visible else 1.0)

	toast_time = maxf(toast_time - delta, 0.0)
	toast_label.position = Vector2(0, h * 0.62)
	toast_label.size = Vector2(w, 14)
	toast_label.modulate.a = clampf(toast_time, 0.0, 1.0)

	var pw := minf(w - 40.0, 330.0)
	dialog_panel.size = Vector2(pw, 62)
	dialog_panel.position = Vector2((w - pw) * 0.5, h - 62 - 10 - 22.0 * bars)
	name_label.position = Vector2(8, 3)
	name_label.size = Vector2(pw - 16, 12)
	text_label.position = Vector2(8, 15)
	text_label.size = Vector2(pw - 16, 44)
	more_label.position = Vector2(pw - 14, 48)
	if dialog_panel.visible and dialog_typing():
		chars_shown += delta * 45.0
		text_label.visible_characters = int(chars_shown)
		if int(chars_shown) / 3 != last_blip:
			last_blip = int(chars_shown) / 3
			main.sfx.play("blip")
	more_label.visible = dialog_panel.visible and not dialog_typing() and int(title_time * 3.0) % 2 == 0

	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if main.game_over_active:
		draw_rect(Rect2(0, 0, w, h), Color(0.05, 0.0, 0.0, 0.65))
	if bars > 0.01:
		var bh := 22.0 * bars
		draw_rect(Rect2(0, 0, w, bh), Color.BLACK)
		draw_rect(Rect2(0, h - bh, w, bh), Color.BLACK)

	var p = main.player
	var hearts: int = p.max_hp / 2
	for i in hearts:
		var c := Vector2(14 + i * 15, 13)
		var fill: int = clampi(p.hp - i * 2, 0, 2)
		draw_heart(c, 6.6, Color.BLACK, false)
		draw_heart(c, 5.4, Color(0.3, 0.06, 0.07), false)
		if fill == 2:
			draw_heart(c, 5.4, Color(0.95, 0.18, 0.22), false)
		elif fill == 1:
			draw_heart(c, 5.4, Color(0.95, 0.18, 0.22), true)
	# shard icon
	var s := Vector2(14, 31)
	draw_colored_polygon(PackedVector2Array([s + Vector2(0, -6), s + Vector2(4, 0), s + Vector2(0, 6), s + Vector2(-4, 0)]), Color.BLACK)
	draw_colored_polygon(PackedVector2Array([s + Vector2(0, -4.5), s + Vector2(2.8, 0), s + Vector2(0, 4.5), s + Vector2(-2.8, 0)]), Color(0.93, 0.9, 0.78))


func draw_heart(c: Vector2, r: float, col: Color, half: bool) -> void:
	draw_circle(c + Vector2(-r * 0.48, -r * 0.2), r * 0.55, col)
	if not half:
		draw_circle(c + Vector2(r * 0.48, -r * 0.2), r * 0.55, col)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 1.02, 0), c + Vector2(r * 1.02, 0), c + Vector2(0, r * 1.05)]), col)
	else:
		draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 1.02, 0), c + Vector2(0, 0), c + Vector2(0, r * 1.05)]), col)
		draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.6), Vector2(r * 0.6, r * 0.6)), col)
