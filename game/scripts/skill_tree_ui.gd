class_name SkillTreeUI
extends CanvasLayer
## The Amazon talent tree on the original skltree_a_back art.
## T toggles. Click = spend a point. Ctrl+click = assign to LMB.
## Right-click = assign to RMB. Keys 1/2/3 switch tabs. F1-F5 bind the
## hovered skill.
##
## Built on D2Panel: the page is the tab's lattice art with the chrome
## column over it, and every icon, number and tab plate is placed in page
## pixels at a spot measured off that art, so it lands in its socket.

# icon sockets measured on the lattice pages: 48 px squares whose bright
# left/bottom edges sit at x = 13, 82, 151 and bottom y = 63 + 68.2 per row
const SOCKET := 48.0
const SOCKET_X := [13.0, 82.0, 151.0]
const SOCKET_Y0 := 15.0
const SOCKET_PITCH_Y := 68.2
# the spare socket bottom-right (Normal Attack) and the chrome's top box,
# where D2 shows the unspent skill points
const ATTACK_RECT := Rect2(172, 386, 31, 31)
const THROW_RECT := Rect2(133, 386, 31, 31)   # left of it: Throw (javelins)
const POINTS_BOX := Rect2(250, 61, 49, 25)
# tab plates in the chrome column: 87x99 at x 228, y 111 / 219 / 327
const TAB_X := 228.0
const TAB_Y0 := 111.0
const TAB_PITCH := 108.0
const TAB_SIZE := Vector2(87, 99)
const TAB_NAMES := ["Bow and Crossbow", "Passive and Magic", "Javelin and Spear"]
const TAB_SHORT := ["Bow", "Passive", "Javelin"]
const GOLD := Color(1.0, 0.9, 0.5)
const DIM := Color(0.55, 0.55, 0.55)

var open := false
var tab := 0
var panel: D2Panel
var tooltip: Label
var _lattice := {}
var _chrome: TextureRect
var _nodes := []
var _hover_skill := ""   # skill under the cursor: F1-F5 binds it

@onready var gs := get_node("/root/GameState")
@onready var db := get_node("/root/SpriteDB")


func _ready() -> void:
	layer = 6
	panel = D2Panel.new("ui/skltree_1.png")
	panel.visible = false
	add_child(panel)
	# the chrome column (tabs, points box) is its own page, drawn over the
	# lattice as the first thing in the content layer
	_chrome = TextureRect.new()
	var img := Image.load_from_file(Paths.asset("ui/skltree_0.png"))
	if img != null:
		_chrome.texture = ImageTexture.create_from_image(img)
	_chrome.size = D2Panel.NATIVE
	_chrome.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.content.add_child(_chrome)
	tooltip = Label.new()
	get_node("/root/D2Font").style(tooltip, 16)
	tooltip.add_theme_color_override("font_color", Color(1, 1, 1))
	tooltip.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	tooltip.add_theme_constant_override("outline_size", 5)
	add_child(tooltip)
	tooltip.visible = false
	gs.skills_changed.connect(_rebuild)


func _lattice_tex(i: int) -> Texture2D:
	if _lattice.has(i):
		return _lattice[i]
	var img := Image.load_from_file(Paths.asset("ui/skltree_%d.png" % (i + 1)))
	var t: Texture2D = ImageTexture.create_from_image(img) if img != null else null
	_lattice[i] = t
	return t


func toggle() -> void:
	# mouse/look state is owned by the world's _sync_ui()
	open = not open
	panel.visible = open
	if open:
		panel.fit(get_viewport().get_visible_rect().size, true)
		_rebuild()
	else:
		tooltip.visible = false


func _amazon_skills_on_page(page: int) -> Array:
	var out := []
	var gd: Dictionary = db.gamedata()
	for name in gd.get("skills", {}):
		var r: Dictionary = gd["skills"][name]
		if r.get("charclass", "") != "ama":
			continue
		var sd: Dictionary = gd.get("skilldesc", {}).get(str(name).to_lower(), {})
		if sd.is_empty() or int(str(sd.get("page", "0")).to_int()) != page:
			continue
		out.append({"name": name, "row": int(str(sd.get("row", "1")).to_int()),
				"col": int(str(sd.get("col", "1")).to_int()),
				"icon": int(str(sd.get("icon", "0")).to_int()), "def": r})
	return out


