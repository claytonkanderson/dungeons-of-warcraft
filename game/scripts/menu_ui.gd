class_name MenuUI
extends CanvasLayer
## Esc menu: save/load, volume settings, quit. Dark D2-styled panel.

var open := false
var world = null
var root: Control
var _panel: ColorRect
var _box: VBoxContainer


func _ready() -> void:
	layer = 8
	root = Control.new()
	root.visible = false
	add_child(root)
	_panel = ColorRect.new()
	_panel.color = Color(0.03, 0.02, 0.02, 0.93)
	root.add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 10)
	_panel.add_child(_box)
	_build()


func toggle() -> void:
	open = not open
	root.visible = open
	if open:
		_layout()


func _label(text: String, px := 20, color := Color(0.9, 0.82, 0.6)) -> Label:
	var l := Label.new()
	l.text = text
	get_node("/root/D2Font").style(l, px)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	get_node("/root/D2Font").style(b, 20)
	b.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 0.7))
	b.pressed.connect(cb)
	return b


func _slider(text: String, key: String) -> void:
	var st := get_node("/root/Settings")
	_box.add_child(_label(text, 16, Color(0.7, 0.65, 0.5)))
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(st.get(key))
	s.custom_minimum_size = Vector2(260, 20)
	s.value_changed.connect(func(v): st.set_volume(key, v))
	_box.add_child(s)


func _build() -> void:
	_box.add_child(_label("AMAZON  DEADMINES", 26))
	_box.add_child(_label(" ", 8))
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
	_box.add_child(_label(" ", 8))
	_slider("Master Volume", "master")
	_slider("Music + Ambience", "music")
	_slider("Sound Effects", "effects")
	_box.add_child(_label(" ", 8))
	_box.add_child(_button("Save and Quit", func():
		var gs := get_node("/root/GameState")
		gs.save_game(world.player if world != null else null)
		get_tree().quit()))


func _layout() -> void:
	var vp := root.get_viewport_rect().size
	var size := Vector2(360, 480)
	_panel.size = size
	_panel.position = (vp - size) * 0.5
	_box.position = Vector2(30, 24)
	_box.size = size - Vector2(60, 48)
