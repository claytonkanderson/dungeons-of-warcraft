extends Control
## "Dungeons of Warcraft" — the launch menu: character roster on the left,
## the vanilla dungeon ladder on the right, continue/enter at the bottom.
## Test/automation flags fall straight through into the world scene.

const GOLD := Color(0.85, 0.72, 0.35)
const GOLD_DIM := Color(0.55, 0.48, 0.3)
const GREY := Color(0.45, 0.45, 0.45)
const DARK := Color(0.3, 0.28, 0.28)
const GREEN := Color(0.25, 0.8, 0.25)
const WHITE := Color(0.9, 0.88, 0.82)

var sel_char := ""
var sel_dungeon := ""
var _char_box: VBoxContainer
var _dung_box: VBoxContainer
var _name_edit: LineEdit
var _enter_btn: Button
var _continue_btn: Button
var _delete_armed := false
var _delete_btn: Button

@onready var gs := get_node("/root/GameState")
@onready var dg := get_node("/root/Dungeons")


func _ready() -> void:
	# automation flags bypass the menu entirely (legacy/test save slot)
	for a in OS.get_cmdline_user_args():
		if str(a) in ["--combat-test", "--ui-test", "--fps-probe",
				"--walk-test", "--fresh"] or str(a).begins_with("--shots=") \
				or str(a).begins_with("--at=") \
				or str(a).begins_with("--dungeon="):
			get_tree().change_scene_to_file.call_deferred("res://scenes/world.tscn")
			return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	gs.migrate_legacy_save()
	_build()
	_refresh()
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--menu-shot="):
			for i in range(8):
				await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				str(a).substr(12))
			get_tree().quit()


func _label(text: String, px: int, color := GOLD) -> Label:
	var l := Label.new()
	l.text = text
	get_node("/root/D2Font").style(l, px)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _button(text: String, px: int, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	get_node("/root/D2Font").style(b, px)
	b.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 0.7))
	b.pressed.connect(cb)
	return b


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.025)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := _label("DUNGEONS  OF  WARCRAFT", 42)
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.position.y = 38
	add_child(title)
	var sub := _label("a Diablo / Warcraft hybrid mod", 16, GOLD_DIM)
	sub.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sub.position.y = 92
	add_child(sub)

	# ---- characters (left) ----
	var chead := _label("CHARACTERS", 20, WHITE)
	chead.position = Vector2(80, 150)
	chead.size.x = 320
	add_child(chead)
	_char_box = VBoxContainer.new()
	_char_box.position = Vector2(80, 190)
	_char_box.size = Vector2(320, 300)
	_char_box.add_theme_constant_override("separation", 6)
	add_child(_char_box)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "new character name"
	_name_edit.max_length = 20
	_name_edit.position = Vector2(80, 520)
	_name_edit.size = Vector2(200, 34)
	add_child(_name_edit)
	var create := _button("Create", 16, _on_create)
	create.position = Vector2(290, 520)
	create.size = Vector2(110, 34)
	add_child(create)
	_delete_btn = _button("Delete", 14, _on_delete)
	_delete_btn.position = Vector2(80, 562)
	_delete_btn.size = Vector2(110, 30)
	add_child(_delete_btn)

	# ---- dungeons (right) ----
	var dhead := _label("DUNGEONS", 20, WHITE)
	dhead.position = Vector2(500, 150)
	dhead.size.x = 700
	add_child(dhead)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(500, 190)
	scroll.size = Vector2(700, 420)
	add_child(scroll)
	_dung_box = VBoxContainer.new()
	_dung_box.custom_minimum_size.x = 680
	_dung_box.add_theme_constant_override("separation", 2)
	scroll.add_child(_dung_box)

	# ---- bottom bar ----
	_continue_btn = _button("CONTINUE", 22, _on_continue)
	_continue_btn.position = Vector2(500, 632)
	_continue_btn.size = Vector2(200, 44)
	add_child(_continue_btn)
	_enter_btn = _button("ENTER  DUNGEON", 22, _on_enter)
	_enter_btn.position = Vector2(720, 632)
	_enter_btn.size = Vector2(260, 44)
	add_child(_enter_btn)
	var quit := _button("QUIT", 22, func(): get_tree().quit())
	quit.position = Vector2(1000, 632)
	quit.size = Vector2(120, 44)
	add_child(quit)


