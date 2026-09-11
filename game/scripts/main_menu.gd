extends Control
## "Dungeons of Warcraft" — the launch menu: the selected character standing
## in their own gear on the left, the roster in the middle, the vanilla
## dungeon ladder on the right, over the artwork of whichever dungeon is
## highlighted. Test/automation flags fall straight through into the world.
##
## Co-op: HOST opens a session and the lobby takes the left column (the
## address to send, who is in); JOIN asks for the host's address. The host
## picks the dungeon and START takes everyone in together (net.gd).

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
var _lobby: Control
var _lobby_status: Label
var _lobby_players: GridContainer
var _lobby_phead: Label
var _lobby_ip: LineEdit
var _lobby_connect: Button
var _lobby_leave: Button
var _host_btn: Button
var _join_btn: Button
var _joining := false           # JOIN pressed: the address field is up

@onready var gs := get_node("/root/GameState")
@onready var dg := get_node("/root/Dungeons")


func _ready() -> void:
	# automation flags bypass the menu entirely (legacy/test save slot);
	# a session from the command line goes through the lobby below
	Cli.warn_unknown()
	var session_flag: bool = Cli.has("--host") or Cli.value("--join=") != ""
	for a in OS.get_cmdline_user_args():
		if session_flag:
			break
		if str(a) in ["--combat-test", "--ui-test", "--fps-probe",
				"--walk-test", "--fresh"] or str(a).begins_with("--shots=") \
				or str(a).begins_with("--at=") \
				or str(a).begins_with("--dungeon=") \
				or str(a).begins_with("--replay="):
			get_tree().change_scene_to_file.call_deferred("res://scenes/world.tscn")
			return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_node("/root/Music").set_menu()
	gs.migrate_legacy_save()
	_build()
	Net.roster_changed.connect(_lobby_refresh)
	Net.status_changed.connect(_lobby_refresh)
	Net.launched.connect(_on_launched)
	Net.session_ended.connect(_on_session_ended)
	Net.start_refused.connect(func(_who, _did, _why): _refresh())
	# --host / --join=<ip>: straight into a session (with --dungeon= the
	# host opens that dungeon at once; a joiner is taken in when it is)
	if Cli.has("--host") or Cli.value("--join=") != "":
		_pick_any_character()
		if Cli.has("--host"):
			var err := Net.host()
			if err != "":
				printerr("host: %s" % err)
			var did := Cli.value("--dungeon=")
			if did != "" and not dg.entry(did).is_empty():
				sel_dungeon = did
				Net.request_start.call_deferred(did)
		else:
			_joining = true
			var jerr := Net.join(Cli.value("--join="))
			if jerr != "":
				printerr("join: %s" % jerr)
	_refresh()
	if Net.last_error != "":
		_lobby_refresh()
	# back from a dungeon with the session still up: the roster shows the
	# level this character is at now
	Net.announce()
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--menu-shot="):
			if Cli.offscreen():
				Cli.hide_window()
			# a session flag: long enough for a joiner to connect before the shot
			for i in range(600 if session_flag else 12):
				await get_tree().process_frame
			await Cli.capture(get_viewport(), str(a).substr(12))
			get_tree().quit()


