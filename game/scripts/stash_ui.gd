extends CanvasLayer
## The stash: Diablo II's expansion stash page (TradeStash.dc6), 6 by 8
## cells, with the pack open beside it. Up to four pages, bought from the
## goblin; the arrows in the second field turn them. Click an item in the
## pack and then a stash cell to store it, click a stashed item to take it
## back into the pack. The top field shows the character's gold, as the
## page does in D2 (there is no separate stash purse here).

const GOLD := Color(0.95, 0.85, 0.4)
const GRID_ORIGIN := Vector2(74.0, 82.0)   # measured on tradestash_0.png
const CELL := 29.0
const COLS := 6
const ROWS := 8
const GOLD_RECT := Rect2(97, 24, 151, 15)
const COIN_AT := Vector2(74, 23)
const PAGE_RECT := Rect2(95, 50, 132, 16)
const PREV_RECT := Rect2(75, 49, 20, 18)
const NEXT_RECT := Rect2(227, 49, 20, 18)
const BTN_CLOSE := Vector2(274, 387)

var open := false
var world = null
var page := 0
var panel: D2Panel
var gold_field: D2Field
var page_field: D2Field
var tooltip_card: ItemTooltip
var _grid: Control
var _slots: Array = []

@onready var gs := get_node("/root/GameState")
@onready var db := get_node("/root/ItemDB")


func _ready() -> void:
	layer = 7
	panel = D2Panel.new("ui/tradestash_0.png")
	panel.visible = false
	add_child(panel)
	gold_field = D2Field.new(GOLD_RECT, 14, GOLD, HORIZONTAL_ALIGNMENT_CENTER, true, "font8")
	panel.content.add_child(gold_field)
	var coin := TextureRect.new()
	coin.texture = _frame("ui/goldcoinbtn", 0)
	coin.position = COIN_AT
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.content.add_child(coin)
	page_field = D2Field.new(PAGE_RECT, 14, GOLD, HORIZONTAL_ALIGNMENT_CENTER, true, "font8")
	panel.content.add_child(page_field)
	_arrow(PREV_RECT, "<", -1)
	_arrow(NEXT_RECT, ">", 1)
	_grid = Control.new()
	_grid.position = GRID_ORIGIN
	_grid.size = Vector2(COLS, ROWS) * CELL
	_grid.mouse_filter = Control.MOUSE_FILTER_STOP
	_grid.gui_input.connect(_on_grid_click)
	panel.content.add_child(_grid)
	var close_btn := TextureButton.new()
	close_btn.position = BTN_CLOSE
	close_btn.size = Vector2(32, 32)
	close_btn.ignore_texture_size = true
	close_btn.stretch_mode = TextureButton.STRETCH_KEEP
	close_btn.texture_normal = _frame("ui/buysellbtn", 10)
	close_btn.texture_pressed = _frame("ui/buysellbtn", 11)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.pressed.connect(func():
		get_node("/root/Sfx").event_ui("button")
		if world != null:
			world._ui_action("ui:stash"))
	panel.content.add_child(close_btn)
	tooltip_card = ItemTooltip.new()
	add_child(tooltip_card)
	gs.inventory_changed.connect(func():
		if open:
			_refresh())


func _frame(sheet_name: String, i: int) -> Texture2D:
	var sheet = get_node("/root/SpriteDB").load_sheet(sheet_name)
	if sheet == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = sheet.texture
	at.region = Rect2(i * sheet.cell.x, 0, sheet.cell.x, sheet.cell.y)
	return at


func _arrow(rect: Rect2, text: String, step: int) -> void:
	var b := Button.new()
	b.flat = true
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.focus_mode = Control.FOCUS_NONE
	get_node("/root/D2Font").style(b, 16)
	b.add_theme_color_override("font_color", GOLD)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.pressed.connect(func():
		get_node("/root/Sfx").event_ui("button")
		page = wrapi(page + step, 0, gs.stash_pages)
		_refresh())
	panel.content.add_child(b)


func toggle() -> void:
	## mouse/look state is owned by the world's _sync_ui()
	open = not open
	panel.visible = open
	if open:
		panel.fit(get_viewport().get_visible_rect().size, false)
		_refresh()
	elif tooltip_card != null:
		tooltip_card.hide_item()


func _on_grid_click(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	var inv = world.inv_ui if world != null else null
	if inv == null or inv.carried == null:
		return
	var local: Vector2 = _grid.get_local_mouse_position()
	var gx := int(floor(local.x / CELL))
	var gy := int(floor(local.y / CELL))
	var entry = inv.carried
	if gs.stash_put(entry, page, gx, gy):
		inv.carried = null
		inv._refresh()
	get_viewport().set_input_as_handled()


func _take(entry: Dictionary) -> void:
	if not gs.stash_take(entry):
		if world != null and world.hud_node != null:
			world.hud_node.show_area("Your pack is full", Color(1.0, 0.55, 0.3), 2.0)
	if tooltip_card != null:
		tooltip_card.hide_item()
	if world != null and world.inv_ui != null:
		world.inv_ui._refresh()


func _refresh() -> void:
	if not open:
		return
	if page >= gs.stash_pages:
		page = 0
	gold_field.set_value(str(gs.gold))
	page_field.set_value("Page %d of %d" % [page + 1, gs.stash_pages])
	for n in _slots:
		n.queue_free()
	_slots.clear()
	for item in gs.stash_items:
		var it: Dictionary = item
		if int(it.get("page", 0)) != page:
			continue
		var rect := Rect2(Vector2(it.x, it.y) * CELL, Vector2(it.w, it.h) * CELL)
		var s := D2Slot.new(rect)
		s.set_item(db.inv_texture(str(it.get("code", ""))))
		s.button.mouse_entered.connect(func():
			if tooltip_card != null:
				tooltip_card.show_item(it, panel.to_screen(GRID_ORIGIN
						+ rect.position + Vector2(rect.size.x * 0.5, 0))))
		s.button.mouse_exited.connect(func():
			if tooltip_card != null:
				tooltip_card.hide_item())
		s.button.pressed.connect(_take.bind(it))
		_grid.add_child(s)
		_slots.append(s)
