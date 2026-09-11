extends CanvasLayer
## The goblin's trade screen: Diablo II's vendor page (buysell.DC6) with
## the gamble stock laid out on its 10x10 grid, the buy / sell / close
## buttons on their wells, and the pack open beside it.
##
## Gambling is Gheed's: a base item at a price, unseen until bought, magic
## at least with a chance of rare, set or unique. Click a piece to buy it
## into the pack (right-click too); the Buy button only marks the mode, as
## it does in D2. Selling: press Sell, then click an item in the pack; or
## pick an item up in the pack and drop it anywhere on this page. Respec
## and stash pages are on the goblin's talk menu (world.gd), priced here.
## Everything is this player's own (gold, pack), so co-op needs nothing
## from the host.

const GOLD := Color(0.95, 0.85, 0.4)
const GRID_ORIGIN := Vector2(15.0, 62.0)   # measured on buysell_0.png
const CELL := 29.0
const COLS := 10
const ROWS := 10
const NAME_RECT := Rect2(17, 359, 184, 17)
const BTN_BUY := Vector2(118, 387)         # 32x32 art centred on the 28x20 wells
const BTN_SELL := Vector2(170, 387)
const BTN_CLOSE := Vector2(274, 387)
const MAX_OFFERS := 18
const MAX_PAGES := 4

var open := false
var world = null
var panel: D2Panel
var name_field: D2Field
var tooltip_card: ItemTooltip
var mode := ""                    # "", "buy" or "sell"
var _offers: Array = []           # [{code, price, x, y, w, h}] this visit's stock
var _slots: Array = []
var _buy_btn: TextureButton
var _sell_btn: TextureButton

@onready var gs := get_node("/root/GameState")
@onready var db := get_node("/root/ItemDB")
@onready var gen := get_node("/root/ItemGen")


func _ready() -> void:
	layer = 7
	panel = D2Panel.new("ui/buysell_0.png")
	panel.visible = false
	add_child(panel)
	# the whole page takes a click: an item carried from the pack and let
	# go anywhere on the vendor's side is sold, as in D2
	var catcher := Control.new()
	catcher.size = D2Panel.NATIVE
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(_on_page_click)
	panel.content.add_child(catcher)
	name_field = D2Field.new(NAME_RECT, 14, GOLD, HORIZONTAL_ALIGNMENT_CENTER, true, "font8")
	panel.content.add_child(name_field)
	_buy_btn = _button(BTN_BUY, 2, true)
	_buy_btn.toggled.connect(func(on: bool):
		_set_mode("buy" if on else ""))
	_sell_btn = _button(BTN_SELL, 4, true)
	_sell_btn.toggled.connect(func(on: bool):
		_set_mode("sell" if on else ""))
	var close_btn := _button(BTN_CLOSE, 10, false)
	close_btn.pressed.connect(func():
		get_node("/root/Sfx").event_ui("button")
		if world != null:
			world._ui_action("ui:vendor"))
	tooltip_card = ItemTooltip.new()
	add_child(tooltip_card)
	gs.inventory_changed.connect(func():
		if open:
			_refresh())


func _button(at: Vector2, frame: int, toggles: bool) -> TextureButton:
	## one of buysellbtn's 32x32 buttons: frame is the idle plate, the next
	## frame its pressed state
	var b := TextureButton.new()
	b.position = at
	b.size = Vector2(32, 32)
	b.ignore_texture_size = true
	b.stretch_mode = TextureButton.STRETCH_KEEP
	b.texture_normal = _frame(frame)
	b.texture_pressed = _frame(frame + 1)
	b.texture_hover = _frame(frame)
	b.toggle_mode = toggles
	b.focus_mode = Control.FOCUS_NONE
	panel.content.add_child(b)
	return b


func _frame(i: int) -> Texture2D:
	var sheet = get_node("/root/SpriteDB").load_sheet("ui/buysellbtn")
	if sheet == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = sheet.texture
	at.region = Rect2(i * sheet.cell.x, 0, sheet.cell.x, sheet.cell.y)
	return at


