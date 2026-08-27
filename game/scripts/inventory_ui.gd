class_name InventoryUI
extends CanvasLayer
## D2-style grid inventory panel. Toggle with I. Click an item to pick it
## up, click a cell to place it. Esc or I closes.

# original invchar6 panel art: grid measured on the 320x432 page
const ART_SCALE := 1.5
const ART_GRID := Vector2(15.0, 253.0)
const ART_CELL := 29.0
const CELL := ART_CELL * ART_SCALE

# equipment slot regions on the 320x432 inventory page (approximate)
const SLOT_RECTS := {
	"head": Rect2(137, 20, 48, 46),
	"amul": Rect2(212, 30, 26, 26),
	"weap": Rect2(13, 44, 64, 104),
	"shie": Rect2(244, 44, 64, 104),
	"tors": Rect2(132, 80, 58, 72),
	"belt": Rect2(132, 178, 58, 26),
	"ring1": Rect2(88, 178, 26, 26),
	"ring2": Rect2(214, 178, 26, 26),
	"glov": Rect2(13, 178, 48, 48),
	"boot": Rect2(244, 178, 48, 48),
}

var open := false
var panel: Control
var gold_label: Label
var carried = null            # inventory entry being moved
var _item_nodes := []
var tooltip_card: ItemTooltip

@onready var gs := get_node("/root/GameState")
@onready var db := get_node("/root/ItemDB")


func _ready() -> void:
	layer = 5
	panel = TextureRect.new()
	var img := Image.load_from_file(Paths.asset("ui/invchar_1.png"))
	if img != null:
		panel.texture = ImageTexture.create_from_image(img)
	panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel.visible = false
	add_child(panel)
	gold_label = Label.new()
	gold_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	get_node("/root/D2Font").style(gold_label, 16)
	gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(gold_label)
	gs.inventory_changed.connect(_refresh)
	gs.equipment_changed.connect(_refresh)
	tooltip_card = ItemTooltip.new()
	add_child(tooltip_card)


func toggle() -> void:
	# mouse/look state is owned by the world's _sync_ui()
	open = not open
	panel.visible = open
	if open:
		_layout()
		_refresh()
	else:
		carried = null
		if tooltip_card != null:
			tooltip_card.hide_item()


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	panel.size = Vector2(320, 432) * ART_SCALE
	panel.position = Vector2(vp.x - panel.size.x - 24, (vp.y - panel.size.y) * 0.5)
	# centered inside the wide gold-amount box at the page bottom
	gold_label.position = Vector2(102, 393) * ART_SCALE
	gold_label.size = Vector2(97, 17) * ART_SCALE


func _grid_origin() -> Vector2:
	return ART_GRID * ART_SCALE


func _refresh() -> void:
	if not open:
		return
	for n in _item_nodes:
		n.queue_free()
	_item_nodes.clear()
	gold_label.text = str(gs.gold)
	for it in gs.inv_items:
		var tex: Texture2D = db.inv_texture(it.code)
		var r := Button.new()
		r.flat = true
		r.position = _grid_origin() + Vector2(it.x, it.y) * CELL
		r.size = Vector2(it.w, it.h) * CELL
		r.mouse_entered.connect(func():
			if tooltip_card != null:
				tooltip_card.show_item(it, panel.position + r.position
						+ Vector2(r.size.x * 0.5, 0)))
		r.mouse_exited.connect(func():
			if tooltip_card != null:
				tooltip_card.hide_item())
		r.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed \
					and ev.button_index == MOUSE_BUTTON_RIGHT:
				if gs.equip_entry(it) and tooltip_card != null:
					tooltip_card.hide_item())
		r.pressed.connect(_on_item_clicked.bind(it))
		panel.add_child(r)
		_item_nodes.append(r)
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.position = r.position
			tr.size = r.size
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(tr)
			_item_nodes.append(tr)
		if it == carried:
			var hl := ColorRect.new()
			hl.color = Color(0.9, 0.8, 0.2, 0.25)
			hl.position = r.position
			hl.size = r.size
			hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(hl)
			_item_nodes.append(hl)

	# equipped items in their slots
	for slot in gs.equipped:
		var ent: Dictionary = gs.equipped[slot]
		if not SLOT_RECTS.has(slot):
			continue
		var rect: Rect2 = SLOT_RECTS[slot]
		var btn2 := Button.new()
		btn2.flat = true
		btn2.position = rect.position * ART_SCALE
		btn2.size = rect.size * ART_SCALE
		btn2.mouse_entered.connect(func():
			if tooltip_card != null:
				tooltip_card.show_item(ent, panel.position + btn2.position
						+ Vector2(btn2.size.x * 0.5, 0)))
		btn2.mouse_exited.connect(func():
			if tooltip_card != null:
				tooltip_card.hide_item())
		btn2.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed \
					and ev.button_index == MOUSE_BUTTON_RIGHT:
				gs.unequip(slot)
				if tooltip_card != null:
					tooltip_card.hide_item())
		panel.add_child(btn2)
		_item_nodes.append(btn2)
		var tex2: Texture2D = db.inv_texture(str(ent.get("code", "")))
		if tex2 != null:
			var tr2 := TextureRect.new()
			tr2.texture = tex2
			tr2.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tr2.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr2.position = btn2.position
			tr2.size = btn2.size
			tr2.mouse_filter = Control.MOUSE_FILTER_IGNORE
			panel.add_child(tr2)
			_item_nodes.append(tr2)



func _on_item_clicked(it) -> void:
	if carried == null:
		carried = it
	elif carried == it:
		carried = null
	_refresh()


func _input(e: InputEvent) -> void:
	if not open:
		return
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT \
			and carried != null:
		var local: Vector2 = panel.get_local_mouse_position()
		if not Rect2(Vector2.ZERO, panel.size).has_point(local):
			# carried item released outside the page: drop it on the ground
			var w: Node = get_tree().get_first_node_in_group("world")
			if w != null and w.has_method("drop_entry"):
				var entry = carried
				carried = null
				w.drop_entry(entry)
				_refresh()
			return
		# carried item released on its matching equipment slot: equip it
		for slot in SLOT_RECTS:
			var rect: Rect2 = SLOT_RECTS[slot]
			if Rect2(rect.position * ART_SCALE, rect.size * ART_SCALE).has_point(local):
				var want := str(gs.slot_for(str(carried.get("code", ""))))
				var ring_ok: bool = slot in ["ring1", "ring2"] \
						and want in ["ring1", "ring2"]
				if slot == want or ring_ok:
					var entry2 = carried
					carried = null
					if gs.equip_entry(entry2):
						if tooltip_card != null:
							tooltip_card.hide_item()
					_refresh()
					return
		var cell: Vector2 = local - _grid_origin()
		var gx := int(floor(cell.x / CELL))
		var gy := int(floor(cell.y / CELL))
		if gx >= 0 and gy >= 0 and gs.inv_move(carried, gx, gy):
			carried = null
			_refresh()