func _socket(col: int, row: int) -> Rect2:
	var x: float = SOCKET_X[clampi(col - 1, 0, 2)]
	return Rect2(x, SOCKET_Y0 + (row - 1) * SOCKET_PITCH_Y, SOCKET, SOCKET)


func _icon(sheet, frame: int, rect: Rect2, tint := Color(1, 1, 1)) -> TextureRect:
	var at := AtlasTexture.new()
	at.atlas = sheet.texture
	at.region = Rect2(frame * sheet.cell.x, 0, sheet.cell.x, sheet.cell.y)
	var tr := TextureRect.new()
	tr.texture = at
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.position = rect.position
	tr.size = rect.size
	tr.modulate = tint
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(tr)
	return tr


func _text(rect: Rect2, s: String, color: Color, px := 14, fit := false) -> D2Field:
	## the page's small numbers and captions: font8 at its native 14 px
	var f := D2Field.new(rect, mini(px, 14), color, HORIZONTAL_ALIGNMENT_CENTER, fit, "font8")
	_add(f)
	f.set_value(s)
	return f


func _button(rect: Rect2) -> Button:
	var b := Button.new()
	b.flat = true
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	_add(b)
	return b


func _add(n: Control) -> void:
	panel.content.add_child(n)
	_nodes.append(n)


func _rebuild() -> void:
	if not open:
		return
	for n in _nodes:
		n.queue_free()
	_nodes.clear()
	panel.page.texture = _lattice_tex(tab)

	# unspent points in the chrome's top box
	_text(POINTS_BOX, str(gs.skill_points), GOLD if gs.skill_points > 0 else DIM)

	# tab plates: signature skill icon + short name, the active tab lit
	var icon_sheet = db.load_sheet("ui/amskillicon")
	for i in range(3):
		var plate := Rect2(Vector2(TAB_X, TAB_Y0 + i * TAB_PITCH), TAB_SIZE)
		var active := i == tab
		var sig := _amazon_skills_on_page(i + 1)
		sig.sort_custom(func(a, b): return a.row * 10 + a.col < b.row * 10 + b.col)
		if icon_sheet != null and not sig.is_empty():
			_icon(icon_sheet, int(sig[0].icon),
					Rect2(plate.position + Vector2((TAB_SIZE.x - SOCKET) * 0.5, 8), Vector2(SOCKET, SOCKET)),
					Color(1, 1, 1) if active else Color(0.45, 0.45, 0.5))
		_text(Rect2(plate.position + Vector2(0, 62), Vector2(TAB_SIZE.x, 20)),
				TAB_SHORT[i], GOLD if active else DIM)
		_button(plate).pressed.connect(func():
			tab = i
			_rebuild())

	# Normal Attack in the spare socket: bind it back to either hand or a
	# hotkey, same gestures as any learned skill
	var atk_sheet = db.load_sheet("ui/skilliconpanel")
	if atk_sheet != null:
		for basic in [["Attack", 2, ATTACK_RECT, "Normal Attack"],
				["Throw", 6, THROW_RECT, "Throw (javelins)"]]:
			var bname: String = basic[0]
			var brect: Rect2 = basic[2]
			_icon(atk_sheet, int(basic[1]), brect)
			_hotkey_badge(bname, brect)
			var ab := _button(brect)
			ab.mouse_entered.connect(func():
				_hover_skill = bname
				_show_tip(str(basic[3]) + "\nctrl+click: LMB   right-click: RMB\nF1-F5: bind hotkey",
						brect))
			ab.mouse_exited.connect(_hide_tip)
			ab.gui_input.connect(func(ev):
				if not (ev is InputEventMouseButton and ev.pressed):
					return
				var p: Player = get_tree().get_first_node_in_group("player")
				if p == null:
					return
				if ev.button_index == MOUSE_BUTTON_LEFT and ev.ctrl_pressed:
					p.action_skill[0] = bname
				elif ev.button_index == MOUSE_BUTTON_RIGHT:
					p.action_skill[1] = bname)

	for s in _amazon_skills_on_page(tab + 1):
		var rect := _socket(s.col, s.row)
		var lvl: int = gs.skill_level(s.name)
		if icon_sheet != null:
			var tint := Color(1, 1, 1)
			if lvl <= 0:
				tint = Color(0.7, 0.7, 0.75) if gs.can_allocate(s.name) else Color(0.35, 0.35, 0.4)
			_icon(icon_sheet, int(s.icon), rect, tint)
		if lvl > 0:
			# D2 prints the level in the small notch the lattice frame leaves
			# at the socket's bottom-right corner, half outside the icon
			_text(Rect2(rect.position + Vector2(44, 46), Vector2(14, 14)), str(lvl),
					Color(1, 1, 0.6), 11)
		_hotkey_badge(str(s.name), rect)
		var btn := _button(rect)
		btn.mouse_entered.connect(_on_hover.bind(s, rect))
		btn.mouse_exited.connect(_hide_tip)
		btn.gui_input.connect(_on_icon_input.bind(s))


