extends CanvasLayer
## A Diablo II talk menu: the NPC's name over a short list of what they
## offer, on a dark plate mid-screen; the option under the mouse lights
## gold, Cancel (or Esc) closes. world.gd fills it for the Outpost's goblin:
## Gamble, the two respecs, a stash page.

const GOLD := Color(0.95, 0.85, 0.4)
const WHITE := Color(0.9, 0.88, 0.82)
const DIM := Color(0.55, 0.52, 0.48)
const W := 320.0

var open := false
var world = null
var _root: Control
var _plate: Panel
var _box: VBoxContainer


func _ready() -> void:
	layer = 8
	_root = Control.new()
	_root.visible = false
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_plate = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.86)
	sb.border_color = Color(0.35, 0.28, 0.14)
	sb.set_border_width_all(1)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 12.0
	_plate.add_theme_stylebox_override("panel", sb)
	_root.add_child(_plate)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 2)
	_plate.add_child(_box)


func show_menu(npc_name: String, options: Array) -> void:
	## options: [{"label": String, "cb": Callable, "enabled": bool}]. Every
	## choice closes the menu before its callback runs, so a choice that
	## opens a panel does not leave the menu behind it.
	for c in _box.get_children():
		c.queue_free()
	var title := Label.new()
	title.text = npc_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	get_node("/root/D2Font").style(title, 16)
	title.add_theme_color_override("font_color", GOLD)
	title.custom_minimum_size = Vector2(W, 26)
	_box.add_child(title)
	var all: Array = options.duplicate()
	all.append({"label": "Cancel", "cb": Callable(), "enabled": true})
	for o in all:
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.text = str(o.get("label", ""))
		b.custom_minimum_size = Vector2(W, 24)
		get_node("/root/D2Font").style(b, 16)
		var on: bool = bool(o.get("enabled", true))
		b.add_theme_color_override("font_color", WHITE if on else DIM)
		b.add_theme_color_override("font_hover_color", GOLD if on else DIM)
		b.add_theme_color_override("font_pressed_color", GOLD)
		b.add_theme_color_override("font_disabled_color", DIM)
		b.add_theme_color_override("font_hover_pressed_color", GOLD)
		var cb: Callable = o.get("cb", Callable())
		b.pressed.connect(func():
			get_node("/root/Sfx").event_ui("button")
			if not on:
				return
			close()
			if cb.is_valid():
				cb.call())
		_box.add_child(b)
	open = true
	_root.visible = true
	await get_tree().process_frame
	var sz: Vector2 = _box.get_combined_minimum_size() + Vector2(32, 22)
	_plate.size = sz
	var vp := get_viewport().get_visible_rect().size
	_plate.position = Vector2((vp.x - sz.x) * 0.5, vp.y * 0.34 - sz.y * 0.5)


func close() -> void:
	open = false
	_root.visible = false
	if world != null:
		world._sync_ui()


func toggle() -> void:
	## the world's Esc pass closes every open panel through toggle()
	if open:
		close()