func _set_mode(m: String) -> void:
	mode = m
	_buy_btn.set_pressed_no_signal(m == "buy")
	_sell_btn.set_pressed_no_signal(m == "sell")
	if m == "buy":
		_say("Click a piece to gamble on it")
	elif m == "sell":
		_say("Click an item in your pack to sell it")
	else:
		_say("")


func _say(s: String) -> void:
	name_field.set_value(s if s != "" else load("res://scripts/outpost.gd").VENDOR_NAME)


func toggle() -> void:
	## mouse/look state is owned by the world's _sync_ui()
	open = not open
	panel.visible = open
	var inv = world.inv_ui if world != null else null
	if open:
		panel.fit(get_viewport().get_visible_rect().size, false)
		_set_mode("")
		_new_offers()
		_refresh()
		if inv != null:
			inv.click_hook = _on_pack_click
	else:
		mode = ""
		if inv != null and inv.click_hook == Callable(_on_pack_click):
			inv.click_hook = Callable()
		if tooltip_card != null:
			tooltip_card.hide_item()


# ---------------------------------------------------------------- the stock

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


func _size_of(code: String) -> Vector2i:
	var it: Dictionary = db.item(code)
	return Vector2i(maxi(1, str(it.get("invwidth", "1")).to_int()),
			maxi(1, str(it.get("invheight", "1")).to_int()))


func _free(x: int, y: int, w: int, h: int, ignore = null) -> bool:
	if x < 0 or y < 0 or x + w > COLS or y + h > ROWS:
		return false
	for o in _offers:
		if o == ignore:
			continue
		if x < int(o.x) + int(o.w) and int(o.x) < x + w \
				and y < int(o.y) + int(o.h) and int(o.y) < y + h:
			return false
	return true


func _place(code: String, ignore = null) -> Dictionary:
	## the first cell, row by row, where a base of this size sits; empty
	## when the grid is full
	var sz := _size_of(code)
	for y in range(ROWS):
		for x in range(COLS):
			if _free(x, y, sz.x, sz.y, ignore):
				return {"code": code, "price": price_of(code), "x": x, "y": y, "w": sz.x, "h": sz.y}
	return {}


func _new_offers() -> void:
	var pool := gamble_bases()
	_offers = []
	var seen := {}
	var tries := 0
	while _offers.size() < MAX_OFFERS and tries < 120 and not pool.is_empty():
		tries += 1
		var code: String = pool[randi() % pool.size()]
		if seen.has(code):
			continue
		seen[code] = true
		var o := _place(code)
		if not o.is_empty():
			_offers.append(o)


func _restock(offer: Dictionary) -> void:
	## the slot sells again: a fresh base of the same footprint if one
	## exists, else whatever fits where it stood
	var pool := gamble_bases()
	for tries in range(40):
		if pool.is_empty():
			break
		var code: String = pool[randi() % pool.size()]
		var sz := _size_of(code)
		if sz.x == int(offer.w) and sz.y == int(offer.h):
			offer["code"] = code
			offer["price"] = price_of(code)
			return
	var idx := _offers.find(offer)
	if idx >= 0:
		_offers.remove_at(idx)


# ---------------------------------------------------------------- dealing

func _gamble(offer: Dictionary) -> void:
	var price := int(offer["price"])
	if gs.gold < price:
		_say("Not enough gold (%d needed)" % price)
		return
	# Diablo II's gamble odds: magic at least, the rest well above a drop
	var code := str(offer["code"])
	var inst: Dictionary = gen.roll_item(code, gs.level + 4,
			{"unique": 600, "set": 600, "rare": 400, "magic": 0}, "magic")
	if not gs.inv_try_add(code, inst):
		_say("No room in your pack")
		return
	gs.gold -= price
	var name: String = str(inst.get("name", db.item(code).get("name", "?")))
	_say("You got: %s" % name)
	get_node("/root/Sfx").event_ui("gold_drop")
	_restock(offer)
	gs.inventory_changed.emit()


