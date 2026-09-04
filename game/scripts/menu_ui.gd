class_name MenuUI
extends CanvasLayer
## Esc menu: save/load, volume settings, quit — on D2's own plate and button
## art, in D2's font, sized to clear the control panel at every scale.

const MARGIN := 22.0                  # same black border on all four sides
const BUTTON_SIZE := Vector2(256, 35)
const GOLD := Color(0.85, 0.78, 0.55)
const DIM_GOLD := Color(0.66, 0.6, 0.42)
const EDGE := Color(0.55, 0.45, 0.22)

var open := false
var world = null
var root: Control
var _panel: Panel
var _box: VBoxContainer


func _ready() -> void:
	layer = 8
	root = Control.new()
	root.visible = false
	add_child(root)
	_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.02, 0.02, 0.94)
	sb.border_color = EDGE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(2)
	_panel.add_theme_stylebox_override("panel", sb)
	root.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(_box)
	_build()


func toggle() -> void:
	open = not open
	root.visible = open
	if open:
		_layout()
		# the big area-name label sits on the HUD layer above this one
		if world != null and world.hud_node != null and world.hud_node._area_label != null:
			world.hud_node._area_label.visible = false


func _frame_tex(sheet_name: String, frame: int) -> Texture2D:
	var sheet = get_node("/root/SpriteDB").load_sheet(sheet_name)
	if sheet == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = sheet.texture
	at.region = Rect2(frame * sheet.cell.x, 0, sheet.cell.x, sheet.cell.y)
	return at


func _label(text: String, px := 20, color := GOLD) -> Label:
	var l := Label.new()
	l.text = text
	get_node("/root/D2Font").style(l, px)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _button(text: String, cb: Callable) -> Button:
	## D2's wide blank button (WideButtonBlank.dc6): plate up, plate down.
	var b := Button.new()
	b.text = text
	get_node("/root/D2Font").style(b, 16)
	b.add_theme_color_override("font_color", GOLD)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 0.7))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 0.7))
	b.custom_minimum_size = BUTTON_SIZE
	b.focus_mode = Control.FOCUS_NONE
	var idle := _frame_tex("ui/menubutton",0)
	if idle != null:
		var up := StyleBoxTexture.new()
		up.texture = idle
		b.add_theme_stylebox_override("normal", up)
		b.add_theme_stylebox_override("hover", up)
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var down := StyleBoxTexture.new()
		down.texture = _frame_tex("ui/menubutton",2)
		b.add_theme_stylebox_override("pressed", down)
	b.pressed.connect(func():
		get_node("/root/Sfx").event_ui("button")
		cb.call())
	return b


func _slider(text: String, key: String) -> void:
	var st := get_node("/root/Settings")
	_box.add_child(_label(text, 14, DIM_GOLD))
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(st.get(key))
	s.custom_minimum_size = Vector2(BUTTON_SIZE.x, 14)
	s.focus_mode = Control.FOCUS_NONE
	# D2 colours: a dark track with a gold fill and a small gold knob
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.08, 0.06, 0.04)
	track.border_color = EDGE
	track.set_border_width_all(1)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	s.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.72, 0.58, 0.25)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob := _knob_tex()
	s.add_theme_icon_override("grabber", knob)
	s.add_theme_icon_override("grabber_highlight", knob)
	s.add_theme_icon_override("grabber_disabled", knob)
	s.value_changed.connect(func(v): st.set_volume(key, v))
	_box.add_child(s)


func _knob_tex() -> Texture2D:
	var img := Image.create(10, 14, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.85, 0.72, 0.35))
	for x in range(10):
		for y in range(14):
			if x == 0 or x == 9 or y == 0 or y == 13:
				img.set_pixel(x, y, Color(0.35, 0.27, 0.12))
	return ImageTexture.create_from_image(img)


func _spacer(h: float) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	_box.add_child(c)


func _build() -> void:
	_box.add_child(_label("DUNGEONS  OF  WARCRAFT", 18))
	_spacer(6)
	_box.add_child(_button("Resume", func():
		if world != null:
			world.toggle_menu()))
	_box.add_child(_button("Save Game", func():
		var gs := get_node("/root/GameState")
		gs.save_game(world.player if world != null else null)
		if world != null and world.hud_node != null:
			world.hud_node.show_area("Saved")))
	_box.add_child(_button("Load Game", func():
		var gs := get_node("/root/GameState")
		if gs.load_game(world.player if world != null else null):
			if world != null:
				world.player.refresh_attack_style()
				if world.hud_node != null:
					world.hud_node.show_area("Loaded")
		elif world != null and world.hud_node != null:
			world.hud_node.show_area("No save found")))
	_box.add_child(_button("Unstuck", func():
		if world != null:
			world.unstuck_player()
			world.toggle_menu()))
	_box.add_child(_button("Fullscreen  (F11)", func():
		Cli.toggle_fullscreen()))
	_spacer(6)
	_slider("Master Volume", "master")
	_slider("Music + Ambience", "music")
	_slider("Sound Effects", "effects")
	_spacer(6)
	# One way out. "Exit to Main Menu" and "Save and Quit" both saved and
	# differed only in destination, and the second did not fit the panel; the
	# main menu already has Quit, and closing the window saves too.
	_box.add_child(_button("Save & Exit", func():
		var gs := get_node("/root/GameState")
		gs.save_game(world.player if world != null else null)
		get_tree().change_scene_to_file("res://scenes/menu.tscn")))


func _layout() -> void:
	## Centred in the space above the control panel, whatever the window: the
	## canvas is always 1280x720 (canvas_items stretch), the HUD takes the
	## bottom 800-mode panel height scaled to the width.
	var vp := root.get_viewport_rect().size
	var hud_h: float = (HUD.PANEL_H + HUD.XP_H) * vp.x / HUD.PANEL_W
	var free_h: float = vp.y - hud_h
	# the plate is sized from what is on it, plus the same margin all round;
	# every row is centred, so the button art never stretches or drifts
	for c in _box.get_children():
		if c is Control:
			c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var content: Vector2 = _box.get_combined_minimum_size()
	content.x = maxf(content.x, BUTTON_SIZE.x)
	_box.position = Vector2(MARGIN, MARGIN)
	_box.size = content
	_panel.size = content + Vector2(MARGIN, MARGIN) * 2.0
	_panel.position = Vector2((vp.x - _panel.size.x) * 0.5,
			maxf(8.0, (free_h - _panel.size.y) * 0.5))
