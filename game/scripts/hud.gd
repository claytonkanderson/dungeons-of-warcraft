class_name HUD
extends CanvasLayer
## D2 UI: original 800-mode control panel with health/mana orb fills,
## assigned-skill icons, viewmodel, crosshair, Alt item labels.

const PANEL_W := 704.0        # composited strip size
const PANEL_H := 104.0
# calibrated positions within the strip (see shots/ui_calibrate.png)
var ORB_L := Vector2(33.0, 8.0)       # health orb top-left (80x80 fill)
var ORB_R := Vector2(591.0, 8.0)      # mana orb top-left
# gold-border-measured boxes in the composited 704x104 strip
var SKILL_L := Vector2(158.0, 62.0)   # assigned skill icon boxes (30x38)
var SKILL_R := Vector2(515.0, 62.0)
const SKILL_SIZE := Vector2(30.0, 38.0)
const BELT_X := 374.5                 # four 29x30 sockets, 31px pitch
const BELT_Y := 65.0
const BELT_PITCH := 31.0
const BELT_SIZE := Vector2(28.0, 30.0)
# experience bar: its own strip along the very bottom of the screen, with
# the D2 panel riding directly on top of it. Purple, like WoW's.
const XP_H := 6.0                     # panel units; scales with the panel
const XP_TRACK := Color(0.04, 0.02, 0.05, 0.95)
const XP_FILL := Color(0.50, 0.0, 0.48)
const XP_GLINT := Color(0.72, 0.25, 0.70)

var bow: TextureRect
var info: Label
var panel_ui: Control
var _bob := 0.0
var _kick := 0.0
var _tex := {}

@onready var gs := get_node("/root/GameState")


func _tex_load(rel: String) -> Texture2D:
	if _tex.has(rel):
		return _tex[rel]
	var img := Image.load_from_file(Paths.asset(rel))
	var t: Texture2D = ImageTexture.create_from_image(img) if img != null else null
	_tex[rel] = t
	return t


func _icon_tex(icon_frame: int, sheet_name := "ui/amskillicon") -> AtlasTexture:
	var sheet = get_node("/root/SpriteDB").load_sheet(sheet_name)
	if sheet == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = sheet.texture
	at.region = Rect2(icon_frame * sheet.cell.x, 0, sheet.cell.x, sheet.cell.y)
	return at


