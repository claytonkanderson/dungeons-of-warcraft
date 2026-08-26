class_name ItemTooltip
extends Control
## D2-style item hover card: black panel, centered lines, D2 font,
## quality-colored name, blue magic properties.

const MAGIC_BLUE := Color(0.41, 0.41, 1.0)

var bg: ColorRect
var vbox: VBoxContainer


func _ready() -> void:
	visible = false
	z_index = 100
	bg = ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0, 0.82)
	add_child(bg)
	vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	add_child(vbox)


func _line(text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	get_node("/root/D2Font").style(l, 16)
	vbox.add_child(l)


func show_item(entry: Dictionary, at: Vector2) -> void:
	for c in vbox.get_children():
		c.queue_free()
	var db := get_node("/root/ItemDB")
	var code := str(entry.get("code", ""))
	var base_name := str(db.item(code).get("name", code))
	var it: Dictionary = db.item(code)
	if entry.has("inst"):
		var inst: Dictionary = entry["inst"]
		var qcolor := Color.from_string(str(inst.get("color", "ffffff")), Color.WHITE)
		_line(str(inst.get("name", base_name)), qcolor)
		_line(str(inst.get("base_name", base_name)), qcolor)
		_base_lines(it, inst)
		for line in get_node("/root/ItemText").lines_for(inst):
			_line(str(line), MAGIC_BLUE)
	else:
		_line(base_name, Color.WHITE)
		_base_lines(it, {})
	visible = true
	await get_tree().process_frame
	var sz := vbox.get_combined_minimum_size() + Vector2(24, 12)
	bg.size = sz
	vbox.position = Vector2(12, 6)
	vbox.size = sz - Vector2(24, 12)
	size = sz
	var vp := get_viewport_rect().size
	position = Vector2(clampf(at.x - sz.x * 0.5, 8, vp.x - sz.x - 8),
			clampf(at.y - sz.y - 12, 8, vp.y - sz.y - 8))


func hide_item() -> void:
	visible = false


func _inst_mod(inst: Dictionary, code: String) -> int:
	var total := 0
	var flat := []
	for p in inst.get("props", []):
		if p.has("affix"):
			flat.append_array(p.get("props", []))
		else:
			flat.append(p)
	for p in flat:
		if str(p.get("code", "")) == code:
			total += int(p.get("val", str(p.get("min", "0")).to_int()))
	return total


func _base_lines(it: Dictionary, inst: Dictionary) -> void:
	## White base-stat lines: Defense on armor, Damage on weapons, req level.
	var ed := _inst_mod(inst, "dmg%")
	var mn2 := str(it.get("2handmindam", "")).to_int()
	var mx2 := str(it.get("2handmaxdam", "")).to_int()
	var mn1 := str(it.get("mindam", "")).to_int()
	var mx1 := str(it.get("maxdam", "")).to_int()
	var dmin := _inst_mod(inst, "dmg-min")
	var dmax := _inst_mod(inst, "dmg-max")
	if mx2 > 0:
		_line("Two-Hand Damage: %d to %d" % [
			mn2 * (100 + ed) / 100 + dmin, mx2 * (100 + ed) / 100 + dmax],
			Color.WHITE)
	if mx1 > 0:
		_line("One-Hand Damage: %d to %d" % [
			mn1 * (100 + ed) / 100 + dmin, mx1 * (100 + ed) / 100 + dmax],
			Color.WHITE)
	var mxac := str(it.get("maxac", "")).to_int()
	if mxac > 0:
		var base_ac := int(inst.get("base_ac",
				(str(it.get("minac", "")).to_int() + mxac) / 2))
		var acp := _inst_mod(inst, "ac%")
		var def := base_ac * (100 + acp) / 100 + _inst_mod(inst, "ac")
		_line("Defense: %d" % def, Color.WHITE)
	var gs := get_node("/root/GameState")
	var grey := Color(0.65, 0.65, 0.65)
	var red := Color(1.0, 0.25, 0.25)
	var rstr := str(it.get("reqstr", "")).to_int()
	var rdex := str(it.get("reqdex", "")).to_int()
	var rlvl := maxi(int(inst.get("reqlvl", 0)), str(it.get("levelreq", "")).to_int())
	if rstr > 0:
		_line("Required Strength: %d" % rstr,
				red if gs.total_stat("str") < rstr else grey)
	if rdex > 0:
		_line("Required Dexterity: %d" % rdex,
				red if gs.total_stat("dex") < rdex else grey)
	if rlvl > 1:
		_line("Required Level: %d" % rlvl, red if gs.level < rlvl else grey)
