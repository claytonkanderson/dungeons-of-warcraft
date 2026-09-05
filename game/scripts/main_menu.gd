extends Control
## "Dungeons of Warcraft" — the launch menu: the selected character standing
## in their own gear on the left, the roster in the middle, the vanilla
## dungeon ladder on the right, over the artwork of whichever dungeon is
## highlighted. Test/automation flags fall straight through into the world.

const GOLD := Color(0.85, 0.72, 0.35)
const GOLD_DIM := Color(0.55, 0.48, 0.3)
const GREY := Color(0.45, 0.45, 0.45)
const DARK := Color(0.3, 0.28, 0.28)
const GREEN := Color(0.25, 0.8, 0.25)
const WHITE := Color(0.9, 0.88, 0.82)

# column geometry (the viewport is a fixed 1280x720)
const DOLL_PANEL := Rect2(34, 140, 240, 500)
const CHAR_PANEL := Rect2(288, 140, 280, 500)
const DUNG_PANEL := Rect2(588, 140, 660, 500)
const ROW_SIZE := Vector2(256, 93)
const BUTTON_Y := 662

var sel_char := ""
var sel_dungeon := ""
var _char_box: VBoxContainer
var _dung_box: VBoxContainer
var _name_edit: LineEdit
var _enter_btn: Button
var _delete_armed := false
var _delete_btn: Button
var _doll: Control
var _doll_name: Label
var _doll_level: Label
var _bg: TextureRect
var _bg_fade: TextureRect
var _bg_shown := ""
var _bg_cache := {}
var _ui_tex := {}

@onready var gs := get_node("/root/GameState")
@onready var dg := get_node("/root/Dungeons")


func _ready() -> void:
	# automation flags bypass the menu entirely (legacy/test save slot)
	Cli.warn_unknown()
	for a in OS.get_cmdline_user_args():
		if str(a) in ["--combat-test", "--ui-test", "--fps-probe",
				"--walk-test", "--fresh"] or str(a).begins_with("--shots=") \
				or str(a).begins_with("--at=") \
				or str(a).begins_with("--dungeon="):
			get_tree().change_scene_to_file.call_deferred("res://scenes/world.tscn")
			return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_node("/root/Music").set_menu()
	gs.migrate_legacy_save()
	_build()
	_refresh()
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--menu-shot="):
			if Cli.offscreen():
				Cli.hide_window()
			for i in range(12):
				await get_tree().process_frame
			await Cli.capture(get_viewport(), str(a).substr(12))
			get_tree().quit()


func _label(text: String, px: int, color := GOLD) -> Label:
	var l := Label.new()
	l.text = text
	get_node("/root/D2Font").style(l, px)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _tex(name: String) -> Texture2D:
	## A D2 UI sheet from assets/ui, loaded once.
	if not _ui_tex.has(name):
		var img := Image.load_from_file(ProjectSettings.globalize_path(
				Paths.asset("ui/%s.png" % name)))
		_ui_tex[name] = ImageTexture.create_from_image(img) if img != null else null
	return _ui_tex[name]


func _frame_tex(name: String, frame: int, frames: int) -> Texture2D:
	## One frame out of a horizontal D2 sheet (idle / pressed).
	var t := _tex(name)
	if t == null:
		return null
	var w := int(t.get_width() / float(frames))
	var at := AtlasTexture.new()
	at.atlas = t
	at.region = Rect2(frame * w, 0, w, t.get_height())
	return at


func _skin(button: Button, name: String, frames: int, pressed_frame: int) -> bool:
	## Dress a Button in D2 art; false when the art is missing. These sheets
	## interleave the full plate with narrow edge pieces, so the pressed state
	## is not simply frame 1.
	var idle := _frame_tex(name, 0, frames)
	if idle == null:
		return false
	var box := _frame_box(idle)
	button.add_theme_stylebox_override("normal", box)
	button.add_theme_stylebox_override("hover", box)
	button.add_theme_stylebox_override("disabled", box)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed",
			_frame_box(_frame_tex(name, pressed_frame, frames)))
	return true


static func _frame_box(frame: AtlasTexture) -> StyleBoxTexture:
	## A StyleBoxTexture draws its texture's whole atlas unless told the
	## region: given the AtlasTexture straight, the entire sheet was squeezed
	## into the button and the one-pixel side borders vanished. The sheet
	## plus the frame's region, with the border kept at its own width.
	var box := StyleBoxTexture.new()
	box.texture = frame.atlas
	box.region_rect = frame.region
	box.texture_margin_left = 4
	box.texture_margin_right = 4
	box.texture_margin_top = 4
	box.texture_margin_bottom = 4
	return box


func _button(text: String, px: int, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	get_node("/root/D2Font").style(b, px)
	b.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 0.7))
	b.add_theme_color_override("font_disabled_color", Color(0.4, 0.37, 0.3))
	b.pressed.connect(cb)
	return b