func _selected_done() -> Array:
	for c in gs.list_characters():
		if str(c.slug) == sel_char:
			var f := FileAccess.open(gs.CHAR_DIR + "/%s.json" % sel_char,
					FileAccess.READ)
			if f != null:
				var d: Variant = JSON.parse_string(f.get_as_text())
				if d is Dictionary:
					return d.get("dungeons_done", [])
	return []


func _refresh() -> void:
	for n in _char_box.get_children():
		n.queue_free()
	for n in _dung_box.get_children():
		n.queue_free()
	var chars: Array = gs.list_characters()
	if sel_char == "" and not chars.is_empty():
		sel_char = str(chars[0].slug)
	for c in chars:
		var slug := str(c.slug)
		var b := _button("%s   -   level %d" % [str(c.name), int(c.level)], 18,
				func():
					sel_char = slug
					_delete_armed = false
					_delete_btn.text = "Delete"
					_refresh())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_color_override("font_color",
				GOLD if slug == sel_char else DARK)
		_char_box.add_child(b)
	if chars.is_empty():
		var hint := _label("create a character below", 14, GREY)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_char_box.add_child(hint)

	var done := _selected_done()
	if sel_dungeon == "" \
			or not (str(dg.status(sel_dungeon, done)) in ["available", "complete"]):
		sel_dungeon = dg.next_playable(done)
	for d in dg.LIST:
		var did := str(d.id)
		var st := str(dg.status(did, done))
		var row := Button.new()
		row.flat = true
		row.custom_minimum_size = Vector2(680, 26)
		row.pressed.connect(func():
			if st in ["available", "complete"]:
				sel_dungeon = did
				_refresh())
		_dung_box.add_child(row)
		var name_l := _label(str(d.name), 16, WHITE)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_l.position = Vector2(8, 2)
		name_l.size = Vector2(360, 22)
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(name_l)
		var lvl_l := _label(str(d.levels), 16, GREY)
		lvl_l.position = Vector2(380, 2)
		lvl_l.size = Vector2(80, 22)
		lvl_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lvl_l)
		var st_text: String = {"complete": "COMPLETE", "available": "AVAILABLE",
				"unbuilt": "NOT BUILT", "locked": "LOCKED"}[st]
		var st_col: Color = {"complete": GREEN, "available": GOLD,
				"unbuilt": Color(0.3, 0.3, 0.35), "locked": GREY}[st]
		var st_l := _label(str(st_text), 14, st_col)
		st_l.position = Vector2(480, 3)
		st_l.size = Vector2(120, 22)
		st_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(st_l)
		if did == sel_dungeon and st in ["available", "complete"]:
			var mark := _label(">", 16, GOLD)
			mark.position = Vector2(612, 2)
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(mark)
			name_l.add_theme_color_override("font_color", GOLD)

	var can_play: bool = sel_char != "" \
			and dg.status(sel_dungeon, done) in ["available", "complete"]
	_enter_btn.disabled = not can_play
	_continue_btn.disabled = sel_char == "" or dg.next_playable(done) == ""


func _on_create() -> void:
	var slug: String = gs.create_character(_name_edit.text)
	if slug == "":
		_name_edit.placeholder_text = "name taken / invalid"
		_name_edit.text = ""
		return
	_name_edit.text = ""
	sel_char = slug
	_refresh()


func _on_delete() -> void:
	if sel_char == "":
		return
	if not _delete_armed:
		_delete_armed = true
		_delete_btn.text = "Confirm?"
		return
	gs.delete_character(sel_char)
	sel_char = ""
	_delete_armed = false
	_delete_btn.text = "Delete"
	_refresh()


func _enter(did: String) -> void:
	if sel_char == "" or not gs.select_character(sel_char):
		return
	gs.enter_dungeon(did)
	get_tree().change_scene_to_file("res://scenes/world.tscn")


func _on_enter() -> void:
	_enter(sel_dungeon)


func _on_continue() -> void:
	var nxt: String = dg.next_playable(_selected_done())
	if nxt != "":
		_enter(nxt)
