class_name ShopUI
extends CanvasLayer
## The Outpost: where gold goes. Opened at the brazier by the dungeon's
## entrance (outpost.gd). Three things are sold:
##   gambling  - Diablo II's: a base item at a price, unseen until bought,
##               always at least magic, with a chance of rare, set, unique
##   respec    - the skill points back, or the stat points back
##   the stash - pages of storage that stay with the character; the
##               inventory opens beside this panel so items can be moved
## Everything here is this player's own (gold, inventory, stash), so in
## co-op it needs nothing from the host.

const GOLD := Color(0.95, 0.85, 0.4)
const DIM := Color(0.6, 0.55, 0.45)
const WHITE := Color(0.9, 0.88, 0.82)
const EDGE := Color(0.45, 0.35, 0.15)
const PANEL := Rect2(40, 60, 620, 600)
const OFFERS := 8
const STASH_COLS := 10
const STASH_ROWS := 4
const STASH_CELL := 26.0
const MAX_PAGES := 4

var open := false
var world = null
var root: Control
var _gold_lbl: Label
var _offer_box: VBoxContainer
var _stash_grid: Control
var _stash_tabs: HBoxContainer
var _respec_box: VBoxContainer
var _status: Label
var _offers: Array = []           # [{code, price}] this visit's gamble
var _page := 0
var _stash_nodes: Array = []
var tooltip_card: ItemTooltip

@onready var gs := get_node("/root/GameState")
@onready var db := get_node("/root/ItemDB")
@onready var gen := get_node("/root/ItemGen")


func _ready() -> void:
	layer = 7
	root = Control.new()
	root.visible = false
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.02, 0.02, 0.94)
	sb.border_color = EDGE
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	panel.position = PANEL.position
	panel.size = PANEL.size
	root.add_child(panel)
	var title := _label("THE  OUTPOST", 24, WHITE)
	title.position = Vector2(0, 10)
	title.size = Vector2(PANEL.size.x, 30)
	panel.add_child(title)
	_gold_lbl = _label("", 16, GOLD)
	_gold_lbl.position = Vector2(0, 42)
	_gold_lbl.size = Vector2(PANEL.size.x, 22)
	panel.add_child(_gold_lbl)

	# gambling, left
	var gh := _label("GAMBLE", 16, WHITE)
	gh.position = Vector2(20, 76)
	gh.size = Vector2(300, 20)
	gh.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	panel.add_child(gh)
	var gsub := _label("unseen until bought; magic at least, sometimes far more", 11, DIM)
	gsub.position = Vector2(20, 96)
	gsub.size = Vector2(320, 16)
	gsub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	panel.add_child(gsub)
	_offer_box = VBoxContainer.new()
	_offer_box.position = Vector2(20, 116)
	_offer_box.size = Vector2(320, 380)
	_offer_box.add_theme_constant_override("separation", 4)
	panel.add_child(_offer_box)

	# respec, right top
	var rh := _label("RESPEC", 16, WHITE)
	rh.position = Vector2(360, 76)
	rh.size = Vector2(240, 20)
	rh.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	panel.add_child(rh)
	_respec_box = VBoxContainer.new()
	_respec_box.position = Vector2(360, 100)
	_respec_box.size = Vector2(240, 90)
	_respec_box.add_theme_constant_override("separation", 6)
	panel.add_child(_respec_box)

	# the stash, right bottom
	var sh := _label("STASH", 16, WHITE)
	sh.position = Vector2(360, 200)
	sh.size = Vector2(240, 20)
	sh.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	panel.add_child(sh)
	var ssub := _label("click an item in your pack, then a cell here; click a stashed item to take it back", 11, DIM)
	ssub.position = Vector2(360, 220)
	ssub.size = Vector2(250, 32)
	ssub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ssub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	panel.add_child(ssub)
	_stash_tabs = HBoxContainer.new()
	_stash_tabs.position = Vector2(360, 258)
	_stash_tabs.size = Vector2(250, 26)
	_stash_tabs.add_theme_constant_override("separation", 4)
	panel.add_child(_stash_tabs)
	_stash_grid = Control.new()
	_stash_grid.position = Vector2(360, 292)
	_stash_grid.size = Vector2(STASH_COLS * STASH_CELL, STASH_ROWS * STASH_CELL)
	panel.add_child(_stash_grid)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.04)
	bg.size = _stash_grid.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stash_grid.add_child(bg)
	for x in range(STASH_COLS + 1):
		var l := ColorRect.new()
		l.color = EDGE
		l.position = Vector2(x * STASH_CELL, 0)
		l.size = Vector2(1, _stash_grid.size.y)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stash_grid.add_child(l)
	for y in range(STASH_ROWS + 1):
		var l := ColorRect.new()
		l.color = EDGE
		l.position = Vector2(0, y * STASH_CELL)
		l.size = Vector2(_stash_grid.size.x, 1)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stash_grid.add_child(l)
	_stash_grid.gui_input.connect(_on_stash_click)
	_status = _label("", 13, GOLD)
	_status.position = Vector2(20, PANEL.size.y - 60)
	_status.size = Vector2(PANEL.size.x - 40, 40)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_status)
	var close := _button("Close  (Esc)", func(): _close())
	close.position = Vector2(PANEL.size.x - 150, PANEL.size.y - 40)
	close.size = Vector2(130, 28)
	panel.add_child(close)
	tooltip_card = ItemTooltip.new()
	add_child(tooltip_card)
	gs.inventory_changed.connect(func():
		if open:
			_refresh_stash()
			_gold_lbl.text = "%d gold" % gs.gold)