func sell_price(entry: Dictionary) -> int:
	## a quarter of the item's worth, and no vendor pays more than the
	## character's level lets them (D2's cap, roughly)
	var it: Dictionary = db.item(str(entry.get("code", "")))
	var value := maxi(10, str(it.get("cost", "")).to_int())
	var inst: Dictionary = entry.get("inst", {})
	match str(inst.get("quality", "")):
		"magic":
			value *= 2
		"rare":
			value *= 4
		"set":
			value *= 5
		"unique":
			value *= 6
	return clampi(value / 4, 1, 1000 + 500 * maxi(1, gs.level))


func _sell(entry: Dictionary) -> void:
	if not gs.inv_items.has(entry):
		return
	var price := sell_price(entry)
	var name: String = str(entry.get("inst", {}).get("name",
			db.item(str(entry.get("code", ""))).get("name", "?")))
	gs.inv_items.erase(entry)
	gs.add_gold(price)
	var inv = world.inv_ui if world != null else null
	if inv != null and inv.carried == entry:
		inv.carried = null
	if tooltip_card != null:
		tooltip_card.hide_item()
	if inv != null and inv.tooltip_card != null:
		inv.tooltip_card.hide_item()
	_say("Sold %s for %d gold" % [name, price])
	get_node("/root/Sfx").event_ui("gold_drop")
	gs.inventory_changed.emit()


func _on_pack_click(entry: Dictionary) -> bool:
	## the pack's hook: in sell mode a click on an item sells it instead
	## of picking it up
	if mode != "sell":
		return false
	_sell(entry)
	return true


func _on_page_click(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	var inv = world.inv_ui if world != null else null
	if inv != null and inv.carried != null:
		_sell(inv.carried)
		get_viewport().set_input_as_handled()


func _on_offer_click(offer: Dictionary) -> void:
	var inv = world.inv_ui if world != null else null
	if inv != null and inv.carried != null:
		_sell(inv.carried)
		return
	if mode == "sell":
		return
	_gamble(offer)


# ---------------------------------------------------------------- drawing

func _refresh() -> void:
	if not open:
		return
	for n in _slots:
		n.queue_free()
	_slots.clear()
	for offer in _offers:
		var o: Dictionary = offer
		var rect := Rect2(GRID_ORIGIN + Vector2(o.x, o.y) * CELL, Vector2(o.w, o.h) * CELL)
		var s := D2Slot.new(rect)
		s.set_item(db.inv_texture(str(o["code"])))
		if gs.gold < int(o["price"]):
			s.highlight(Color(0.6, 0.05, 0.05, 0.35))
		s.button.mouse_entered.connect(func():
			if tooltip_card != null:
				tooltip_card.show_item({"code": str(o["code"])}, panel.to_screen(
						rect.position + Vector2(rect.size.x * 0.5, 0)),
						[["Price: %d" % int(o["price"]), GOLD]]))
		s.button.mouse_exited.connect(func():
			if tooltip_card != null:
				tooltip_card.hide_item())
		s.button.pressed.connect(_on_offer_click.bind(o))
		s.button.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed \
					and ev.button_index == MOUSE_BUTTON_RIGHT:
				_gamble(o))
		panel.content.add_child(s)
		_slots.append(s)


# ---------------------------------------------------------------- the talk menu's wares

func respec_price() -> int:
	return 500 * maxi(1, gs.level)


func page_price() -> int:
	return 5000 * gs.stash_pages


func respec_skills() -> String:
	var p := respec_price()
	if gs.gold < p:
		return "Not enough gold (%d needed)" % p
	var n: int = gs.respec_skills()
	gs.gold -= p
	gs.inventory_changed.emit()
	return "%d skill points returned" % n


func respec_stats() -> String:
	var p := respec_price()
	if gs.gold < p:
		return "Not enough gold (%d needed)" % p
	var n: int = gs.respec_stats()
	gs.gold -= p
	gs.inventory_changed.emit()
	return "%d stat points returned" % n


func buy_page() -> String:
	if gs.stash_pages >= MAX_PAGES:
		return "The stash has every page it can hold"
	var p := page_price()
	if gs.gold < p:
		return "Not enough gold (%d needed)" % p
	gs.gold -= p
	gs.stash_pages += 1
	gs.inventory_changed.emit()
	return "Stash page %d bought" % gs.stash_pages