func _label(text: String, px: int, color := GOLD) -> Label:
	var l := Label.new()
	l.text = text
	get_node("/root/D2Font").style_near(l, px)
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
	get_node("/root/D2Font").style_near(b, px)
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
	var chead := _label("CHARACTERS", 24, WHITE)
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
	var dhead := _label("DUNGEONS", 24, WHITE)
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
	_enter_btn.position = Vector2(80, BUTTON_Y)
	_enter_btn.size = Vector2(256, 35)
	_skin(_enter_btn, "menubutton", 4, 2)
	add_child(_enter_btn)
	_host_btn = _button("HOST  CO-OP", 18, _on_host)
	_host_btn.position = Vector2(356, BUTTON_Y)
	_host_btn.size = Vector2(256, 35)
	_skin(_host_btn, "menubutton", 4, 2)
	add_child(_host_btn)
	_join_btn = _button("JOIN  CO-OP", 18, _on_join)
	_join_btn.position = Vector2(632, BUTTON_Y)
	_join_btn.size = Vector2(256, 35)
	_skin(_join_btn, "menubutton", 4, 2)
	add_child(_join_btn)
	var quit := _button("QUIT", 18, func(): get_tree().quit())
	quit.position = Vector2(908, BUTTON_Y)
	quit.size = Vector2(256, 35)
	_skin(quit, "menubutton", 4, 2)
	add_child(quit)

	# master volume, top right: reachable before anything else plays long
	var st := get_node("/root/Settings")
	var vl := _label("VOLUME", 14, GOLD_DIM)
	vl.position = Vector2(1060, 96)
	vl.size = Vector2(80, 20)
	add_child(vl)
	var vs := HSlider.new()
	vs.min_value = 0.0
	vs.max_value = 1.0
	vs.step = 0.05
	vs.value = float(st.master)
	vs.position = Vector2(1140, 98)
	vs.size = Vector2(110, 16)
	vs.focus_mode = Control.FOCUS_NONE
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.08, 0.06, 0.04)
	track.border_color = GOLD_DIM
	track.set_border_width_all(1)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	vs.add_theme_stylebox_override("slider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.72, 0.58, 0.25)
	vs.add_theme_stylebox_override("grabber_area", fill)
	vs.add_theme_stylebox_override("grabber_area_highlight", fill)
	vs.value_changed.connect(func(v): st.set_volume("master", v))
	add_child(vs)

	# ---- the lobby, over the paperdoll while a session is up ----
	_lobby = Control.new()
	_lobby.position = DOLL_PANEL.position
	_lobby.size = DOLL_PANEL.size
	_lobby.visible = false
	add_child(_lobby)
	var lbg := ColorRect.new()
	lbg.color = Color(0.03, 0.025, 0.02, 0.92)
	lbg.size = DOLL_PANEL.size
	_lobby.add_child(lbg)
	var lhead := _label("CO-OP", 24, WHITE)
	lhead.position = Vector2(0, 10)
	lhead.size.x = DOLL_PANEL.size.x
	_lobby.add_child(lhead)
	_lobby_status = _label("", 12, GOLD)
	_lobby_status.position = Vector2(10, 46)
	_lobby_status.size = Vector2(DOLL_PANEL.size.x - 20, 150)
	_lobby_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_lobby_status.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_lobby.add_child(_lobby_status)
	_lobby_ip = LineEdit.new()
	_lobby_ip.placeholder_text = "host's address"
	_lobby_ip.text = get_node("/root/Settings").host_ip   # the last one joined
	_lobby_ip.position = Vector2(10, 150)
	_lobby_ip.size = Vector2(DOLL_PANEL.size.x - 20, 30)
	_lobby_ip.visible = false
	_lobby_ip.text_submitted.connect(func(_t): _on_connect())   # Enter connects too
	_lobby.add_child(_lobby_ip)
	_lobby_connect = _button("Connect", 14, _on_connect)
	_lobby_connect.position = Vector2(10, 186)
	_lobby_connect.size = Vector2(DOLL_PANEL.size.x - 20, 30)
	_lobby_connect.visible = false
	_lobby.add_child(_lobby_connect)
	_lobby_phead = _label("IN THE SESSION", 14, WHITE)
	_lobby_phead.position = Vector2(0, 216)
	_lobby_phead.size.x = DOLL_PANEL.size.x
	_lobby.add_child(_lobby_phead)
	# two by two: each Amazon at the paperdoll's own pixel size, her name
	# under her, four fitting above the leave button
	_lobby_players = GridContainer.new()
	_lobby_players.columns = 2
	_lobby_players.position = Vector2(10, 236)
	_lobby_players.size = Vector2(DOLL_PANEL.size.x - 20, 226)
	_lobby_players.add_theme_constant_override("h_separation", 4)
	_lobby_players.add_theme_constant_override("v_separation", 2)
	# the grid is drawn after the address field and button; it must not
	# take their clicks (it swallowed Connect for the first testers)
	_lobby_players.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lobby.add_child(_lobby_players)
	_lobby_leave = _button("Leave session", 14, _on_leave)
	_lobby_leave.position = Vector2(10, DOLL_PANEL.size.y - 34)
	_lobby_leave.size = Vector2(DOLL_PANEL.size.x - 20, 30)
	_lobby.add_child(_lobby_leave)


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
	if Net.is_host():
		_enter_btn.text = "START  SESSION"
		_enter_btn.disabled = not can_play
	elif Net.is_client() or _joining:
		_enter_btn.text = "HOST  STARTS"
		_enter_btn.disabled = true
	else:
		_enter_btn.text = "ENTER  DUNGEON"
		_enter_btn.disabled = not can_play
	_host_btn.disabled = Net.role != Net.Role.OFF or _joining
	_join_btn.disabled = Net.role != Net.Role.OFF or _joining
	_lobby_refresh()


func _pick_any_character() -> void:
	## --host / --join= from the command line: whoever was played last, or
	## the first on the roster, or a fresh one
	var chars: Array = gs.list_characters()
	if chars.is_empty():
		sel_char = gs.create_character("Amazon")
	else:
		sel_char = str(chars[0].slug)
		for c in chars:
			if str(c.slug) == str(gs.character):
				sel_char = str(gs.character)
	gs.select_character(sel_char)     # the roster shows the real level


func _lobby_refresh() -> void:
	var up: bool = Net.role != Net.Role.OFF or _joining
	_lobby.visible = up
	_doll.visible = not up
	_doll_name.visible = not up
	_doll_level.visible = not up
	if not up:
		return
	var text := Net.status
	if _joining and Net.role == Net.Role.OFF:
		text = "Paste the host's address and Connect. On the host's own network, one of its LAN addresses."
		if Net.last_error != "":
			text = Net.last_error + "\n\n" + text
	_lobby_status.text = text
	_lobby_ip.visible = _joining and Net.role == Net.Role.OFF
	_lobby_connect.visible = _lobby_ip.visible
	# nobody to list until the connection is up
	_lobby_phead.visible = not _lobby_ip.visible
	_lobby_players.visible = not _lobby_ip.visible
	for n in _lobby_players.get_children():
		n.queue_free()
	var ids: Array = Net.roster.keys()
	ids.sort()
	for id in ids:
		var r: Dictionary = Net.roster[id]
		# each Amazon in her own gear beside her name, as the paperdoll draws
		# the selected character, at a third of its size
		var row := VBoxContainer.new()
		row.custom_minimum_size = Vector2(108, 112)
		row.add_theme_constant_override("separation", 0)
		var doll = preload("res://scripts/paperdoll.gd").new()
		doll.px_scale = 0                    # fitted: helms and weapons make the canvas taller than a row
		doll.custom_minimum_size = Vector2(108, 84)
		doll.size = Vector2(108, 84)
		row.add_child(doll)
		var caption := _label("%s\nlevel %d%s" % [str(r.get("name", "?")), int(r.get("level", 1)),
				", host" if int(id) == 1 else ""], 12, GOLD if int(id) == Net.my_id() else WHITE)
		caption.custom_minimum_size = Vector2(108, 28)
		row.add_child(caption)
		_lobby_players.add_child(row)
		doll.show_character(r.get("gear", {}))   # once in the tree: the manifest loads in _ready
	if ids.is_empty() and not _joining:
		var w := _label("nobody yet", 14, GREY)
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_lobby_players.add_child(w)


func _on_host() -> void:
	if sel_char == "" or not gs.select_character(sel_char):
		return
	Net.last_error = ""
	var err := Net.host()
	if err != "":
		Net.last_error = err
	_refresh()


func _on_join() -> void:
	if sel_char == "" or not gs.select_character(sel_char):
		return
	Net.last_error = ""
	_joining = true
	_refresh()
	_lobby_ip.grab_focus()


func _on_connect() -> void:
	Net.last_error = ""
	var err := Net.join(_lobby_ip.text)
	if err != "":
		Net.last_error = err
	else:
		get_node("/root/Settings").set_host_ip(_lobby_ip.text.strip_edges())
	_refresh()


func _on_leave() -> void:
	_joining = false
	Net.leave()
	_refresh()


func _on_launched(did: String) -> void:
	if sel_char == "":
		_pick_any_character()
	_enter(did)


func _on_session_ended(_why: String) -> void:
	_joining = Net.last_error != "" and _joining
	if Cli.has("--net-test"):
		print("NET-TEST session ended at the menu: %s" % Net.last_error)
		get_tree().quit()
		return
	if is_inside_tree():
		_refresh()


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
	if Net.is_host():
		Net.request_start(sel_dungeon)
	elif Net.is_client():
		return
	else:
		_enter(sel_dungeon)


func _unhandled_key_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_F11:
		Cli.toggle_fullscreen()
		get_viewport().set_input_as_handled()
