class_name CharSheet
extends CanvasLayer
## Character stats on the original invchar_0 page art. Toggle with C.
##
## Built on D2Panel: every value is a D2Field sized to the box measured off
## the page art, so it sits inside its box and shrinks rather than spill —
## "50/78" used to run through the divider at 1.5x. Row layout is D2's:
## name / class, then level / experience / next level, the four attributes
## down the left, combat stats and resistances down the right.

const GOLD := Color(0.9, 0.85, 0.7)
const WHITE := Color(1, 1, 1)
# boxes measured on invchar_0.png (x, y, w, h in page pixels). The right-hand
# rows are a label box and a 40 px value box at x=271 beside it.
const NAME_BOX := Rect2(11, 10, 171, 17)
const CLASS_BOX := Rect2(193, 10, 117, 17)
const LEVEL_BOX := Rect2(10, 32, 44, 35)
const EXP_BOX := Rect2(66, 32, 116, 35)
const NEXT_BOX := Rect2(192, 32, 118, 35)
const STAT_ROWS := [["Strength", "str", 83.0], ["Dexterity", "dex", 145.0],
		["Vitality", "vit", 231.0], ["Energy", "ene", 293.0]]
const STAT_LABEL_X := 10.0
const STAT_LABEL_W := 65.0
const STAT_VALUE_X := 76.0
const STAT_VALUE_W := 39.0
const ROW_H := 18.0
const RIGHT_LABEL_X := 161.0
const RIGHT_VALUE := Rect2(271, 0, 40, 17)     # y set per row
const RES_LABEL_X := 174.0
const STATPTS_LABEL := Rect2(20, 390, 100, 17)
const STATPTS_BOX := Rect2(128, 389, 32, 32)

var open := false
var panel: D2Panel
var _nodes := []

@onready var gs := get_node("/root/GameState")


func _ready() -> void:
	layer = 5
	panel = D2Panel.new("ui/invchar_0.png")
	panel.visible = false
	add_child(panel)
	gs.hp_changed.connect(_refresh)
	gs.equipment_changed.connect(_refresh)


func toggle() -> void:
	# mouse/look state is owned by the world's _sync_ui()
	open = not open
	panel.visible = open
	if open:
		panel.fit(get_viewport().get_visible_rect().size, false)
		_refresh()


# D2 draws this page's text with its small font. Our exported font16 scaled to
# 11 px in page space is the same pixel density the old 1.5x layout had (16
# screen px over a 1.5x page) and is what fits the measured boxes.
const TEXT_PX := 11


func _field(rect: Rect2, text: String, color := WHITE, px := TEXT_PX,
		align := HORIZONTAL_ALIGNMENT_CENTER, fit := true) -> D2Field:
	var f := D2Field.new(rect, px, color, align, fit)
	panel.content.add_child(f)
	f.set_value(text)
	_nodes.append(f)
	return f


func _label(rect: Rect2, text: String, color := GOLD) -> D2Field:
	## a caption: full size, centred in its box like D2's, never clipped
	return _field(rect, text, color, TEXT_PX, HORIZONTAL_ALIGNMENT_CENTER, false)


func _right_row(label: String, y: float, value: String, label_w: float,
		color := GOLD) -> void:
	_label(Rect2(RIGHT_LABEL_X, y, label_w, 17), label, color)
	_field(Rect2(RIGHT_VALUE.position.x, y, RIGHT_VALUE.size.x, 17), value)


func _refresh() -> void:
	if not open:
		return
	for n in _nodes:
		n.queue_free()
	_nodes.clear()
	var wd: Vector2 = gs.weapon_damage() / GameState.DMG_MULT
	_field(NAME_BOX, str(gs.char_name), GOLD)
	_field(CLASS_BOX, "Amazon", GOLD)
	_field(LEVEL_BOX, str(gs.level))
	_field(EXP_BOX, str(gs.xp))
	var nxt := "-"
	if gs.level < gs.exp_table.size():
		nxt = str(gs.exp_table[gs.level])
	_field(NEXT_BOX, nxt)
	for r in STAT_ROWS:
		var y: float = r[2]
		_label(Rect2(STAT_LABEL_X, y, STAT_LABEL_W, ROW_H), str(r[0]))
		_field(Rect2(STAT_VALUE_X, y, STAT_VALUE_W, ROW_H),
				str(gs.total_stat(str(r[1]))))
	_right_row("Attack Rating", 83, str(int(gs.attack_rating())), 98)
	_right_row("Defense", 107, str(int(gs.player_defense())), 98)
	var p: Player = get_tree().get_first_node_in_group("player")
	_right_row("Stamina", 145, str(int(p.stamina)) if p != null else "-", 109)
	_right_row("Life", 169, "%d/%d" % [int(gs.hp), int(gs.hp_max)], 109)
	_right_row("Mana", 193, "%d/%d" % [int(gs.mana), int(gs.mana_max)], 109)
	_right_row("Damage", 255, "%d-%d" % [int(wd.x), int(wd.y)], 69)
	var resists := [["Fire Resistance", "res-fire", 332.0, Color(1, 0.35, 0.25)],
			["Cold Resistance", "res-cold", 356.0, Color(0.4, 0.55, 1)],
			["Lightning Resist", "res-ltng", 380.0, Color(1, 1, 0.4)],
			["Poison Resistance", "res-pois", 404.0, Color(0.3, 1, 0.3)]]
	for r in resists:
		var y: float = r[2]
		_label(Rect2(RES_LABEL_X, y, 96, 17), str(r[0]), r[3])
		var v: int = int(gs.mods.get(str(r[1]), 0)) + int(gs.mods.get("res-all", 0))
		_field(Rect2(RIGHT_VALUE.position.x, y, RIGHT_VALUE.size.x, 17), "%d%%" % v)
	# stat point allocation: remaining count in the small bottom box, a +
	# button beside each attribute's value box
	if gs.stat_points > 0:
		_label(STATPTS_LABEL, "Stat Points", Color(1, 0.3, 0.3))
		_field(STATPTS_BOX, str(gs.stat_points))
		for r in STAT_ROWS:
			var pb := Button.new()
			pb.text = "+"
			pb.flat = true
			pb.add_theme_font_size_override("font_size", 14)
			pb.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
			pb.position = Vector2(STAT_VALUE_X + STAT_VALUE_W + 3.0, float(r[2]) - 1.0)
			pb.size = Vector2(20, 20)
			pb.focus_mode = Control.FOCUS_NONE
			var key := str(r[1])
			pb.pressed.connect(func():
				gs.allocate_stat(key)
				_refresh())
			panel.content.add_child(pb)
			_nodes.append(pb)