func _panel(rect: Rect2) -> void:
	## The dark plate the text sits on, so the backdrop can be busy.
	var p := ColorRect.new()
	p.color = Color(0.024, 0.02, 0.016, 0.62)
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(p)
	var edge := ReferenceRect.new()
	edge.border_color = Color(0.33, 0.27, 0.14, 0.8)
	edge.border_width = 1.0
	edge.editor_only = false
	edge.position = rect.position
	edge.size = rect.size
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(edge)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.025)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_bg = TextureRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	_bg_fade = TextureRect.new()
	_bg_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_fade.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_fade.modulate.a = 0.0
	add_child(_bg_fade)

	var title := _label("DUNGEONS  OF  WARCRAFT", 42)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.position.y = 38
	add_child(title)
	var sub := _label("a Diablo / Warcraft hybrid mod", 16, GOLD_DIM)
	sub.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sub.position.y = 92
	add_child(sub)

	# ---- the character, in their own gear (left) ----
	_panel(DOLL_PANEL)
	_doll = preload("res://scripts/paperdoll.gd").new()
	_doll.position = Vector2(DOLL_PANEL.position.x + 8, 200)
	_doll.size = Vector2(DOLL_PANEL.size.x - 16, 348)
	add_child(_doll)
	_doll_name = _label("", 18, GOLD)
	_doll_name.position = Vector2(DOLL_PANEL.position.x, 556)
	_doll_name.size.x = DOLL_PANEL.size.x
	add_child(_doll_name)
	_doll_level = _label("", 14, WHITE)
	_doll_level.position = Vector2(DOLL_PANEL.position.x, 582)
	_doll_level.size.x = DOLL_PANEL.size.x
	add_child(_doll_level)

	# ---- characters (middle) ----
	_panel(CHAR_PANEL)
	var chead := _label("CHARACTERS", 20, WHITE)
	chead.position = Vector2(CHAR_PANEL.position.x, 150)
	chead.size.x = CHAR_PANEL.size.x
	add_child(chead)
	# wide enough for a full 256 px row plus the vertical scrollbar beside
	# it; at 266 the bar sat over the rows' right border and hid it
	var cscroll := ScrollContainer.new()
	cscroll.position = Vector2(292, 180)
	cscroll.size = Vector2(274, 360)
	cscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(cscroll)
	_char_box = VBoxContainer.new()
	_char_box.custom_minimum_size.x = ROW_SIZE.x
	_char_box.add_theme_constant_override("separation", 4)
	cscroll.add_child(_char_box)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "new character"
	_name_edit.max_length = 20
	_name_edit.position = Vector2(296, 552)
	_name_edit.size = Vector2(176, 32)
	add_child(_name_edit)
	var create := _button("Create", 15, _on_create)
	create.position = Vector2(478, 552)
	create.size = Vector2(84, 32)
	add_child(create)
	_delete_btn = _button("Delete", 14, _on_delete)
	_delete_btn.position = Vector2(296, 594)
	_delete_btn.size = Vector2(110, 30)
	add_child(_delete_btn)

	# ---- dungeons (right) ----
	_panel(DUNG_PANEL)
	var dhead := _label("DUNGEONS", 20, WHITE)
	dhead.position = Vector2(DUNG_PANEL.position.x, 150)
	dhead.size.x = DUNG_PANEL.size.x
	add_child(dhead)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(600, 180)
	scroll.size = Vector2(636, 444)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_dung_box = VBoxContainer.new()
	_dung_box.custom_minimum_size.x = 616
	_dung_box.add_theme_constant_override("separation", 2)
	scroll.add_child(_dung_box)

	# ---- bottom bar ----
	_enter_btn = _button("ENTER  DUNGEON", 18, _on_enter)
	_enter_btn.position = Vector2(460, BUTTON_Y)
	_enter_btn.size = Vector2(256, 35)
	_skin(_enter_btn, "menubutton", 4, 2)
	add_child(_enter_btn)
	var quit := _button("QUIT", 18, func(): get_tree().quit())
	quit.position = Vector2(780, BUTTON_Y)
	quit.size = Vector2(256, 35)
	_skin(quit, "menubutton", 4, 2)
	add_child(quit)


func _char_data(slug: String) -> Dictionary:
	if slug == "":
		return {}
	var f := FileAccess.open(gs.CHAR_DIR + "/%s.json" % slug, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d is Dictionary else {}


func _backdrop(id: String) -> void:
	## Cross-fade to this dungeon's artwork.
	if id == _bg_shown:
		return
	if not _bg_cache.has(id):
		var img := Image.load_from_file(ProjectSettings.globalize_path(
				Paths.asset("wow/backdrops/%s.png" % id)))
		_bg_cache[id] = ImageTexture.create_from_image(img) if img != null else null
	var tex: Texture2D = _bg_cache[id]
	if tex == null:
		return
	_bg_shown = id
	if _bg.texture == null:
		_bg.texture = tex
		return
	_bg_fade.texture = tex
	_bg_fade.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_bg_fade, "modulate:a", 1.0, 0.35)
	tw.tween_callback(func():
		_bg.texture = tex
		_bg_fade.modulate.a = 0.0)