class PanelControl:
	extends Control
	var hud: HUD

	func _draw() -> void:
		var gs = hud.gs
		var s: float = size.x / HUD.PANEL_W
		var panel: Texture2D = hud._tex_load("ui/ctrlpanel.png")
		var orb_h: Texture2D = hud._tex_load("ui/orb_0.png")
		var orb_m: Texture2D = hud._tex_load("ui/orb_1.png")
		# panel first; the orb spheres draw over their basins like D2 does
		if panel != null:
			draw_texture_rect(panel, Rect2(Vector2.ZERO, size), false)
		var hfrac: float = clampf(gs.hp / maxf(1.0, gs.hp_max), 0.0, 1.0)
		var mfrac: float = clampf(gs.mana / maxf(1.0, gs.mana_max), 0.0, 1.0)
		# the life orb sickens green while poisoned, like D2
		var htint := Color(0.35, 1.0, 0.35) if gs.is_poisoned() else Color(1, 1, 1)
		_orb(orb_h, hud.ORB_L, hfrac, s, htint)
		_orb(orb_m, hud.ORB_R, mfrac, s)
		# belt potions in the four panel sockets (keys 1-4)
		var db = hud.get_node("/root/ItemDB")
		for bi in range(4):
			var slot: Dictionary = gs.belt[bi] if bi < gs.belt.size() else {}
			if slot.is_empty() or int(slot.get("count", 0)) <= 0:
				continue
			var ptex: Texture2D = db.inv_texture(str(slot.get("code", "")))
			if ptex == null:
				continue
			var bpos := Vector2(HUD.BELT_X + bi * HUD.BELT_PITCH, HUD.BELT_Y) * s
			draw_texture_rect(ptex, Rect2(bpos, HUD.BELT_SIZE * s), false)
			var cnt := str(slot.get("count", 1))
			var font := ThemeDB.fallback_font
			draw_string(font, bpos + Vector2(18, 12) * s, cnt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(1, int(10 * s)), Color(1, 1, 1))
		# experience bar inlaid in the panel itself: progress to next level
		var lvl_i: int = gs.level
		var xfrac := 1.0
		if lvl_i < gs.exp_table.size():
			var e0 := float(str(gs.exp_table[lvl_i - 1]).to_int())
			var e1 := float(str(gs.exp_table[lvl_i]).to_int())
			xfrac = clampf((float(gs.xp) - e0) / maxf(1.0, e1 - e0), 0.0, 1.0)
		# drawn past the bottom of the panel rect, in the strip the
		# layout reserves for it
		var xh := HUD.XP_H * s
		draw_rect(Rect2(0.0, size.y, size.x, xh), HUD.XP_TRACK)
		var xw := (size.x - 2.0 * s) * xfrac
		if xw > 0.0:
			var o := Vector2(s, size.y + s)
			draw_rect(Rect2(o, Vector2(xw, xh - 2.0 * s)), HUD.XP_FILL)
			draw_rect(Rect2(o, Vector2(xw, s)), HUD.XP_GLINT)

		# assigned skill icons: always visible — normal Attack shows the
		# classic swing glyph from the generic skill icon panel
		for i in range(2):
			var p: Player = hud.get_tree().get_first_node_in_group("player")
			if p == null:
				break
			var skill: String = p.action_skill[i]
			var at: AtlasTexture = null
			if skill == "Attack":
				at = hud._icon_tex(2, "ui/skilliconpanel")
			else:
				var sd: Dictionary = hud.get_node("/root/SpriteDB").gamedata() \
						.get("skilldesc", {}).get(skill.to_lower(), {})
				var icon := int(str(sd.get("icon", "-1")).to_int()) \
						if not sd.is_empty() else -1
				if icon >= 0:
					at = hud._icon_tex(icon)
				if at == null:
					at = hud._icon_tex(2, "ui/skilliconpanel")
			var pos: Vector2 = (hud.SKILL_L if i == 0 else hud.SKILL_R) * s
			if at != null:
				draw_texture_rect(at, Rect2(pos, HUD.SKILL_SIZE * s), false)

	func _orb(tex: Texture2D, tl: Vector2, frac: float, s: float,
			tint := Color(1, 1, 1)) -> void:
		if tex == null or frac <= 0.0:
			return
		var oh := tex.get_height()
		var cut := oh * (1.0 - frac)
		draw_texture_rect_region(tex,
			Rect2((tl + Vector2(0, cut)) * s, Vector2(tex.get_width(), oh - cut) * s),
			Rect2(0, cut, tex.get_width(), oh - cut), tint)


func _ready() -> void:
	var cross := Label.new()
	cross.text = "+"
	cross.add_theme_font_size_override("font_size", 22)
	cross.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	cross.set_anchors_preset(Control.PRESET_CENTER)
	add_child(cross)

	bow = TextureRect.new()
	bow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bow.scale = Vector2(4, 4)
	bow.rotation = -0.5
	add_child(bow)

	panel_ui = PanelControl.new()
	panel_ui.hud = self
	add_child(panel_ui)

	info = Label.new()
	info.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	info.add_theme_font_size_override("font_size", 16)
	add_child(info)

	gs.equipment_changed.connect(_update_viewmodel)
	_update_viewmodel()


func _update_viewmodel() -> void:
	## The FPS weapon sprite mirrors the equipped main-hand weapon.
	## (Only the texture: the panel and info label are built once in _ready —
	## rebuilding them here stacked duplicates on every equipment change.)
	var tex: Texture2D = null
	var w: Dictionary = gs.equipped.get("weap", {})
	if not w.is_empty():
		tex = get_node("/root/ItemDB").inv_texture(str(w.get("code", "")))
	if tex == null:
		tex = _tex_load("ui/viewmodel_bow.png")
	bow.texture = tex


func kick() -> void:
	_kick = 1.0


var _area_label: Label
var _area_t := 0.0
var _item_labels := []


func show_area(name: String, color := Color(0.9, 0.82, 0.6), dur := 3.0) -> void:
	if _area_label == null:
		_area_label = Label.new()
		_area_label.add_theme_font_size_override("font_size", 42)
		_area_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_area_label.add_theme_constant_override("outline_size", 8)
		add_child(_area_label)
	_area_label.add_theme_color_override("font_color", color)
	_area_label.text = name
	_area_label.visible = true
	_area_t = dur


var _tgt_root: Control
var _tgt_name: Label
var _tgt_bg: ColorRect
var _tgt_fill: ColorRect