func _hotkey_badge(skill: String, rect: Rect2) -> void:
	for hk in gs.hotkeys:
		if str(gs.hotkeys[hk]) == skill:
			_text(Rect2(rect.position + Vector2(1, 1), Vector2(20, 15)), str(hk),
					Color(0.5, 1.0, 0.5), 11)


func _show_tip(s: String, rect: Rect2) -> void:
	tooltip.text = s
	tooltip.visible = true
	# to the left of the page, level with the socket
	tooltip.position = panel.to_screen(rect.position) - Vector2(tooltip.size.x + 12, 0)


func _hide_tip() -> void:
	tooltip.visible = false
	_hover_skill = ""


func _on_hover(s: Dictionary, rect: Rect2) -> void:
	_hover_skill = str(s.name)
	var r: Dictionary = s.def
	var lines := [s.name,
		"Level %d" % gs.skill_level(s.name),
		"Mana: %.1f" % (float(str(r.get("mana", "0")).to_int()) / 8.0),
		"Required level: %s" % r.get("reqlevel", "1")]
	for k in ["reqskill1", "reqskill2", "reqskill3"]:
		var req := str(r.get(k, "")).strip_edges()
		if req != "":
			lines.append("Requires: " + req)
	lines.append("click: +1   ctrl+click: LMB   right-click: RMB")
	lines.append("F1-F5: bind hotkey")
	_show_tip("\n".join(lines), rect)


func _on_icon_input(e: InputEvent, s: Dictionary) -> void:
	if not (e is InputEventMouseButton and e.pressed):
		return
	var p: Player = get_tree().get_first_node_in_group("player")
	if e.button_index == MOUSE_BUTTON_LEFT and e.ctrl_pressed:
		if gs.skill_level(s.name) > 0 and p != null:
			p.action_skill[0] = s.name
	elif e.button_index == MOUSE_BUTTON_LEFT:
		gs.allocate(s.name)
	elif e.button_index == MOUSE_BUTTON_RIGHT:
		if gs.skill_level(s.name) > 0 and p != null:
			p.action_skill[1] = s.name
	_rebuild()


func _input(e: InputEvent) -> void:
	if not open:
		return
	if e is InputEventKey and e.pressed:
		if e.keycode == KEY_1: tab = 0; _rebuild(); get_viewport().set_input_as_handled()
		elif e.keycode == KEY_2: tab = 1; _rebuild(); get_viewport().set_input_as_handled()
		elif e.keycode == KEY_3: tab = 2; _rebuild(); get_viewport().set_input_as_handled()
		elif e.keycode >= KEY_F1 and e.keycode <= KEY_F5:
			# D2-style: bind the hovered, learned skill to this key
			if _hover_skill != "" and (_hover_skill in ["Attack", "Throw"]
					or gs.skill_level(_hover_skill) > 0):
				gs.hotkeys["F%d" % (e.keycode - KEY_F1 + 1)] = _hover_skill
				get_node("/root/Sfx").event_ui("button")
				_rebuild()