func _label(text: String, px: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	get_node("/root/D2Font").style(l, px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		get_node("/root/Sfx").event_ui("button")
		cb.call())
	return b


func toggle() -> void:
	## mouse/look state is owned by the world's _sync_ui()
	open = not open
	root.visible = open
	if open:
		_new_offers()
		_status.text = ""
		refresh()
	elif tooltip_card != null:
		tooltip_card.hide_item()


func _close() -> void:
	if world != null:
		world._ui_action("ui:shop")


# ---------------------------------------------------------------- gambling

func gamble_bases() -> Array:
	## What can be gambled: every equippable base plus charms and jewels,
	## at a quality level the character could find
	var out := []
	for code in db.items:
		var it: Dictionary = db.item(code)
		var chain: Dictionary = gen.type_chain(str(it.get("type", "")))
		var slot := str(gs.slot_for(code))
		if slot == "" and not chain.has("char") and not chain.has("jewl"):
			continue
		if str(it.get("type", "")) in ["gold", "ques"] or code == "gold":
			continue
		# quest pieces carry no rarity (Wirt's leg, the Horadric malus);
		# another class's gear (druid pelts, barbarian helms) is no use
		if str(it.get("rarity", "")).to_int() <= 0:
			continue
		var other_class := false
		for t in ["orb", "head", "phlm", "pelt", "ashd", "h2h", "h2h2"]:
			if chain.has(t):
				other_class = true
		if other_class:
			continue
		var q := str(it.get("level", "1")).to_int()
		if q > gs.level + 5:
			continue
		out.append(code)
	return out


func price_of(code: String) -> int:
	## Diablo II's gamble prices, roughly: rings and amulets dear, charms
	## and jewels in between, gear by its quality level
	var it: Dictionary = db.item(code)
	var chain: Dictionary = gen.type_chain(str(it.get("type", "")))
	var q := str(it.get("level", "1")).to_int()
	if chain.has("ring"):
		return 2500 + gs.level * 60
	if chain.has("amul"):
		return 3500 + gs.level * 80
	if chain.has("char"):
		return 1200 + gs.level * 40
	if chain.has("jewl"):
		return 1800 + gs.level * 50
	return 250 + q * 45 + gs.level * 20


func _new_offers() -> void:
	var pool := gamble_bases()
	_offers = []
	var seen := {}
	var tries := 0
	while _offers.size() < OFFERS and tries < 200 and not pool.is_empty():
		tries += 1
		var code: String = pool[randi() % pool.size()]
		if seen.has(code):
			continue
		seen[code] = true
		_offers.append({"code": code, "price": price_of(code)})


func _gamble(offer: Dictionary) -> void:
	var price := int(offer["price"])
	if gs.gold < price:
		_status.text = "Not enough gold (%d needed)" % price
		return
	# Diablo II's gamble odds: magic at least, the rest well above a drop
	var inst: Dictionary = gen.roll_item(str(offer["code"]), gs.level + 4,
			{"unique": 600, "set": 600, "rare": 400, "magic": 0}, "magic")
	var name: String = str(inst.get("name", db.item(str(offer["code"])).get("name", "?")))
	gs.gold -= price
	if not gs.inv_try_add(str(offer["code"]), inst):
		# no room: at the feet, as the host's drop in co-op
		if world != null:
			var at: Vector3 = world.player.global_position + Vector3(0, 0.05, 0)
			if Net.is_client():
				Net.drop_item.rpc_id(1, str(offer["code"]), 0, inst, at)
			else:
				world.spawn_drop(str(offer["code"]), 0, inst, at)
		_status.text = "Your pack is full: %s lies at your feet" % name
	else:
		_status.text = "You got: %s" % name
	get_node("/root/Sfx").event_ui("gold_drop")
	gs.inventory_changed.emit()
	# the slot sells again with a fresh base
	var pool := gamble_bases()
	if not pool.is_empty():
		var code: String = pool[randi() % pool.size()]
		offer["code"] = code
		offer["price"] = price_of(code)
	refresh()


# ---------------------------------------------------------------- respec

func respec_price() -> int:
	return 500 * maxi(1, gs.level)


func _respec_skills() -> void:
	var p := respec_price()
	if gs.gold < p:
		_status.text = "Not enough gold (%d needed)" % p
		return
	var n: int = gs.respec_skills()
	gs.gold -= p
	_status.text = "%d skill points returned" % n
	gs.inventory_changed.emit()
	refresh()


func _respec_stats() -> void:
	var p := respec_price()
	if gs.gold < p:
		_status.text = "Not enough gold (%d needed)" % p
		return
	var n: int = gs.respec_stats()
	gs.gold -= p
	_status.text = "%d stat points returned" % n
	gs.inventory_changed.emit()
	refresh()


# ---------------------------------------------------------------- the stash

func page_price() -> int:
	return 5000 * gs.stash_pages


func _buy_page() -> void:
	if gs.stash_pages >= MAX_PAGES:
		return
	var p := page_price()
	if gs.gold < p:
		_status.text = "Not enough gold (%d needed)" % p
		return
	gs.gold -= p
	gs.stash_pages += 1
	_page = gs.stash_pages - 1
	_status.text = "Stash page %d bought" % gs.stash_pages
	gs.inventory_changed.emit()
	refresh()


func _on_stash_click(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	var inv = world.inv_ui if world != null else null
	if inv == null or inv.carried == null:
		return
	var local: Vector2 = _stash_grid.get_local_mouse_position()
	var gx := int(floor(local.x / STASH_CELL))
	var gy := int(floor(local.y / STASH_CELL))
	var entry = inv.carried
	if gs.stash_put(entry, _page, gx, gy):
		inv.carried = null
		inv._refresh()
		_status.text = ""
	else:
		_status.text = "It does not fit there"
	get_viewport().set_input_as_handled()


func _take(entry: Dictionary) -> void:
	if gs.stash_take(entry):
		_status.text = ""
	else:
		_status.text = "Your pack is full"
	if world != null and world.inv_ui != null:
		world.inv_ui._refresh()


# ---------------------------------------------------------------- drawing

func refresh() -> void:
	if not open:
		return
	_gold_lbl.text = "%d gold" % gs.gold
	for n in _offer_box.get_children():
		n.queue_free()
	for offer in _offers:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(320, 42)
		row.add_theme_constant_override("separation", 8)
		var icon := TextureRect.new()
		icon.texture = db.inv_texture(str(offer["code"]))
		icon.custom_minimum_size = Vector2(40, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var nm := _label(str(db.item(str(offer["code"])).get("name", offer["code"])), 13, WHITE)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		nm.custom_minimum_size = Vector2(150, 40)
		row.add_child(nm)
		var pr := _label("%d" % int(offer["price"]), 13, GOLD)
		pr.custom_minimum_size = Vector2(56, 40)
		row.add_child(pr)
		var b := _button("Gamble", _gamble.bind(offer))
		b.custom_minimum_size = Vector2(60, 28)
		b.disabled = gs.gold < int(offer["price"])
		row.add_child(b)
		_offer_box.add_child(row)
	for n in _respec_box.get_children():
		n.queue_free()
	var rs := _button("Reset skills  (%d gold)" % respec_price(), _respec_skills)
	rs.disabled = gs.gold < respec_price()
	_respec_box.add_child(rs)
	var rt := _button("Reset stats  (%d gold)" % respec_price(), _respec_stats)
	rt.disabled = gs.gold < respec_price()
	_respec_box.add_child(rt)
	_refresh_stash()


func _refresh_stash() -> void:
	for n in _stash_tabs.get_children():
		n.queue_free()
	if _page >= gs.stash_pages:
		_page = 0
	for i in range(gs.stash_pages):
		var tb := _button("Page %d" % (i + 1), func():
			_page = i
			_refresh_stash())
		tb.custom_minimum_size = Vector2(56, 24)
		if i == _page:
			tb.add_theme_color_override("font_color", GOLD)
		_stash_tabs.add_child(tb)
	if gs.stash_pages < MAX_PAGES:
		var buy := _button("+ page  (%d)" % page_price(), _buy_page)
		buy.custom_minimum_size = Vector2(100, 24)
		buy.disabled = gs.gold < page_price()
		_stash_tabs.add_child(buy)
	for n in _stash_nodes:
		n.queue_free()
	_stash_nodes.clear()
	for it in gs.stash_items:
		if int(it.get("page", 0)) != _page:
			continue
		var rect := Rect2(Vector2(it.x, it.y) * STASH_CELL, Vector2(it.w, it.h) * STASH_CELL)
		var s := D2Slot.new(rect)
		s.set_item(db.inv_texture(str(it.get("code", ""))))
		s.button.mouse_entered.connect(func():
			tooltip_card.show_item(it, _stash_grid.global_position
					+ rect.position + Vector2(rect.size.x * 0.5, 0)))
		s.button.mouse_exited.connect(func(): tooltip_card.hide_item())
		s.button.pressed.connect(_take.bind(it))
		_stash_grid.add_child(s)
		_stash_nodes.append(s)