func show_target(mob) -> void:
	## D2-style plate at the top: creature name over a health bar.
	if _tgt_root == null:
		_tgt_root = Control.new()
		add_child(_tgt_root)
		_tgt_name = Label.new()
		get_node("/root/D2Font").style(_tgt_name, 16)
		_tgt_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tgt_name.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_tgt_name.add_theme_constant_override("outline_size", 5)
		_tgt_root.add_child(_tgt_name)
		_tgt_bg = ColorRect.new()
		_tgt_bg.color = Color(0.0, 0.0, 0.0, 0.75)
		_tgt_root.add_child(_tgt_bg)
		_tgt_fill = ColorRect.new()
		_tgt_fill.color = Color(0.55, 0.05, 0.05)
		_tgt_root.add_child(_tgt_fill)
	var vp := get_viewport().get_visible_rect().size
	var w := 280.0
	_tgt_root.visible = true
	_tgt_name.text = str(mob.cname)
	_tgt_name.add_theme_color_override("font_color",
			Color(0.95, 0.75, 0.25) if mob.is_boss else Color(0.92, 0.9, 0.85))
	_tgt_name.position = Vector2(vp.x * 0.5 - w * 0.5, 14)
	_tgt_name.size = Vector2(w, 22)
	_tgt_bg.position = Vector2(vp.x * 0.5 - w * 0.5, 40)
	_tgt_bg.size = Vector2(w, 14)
	var frac: float = clampf(mob.hp / maxf(1.0, mob.hp_max), 0.0, 1.0)
	_tgt_fill.position = _tgt_bg.position + Vector2(1, 1)
	_tgt_fill.size = Vector2((w - 2) * frac, 12)


func hide_target() -> void:
	if _tgt_root != null:
		_tgt_root.visible = false


func show_item_labels(items: Array, cam: Camera3D) -> void:
	while _item_labels.size() < items.size():
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		l.add_theme_constant_override("outline_size", 5)
		add_child(l)
		_item_labels.append(l)
	for i in range(_item_labels.size()):
		var l: Label = _item_labels[i]
		if i >= items.size():
			l.visible = false
			continue
		var gi: GroundItem = items[i]
		var wpos: Vector3 = gi.global_position + Vector3(0, gi.label_height(), 0)
		if cam.is_position_behind(wpos):
			l.visible = false
			continue
		l.visible = true
		l.text = gi.display_name
		l.add_theme_color_override("font_color", gi.name_color)
		var sp := cam.unproject_position(wpos)
		l.position = sp - Vector2(l.size.x * 0.5, l.size.y)


func hide_item_labels() -> void:
	for l in _item_labels:
		l.visible = false


func _process(dt: float) -> void:
	var vp := get_viewport().get_visible_rect().size
	if _area_label != null and _area_label.visible:
		_area_t -= dt
		_area_label.position = Vector2(vp.x * 0.5 - _area_label.size.x * 0.5, vp.y * 0.22)
		_area_label.modulate.a = clampf(_area_t, 0.0, 1.0)
		if _area_t <= 0.0:
			_area_label.visible = false
	_kick = maxf(0.0, _kick - dt * 5.0)
	if bow != null:
		_bob += dt * 2.0
		var pp: Player = get_tree().get_first_node_in_group("player")
		var sw := -1.0
		if pp != null and pp.melee and pp.attack_time > 0.0 \
				and pp._attack_len > 0.0:
			sw = 1.0 - pp.attack_time / pp._attack_len
		if sw >= 0.0:
			# first-person melee: wind up high right, sweep across the view
			var e := sw * sw * (3.0 - 2.0 * sw)
			bow.rotation = lerpf(0.8, -2.1, e)
			bow.position = Vector2(vp.x * (0.74 - 0.42 * e),
					vp.y - 250.0 - sin(e * PI) * 90.0)
		else:
			bow.rotation = -0.5
			bow.position = Vector2(vp.x * 0.62 + sin(_bob) * 6.0,
					vp.y - 260.0 + cos(_bob * 2.0) * 4.0 + _kick * 40.0)
	# control panel: full width, riding on top of the xp strip
	var s := vp.x / PANEL_W
	panel_ui.size = Vector2(vp.x, PANEL_H * s)
	panel_ui.position = Vector2(0, vp.y - panel_ui.size.y - XP_H * s)
	panel_ui.queue_redraw()
	info.position = Vector2(30, 24)
	info.text = "lvl %d   xp %d   skill pts %d   gold %d" % [
		gs.level, gs.xp, gs.skill_points, gs.gold]
