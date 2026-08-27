class_name CharSheet
extends CanvasLayer
## Character stats on the original invchar_0 page art. Toggle with C.

const SCALE := 1.5

var open := false
var root: Control
var panel: TextureRect

@onready var gs := get_node("/root/GameState")


func _ready() -> void:
	layer = 5
	root = Control.new()
	root.visible = false
	add_child(root)
	panel = TextureRect.new()
	var img := Image.load_from_file(Paths.asset("ui/invchar_0.png"))
	if img != null:
		panel.texture = ImageTexture.create_from_image(img)
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	root.add_child(panel)
	gs.hp_changed.connect(_refresh)
	gs.equipment_changed.connect(_refresh)


func toggle() -> void:
	# mouse/look state is owned by the world's _sync_ui()
	open = not open
	root.visible = open
	if open:
		_layout()
		_refresh()


func _layout() -> void:
	var vp := root.get_viewport_rect().size
	panel.size = Vector2(320, 432) * SCALE
	panel.position = Vector2(24, (vp.y - panel.size.y) * 0.5)


var _labels := []


func _put(text: String, x: float, y: float, color := Color(0.9, 0.85, 0.7),
		w := 0.0, px := 16) -> void:
	var l := Label.new()
	l.text = text
	get_node("/root/D2Font").style(l, px)
	l.add_theme_color_override("font_color", color)
	l.position = Vector2(x, y) * SCALE
	if w > 0.0:
		l.size = Vector2(w * SCALE, 17 * SCALE)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(l)
	_labels.append(l)


func _refresh() -> void:
	if not open:
		return
	for l in _labels:
		l.queue_free()
	_labels.clear()
	var wd: Vector2 = gs.weapon_damage() / GameState.DMG_MULT
	_put("Amazon", 14, 11)
	_put("Level %d" % gs.level, 112, 11)
	_put("Exp: %d" % gs.xp, 196, 11)
	# left column: label box x 10..74, value box x 78..118
	var rows := [["Strength", "str", 85.0], ["Dexterity", "dex", 147.0],
			["Vitality", "vit", 233.0], ["Energy", "ene", 295.0]]
	for r in rows:
		_put(str(r[0]), 12, float(r[2]))
		_put(str(gs.total_stat(str(r[1]))), 78, float(r[2]), Color(1, 1, 1), 40.0)
	# right column: label box x 160..258, value box x 262..306
	_put("Attack Rating", 164, 85)
	_put(str(int(gs.attack_rating())), 262, 85, Color(1, 1, 1), 44.0)
	_put("Defense", 164, 109)
	_put(str(int(gs.player_defense())), 262, 109, Color(1, 1, 1), 44.0)
	_put("Stamina", 164, 147)
	var p: Player = get_tree().get_first_node_in_group("player")
	_put(str(int(p.stamina)) if p != null else "-", 262, 147, Color(1, 1, 1), 44.0)
	_put("Life", 164, 171)
	_put("%d/%d" % [int(gs.hp), int(gs.hp_max)], 258, 172, Color(1, 1, 1), 50.0, 13)
	_put("Mana", 164, 195)
	_put("%d/%d" % [int(gs.mana), int(gs.mana_max)], 258, 196, Color(1, 1, 1), 50.0, 13)
	# damage in the spare box row below the vitality band
	_put("Damage", 164, 257)
	_put("%d-%d" % [int(wd.x), int(wd.y)], 258, 258, Color(1, 1, 1), 50.0, 13)
	var resists := [["Fire Resistance", "res-fire", 334.0, Color(1, 0.35, 0.25)],
			["Cold Resistance", "res-cold", 358.0, Color(0.4, 0.55, 1)],
			["Lightning Resist", "res-ltng", 382.0, Color(1, 1, 0.4)],
			["Poison Resistance", "res-pois", 406.0, Color(0.3, 1, 0.3)]]
	for r in resists:
		_put(str(r[0]), 164, float(r[2]), r[3])
		var v: int = int(gs.mods.get(str(r[1]), 0)) + int(gs.mods.get("res-all", 0))
		_put("%d%%" % v, 268, float(r[2]), Color(1, 1, 1), 40.0)
	# stat point allocation: remaining count in the small bottom box,
	# a scaled + button beside each stat value box
	if gs.stat_points > 0:
		_put("Stat Points", 30, 390, Color(1, 0.3, 0.3))
		_put(str(gs.stat_points), 127, 390, Color(1, 1, 1), 26.0)
		for r in rows:
			var pb := Button.new()
			pb.text = "+"
			pb.add_theme_font_size_override("font_size", 20)
			pb.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
			pb.position = Vector2(122.0, float(r[2]) - 2.0) * SCALE
			pb.size = Vector2(20, 20) * SCALE
			var key := str(r[1])
			pb.pressed.connect(func():
				gs.allocate_stat(key)
				_refresh())
			panel.add_child(pb)
			_labels.append(pb)