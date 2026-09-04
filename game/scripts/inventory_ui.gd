class_name InventoryUI
extends CanvasLayer
## D2-style grid inventory panel. Toggle with I. Click an item to pick it
## up, click a cell to place it. Esc or I closes.
##
## Built on D2Panel: the page is composed at its native 320x432 and every
## slot is a D2Slot at the rect measured off the page art itself, so items
## sit in their wells by construction. The old layout scaled hand-estimated
## rects by 1.5 and drew the grid 31 px above the actual wells.

# grid wells measured on invchar_1.png (row lines at y 254, 283, 312, 341,
# 370; column lines at x 17 + 29n): first cell at (18, 255), 28 px wells on
# a 29 px pitch, 10 across and 4 down
const GRID_ORIGIN := Vector2(18.0, 255.0)
const CELL := 29.0
const GRID_COLS := 10
const GRID_ROWS := 4

# equipment wells, measured on the page art (gloves mirror boots)
const SLOT_RECTS := {
	"head": Rect2(132, 2, 60, 60),
	"amul": Rect2(205, 30, 30, 31),
	"weap": Rect2(17, 45, 60, 116),
	"shie": Rect2(248, 45, 60, 117),
	"tors": Rect2(132, 73, 60, 89),
	"belt": Rect2(133, 175, 60, 31),
	"ring1": Rect2(91, 175, 30, 31),
	"ring2": Rect2(205, 175, 30, 31),
	"glov": Rect2(17, 175, 60, 61),
	"boot": Rect2(248, 175, 60, 61),
}
const GOLD_RECT := Rect2(102, 393, 97, 17)

var open := false
var panel: D2Panel
var gold_field: D2Field
var carried = null            # inventory entry being moved
var _item_nodes := []
var tooltip_card: ItemTooltip

@onready var gs := get_node("/root/GameState")
@onready var db := get_node("/root/ItemDB")


func _ready() -> void:
	layer = 5
	panel = D2Panel.new("ui/invchar_1.png")
	panel.visible = false
	add_child(panel)
	gold_field = D2Field.new(GOLD_RECT, 16, Color(0.95, 0.85, 0.4))
	panel.content.add_child(gold_field)
	gs.inventory_changed.connect(_refresh)
	gs.equipment_changed.connect(_refresh)
	tooltip_card = ItemTooltip.new()
	add_child(tooltip_card)


func toggle() -> void:
	# mouse/look state is owned by the world's _sync_ui()
	open = not open
	panel.visible = open
	if open:
		panel.fit(get_viewport().get_visible_rect().size, true)
		_refresh()
	else:
		carried = null
		if tooltip_card != null:
			tooltip_card.hide_item()


func _cell_rect(x: int, y: int, w: int, h: int) -> Rect2:
	return Rect2(GRID_ORIGIN + Vector2(x, y) * CELL, Vector2(w, h) * CELL)


func _slot(rect: Rect2, ent, on_right_click: Callable) -> D2Slot:
	var s := D2Slot.new(rect)
	s.set_item(db.inv_texture(str(ent.get("code", ""))))
	s.button.mouse_entered.connect(func():
		if tooltip_card != null:
			tooltip_card.show_item(ent, panel.to_screen(
					rect.position + Vector2(rect.size.x * 0.5, 0))))
	s.button.mouse_exited.connect(func():
		if tooltip_card != null:
			tooltip_card.hide_item())
	s.button.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed \
				and ev.button_index == MOUSE_BUTTON_RIGHT:
			on_right_click.call())
	panel.content.add_child(s)
	_item_nodes.append(s)
	return s


func _refresh() -> void:
	if not open:
		return
	for n in _item_nodes:
		n.queue_free()
	_item_nodes.clear()
	gold_field.set_value(str(gs.gold))
	for it in gs.inv_items:
		var s := _slot(_cell_rect(it.x, it.y, it.w, it.h), it, func():
			if gs.equip_entry(it) and tooltip_card != null:
				tooltip_card.hide_item())
		s.button.pressed.connect(_on_item_clicked.bind(it))
		if it == carried:
			s.highlight(Color(0.9, 0.8, 0.2, 0.25))
	# equipped items in their wells
	for slot in gs.equipped:
		var ent: Dictionary = gs.equipped[slot]
		if not SLOT_RECTS.has(slot):
			continue
		var key := str(slot)
		_slot(SLOT_RECTS[slot], ent, func():
			gs.unequip(key)
			if tooltip_card != null:
				tooltip_card.hide_item())


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
		# the panel's local position is in screen pixels; the page is native
		var local: Vector2 = panel.get_local_mouse_position() / panel.k
		if not Rect2(Vector2.ZERO, D2Panel.NATIVE).has_point(local):
			# carried item released outside the page: drop it on the ground
			var w: Node = get_tree().get_first_node_in_group("world")
			if w != null and w.has_method("drop_entry"):
				var entry = carried
				carried = null
				w.drop_entry(entry)
				_refresh()
			return
		# carried item released on its matching equipment well: equip it
		for slot in SLOT_RECTS:
			var rect: Rect2 = SLOT_RECTS[slot]
			if rect.has_point(local):
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
		var cell: Vector2 = local - GRID_ORIGIN
		var gx := int(floor(cell.x / CELL))
		var gy := int(floor(cell.y / CELL))
		if gx >= 0 and gy >= 0 and gx < GRID_COLS and gy < GRID_ROWS \
				and gs.inv_move(carried, gx, gy):
			carried = null
			_refresh()