func _show_doll(slug: String, data: Dictionary) -> void:
	if slug == "" or data.is_empty():
		_doll.clear()
		_doll_name.text = ""
		_doll_level.text = ""
		return
	_doll.show_character(data.get("equipped", {}))
	_doll_name.text = str(data.get("name", slug))
	_doll_level.text = "Level %d Amazon" % int(data.get("level", 1))


func _refresh() -> void:
	for n in _char_box.get_children():
		n.queue_free()
	for n in _dung_box.get_children():
		n.queue_free()
	var chars: Array = gs.list_characters()
	if sel_char == "" and not chars.is_empty():
		# whoever was being played comes back selected. Falling straight to
		# chars[0] meant leaving a dungeon quietly switched you to whichever
		# character sorted first.
		var playing := str(gs.character)
		sel_char = str(chars[0].slug)
		for c in chars:
			if str(c.slug) == playing:
				sel_char = playing
				break
	for c in chars:
		var slug := str(c.slug)
		var picked := slug == sel_char
		var b := Button.new()
		b.custom_minimum_size = ROW_SIZE
		b.pressed.connect(func():
			sel_char = slug
			_delete_armed = false
			_delete_btn.text = "Delete"
			_refresh())
		if not _skin(b, "charbox" if picked else "charbox_off", 2, 0):
			b.flat = true
		var nm := _label(str(c.name), 18, GOLD if picked else DARK)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		nm.position = Vector2(22, 24)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(nm)
		var lv := _label("Level %d" % int(c.level), 15, WHITE if picked else DARK)
		lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lv.position = Vector2(22, 52)
		lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(lv)
		_char_box.add_child(b)
	if chars.is_empty():
		var hint := _label("create a character below", 14, GREY)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_char_box.add_child(hint)

	var data := _char_data(sel_char)
	var done: Array = data.get("dungeons_done", [])
	_show_doll(sel_char, data)
	if sel_dungeon == "" \
			or not (str(dg.status(sel_dungeon, done)) in ["available", "complete"]):
		sel_dungeon = dg.next_playable(done)
	for d in dg.LIST:
		var did := str(d.id)
		var st := str(dg.status(did, done))
		var row := Button.new()
		row.flat = true
		row.custom_minimum_size = Vector2(616, 26)
		row.pressed.connect(func():
			if st in ["available", "complete"]:
				sel_dungeon = did
				_refresh())
		_dung_box.add_child(row)
		if did == sel_dungeon:
			var lit := ColorRect.new()
			lit.color = Color(0.24, 0.19, 0.08, 0.55)
			lit.size = Vector2(616, 24)
			lit.position = Vector2(0, 1)
			lit.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(lit)
		var name_l := _label(str(d.name), 16, WHITE)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_l.position = Vector2(30, 2)
		name_l.size = Vector2(330, 22)
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(name_l)
		var lvl_l := _label(str(d.levels), 16, GREY)
		lvl_l.position = Vector2(378, 2)
		lvl_l.size = Vector2(80, 22)
		lvl_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lvl_l)
		var st_text: String = {"complete": "COMPLETE", "available": "AVAILABLE",
				"unbuilt": "NOT BUILT", "locked": "LOCKED"}[st]
		var st_col: Color = {"complete": GREEN, "available": GOLD,
				"unbuilt": Color(0.3, 0.3, 0.35), "locked": GREY}[st]
		var st_l := _label(str(st_text), 14, st_col)
		st_l.position = Vector2(474, 3)
		st_l.size = Vector2(130, 22)
		st_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(st_l)
		if did == sel_dungeon and st in ["available", "complete"]:
			var mark := _label(">", 16, GOLD)
			mark.position = Vector2(10, 2)
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(mark)
			name_l.add_theme_color_override("font_color", GOLD)

	_backdrop(sel_dungeon)
	var can_play: bool = sel_char != "" \
			and dg.status(sel_dungeon, done) in ["available", "complete"]
	_enter_btn.disabled = not can_play


func _on_create() -> void:
	var slug: String = gs.create_character(_name_edit.text)
	if slug == "":
		_name_edit.placeholder_text = "name taken / invalid"
		_name_edit.text = ""
		return
	_name_edit.text = ""
	sel_char = slug
	_refresh()


func _on_delete() -> void:
	if sel_char == "":
		return
	if not _delete_armed:
		_delete_armed = true
		_delete_btn.text = "Confirm?"
		return
	gs.delete_character(sel_char)
	sel_char = ""
	_delete_armed = false
	_delete_btn.text = "Delete"
	_refresh()


func _enter(did: String) -> void:
	if sel_char == "" or not gs.select_character(sel_char):
		return
	gs.enter_dungeon(did)
	get_tree().change_scene_to_file("res://scenes/world.tscn")


func _on_enter() -> void:
	_enter(sel_dungeon)


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_F11:
		Cli.toggle_fullscreen()
		get_viewport().set_input_as_handled()
