class_name SkillTreeUI
extends CanvasLayer
## The Amazon talent tree on the original skltree_a_back art.
## T toggles. Click = spend a point. Ctrl+click = assign to LMB.
## Right-click = assign to RMB. Keys 1/2/3 switch tabs.

const SCALE := 1.5
const PAGE := Vector2(320, 432)
# icon slot grid within a page (calibrated against the arrow lattice)
var GRID_ORIGIN := Vector2(12.0, 22.0)
var GRID_STEP := Vector2(69.0, 68.0)
const TAB_NAMES := ["Bow and Crossbow", "Passive and Magic", "Javelin and Spear"]

var open := false
var tab := 0
var root: Control
var tooltip: Label
var _tex := {}

@onready var gs := get_node("/root/GameState")
@onready var db := get_node("/root/SpriteDB")


func _ready() -> void:
	layer = 6
	root = Control.new()
	root.visible = false
	add_child(root)
	tooltip = Label.new()
	tooltip.add_theme_font_size_override("font_size", 15)
	tooltip.add_theme_color_override("font_color", Color(1, 1, 1))
	tooltip.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	tooltip.add_theme_constant_override("outline_size", 5)
	add_child(tooltip)
	tooltip.visible = false
	gs.skills_changed.connect(_rebuild)


func _tex_load(rel: String) -> Texture2D:
	if _tex.has(rel):
		return _tex[rel]
	var img := Image.load_from_file(ProjectSettings.globalize_path(
		"res://../assets/" + rel))
	var t: Texture2D = ImageTexture.create_from_image(img) if img != null else null
	_tex[rel] = t
	return t


func toggle() -> void:
	# mouse/look state is owned by the world's _sync_ui()
	open = not open
	root.visible = open
	if open:
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


func _rebuild() -> void:
	if not open:
		return
	for c in root.get_children():
		c.queue_free()
	var vp := get_viewport().get_visible_rect().size
	var psize := PAGE * SCALE
	root.position = Vector2(vp.x - psize.x - 20, (vp.y - psize.y) * 0.5)
	root.size = psize

	# lattice background for this tab, then the chrome overlay page
	var lattice := _tex_load("ui/skltree_%d.png" % (tab + 1))
	var chrome := _tex_load("ui/skltree_0.png")
	for t in [lattice, chrome]:
		if t == null:
			continue
		var tr := TextureRect.new()
		tr.texture = t
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.size = psize
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tr)

	# tab plates in the chrome column (border-measured: 87x99 at x 228,
	# y 111/219/327): signature skill icon + short name, active tab lit
	var icon_sheet_tabs = db.load_sheet("ui/amskillicon")
	var tab_short := ["Bow", "Passive", "Javelin"]
	for i in range(3):
		var plate := Vector2(228.0, 111.0 + i * 108.0) * SCALE
		var psize2 := Vector2(87.0, 99.0) * SCALE
		var active := i == tab
		var sig := _amazon_skills_on_page(i + 1)
		sig.sort_custom(func(a, b): return a.row * 10 + a.col < b.row * 10 + b.col)
		if icon_sheet_tabs != null and not sig.is_empty():
			var at0 := AtlasTexture.new()
			at0.atlas = icon_sheet_tabs.texture
			at0.region = Rect2(int(sig[0].icon) * icon_sheet_tabs.cell.x, 0,
					icon_sheet_tabs.cell.x, icon_sheet_tabs.cell.y)
			var ti := TextureRect.new()
			ti.texture = at0
			ti.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			ti.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ti.size = Vector2(48, 48) * SCALE
			ti.position = plate + Vector2((psize2.x - ti.size.x) * 0.5, 8 * SCALE)
			ti.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ti.modulate = Color(1, 1, 1) if active else Color(0.45, 0.45, 0.5)
			root.add_child(ti)
		var tl := Label.new()
		tl.text = tab_short[i]
		get_node("/root/D2Font").style(tl, 16)
		tl.add_theme_color_override("font_color",
				Color(1.0, 0.9, 0.5) if active else Color(0.55, 0.55, 0.55))
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.position = plate + Vector2(0, 62 * SCALE)
		tl.size = Vector2(psize2.x, 20 * SCALE)
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tl)
		var tb := Button.new()
		tb.flat = true
		tb.position = plate
		tb.size = psize2
		tb.pressed.connect(func():
			tab = i
			_rebuild())
		root.add_child(tb)

	var title := Label.new()
	title.text = TAB_NAMES[tab] + "   (points: %d)" % gs.skill_points
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.9, 0.82, 0.6))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 4)
	title.position = Vector2(14, -26)
	root.add_child(title)

	var icon_sheet = db.load_sheet("ui/amskillicon")
	for s in _amazon_skills_on_page(tab + 1):
		var pos: Vector2 = (GRID_ORIGIN + Vector2(s.col - 1, s.row - 1) * GRID_STEP) * SCALE
		var lvl: int = gs.skill_level(s.name)
		var btn := Button.new()
		btn.flat = true
		btn.position = pos
		btn.size = Vector2(48, 48) * SCALE
		btn.mouse_entered.connect(_on_hover.bind(s, btn))
		btn.mouse_exited.connect(func(): tooltip.visible = false)
		btn.gui_input.connect(_on_icon_input.bind(s))
		root.add_child(btn)
		if icon_sheet != null:
			var at := AtlasTexture.new()
			at.atlas = icon_sheet.texture
			at.region = Rect2(s.icon * icon_sheet.cell.x, 0,
					icon_sheet.cell.x, icon_sheet.cell.y)
			var tr2 := TextureRect.new()
			tr2.texture = at
			tr2.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tr2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr2.position = pos
			tr2.size = Vector2(48, 48) * SCALE
			tr2.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if lvl <= 0:
				tr2.modulate = Color(0.35, 0.35, 0.4) if not gs.can_allocate(s.name) \
						else Color(0.7, 0.7, 0.75)
			root.add_child(tr2)
		if lvl > 0:
			var ll := Label.new()
			ll.text = str(lvl)
			ll.add_theme_font_size_override("font_size", 15)
			ll.add_theme_color_override("font_color", Color(1, 1, 0.6))
			ll.add_theme_color_override("font_outline_color", Color(0, 0, 0))
			ll.add_theme_constant_override("outline_size", 4)
			ll.position = pos + Vector2(48, 48) * SCALE - Vector2(16, 22)
			root.add_child(ll)


func _on_hover(s: Dictionary, btn: Button) -> void:
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
	tooltip.text = "\n".join(lines)
	tooltip.visible = true
	tooltip.position = root.position + btn.position + Vector2(-160, 0)


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
		if e.keycode == KEY_1: tab = 0; _rebuild()
		elif e.keycode == KEY_2: tab = 1; _rebuild()
		elif e.keycode == KEY_3: tab = 2; _rebuild()
