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
		# a property the game does not apply yet is shown dimmed, so no line
		# on an item promises something the fight will not deliver
		for pair in get_node("/root/ItemText").lines_with_codes(inst):
			var applies: bool = GameState.applies(str(pair[1]))
			_line(str(pair[0]), MAGIC_BLUE if applies else INERT_GREY)
		_set_lines(inst)
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


const INERT_GREY := Color(0.45, 0.45, 0.5)
const SET_GREEN := Color(0.10, 0.85, 0.10)
const SET_GREY := Color(0.5, 0.5, 0.5)


func _set_lines(inst: Dictionary) -> void:
	## Set bonus section: this item's aprops per threshold, green when the
	## worn count unlocks them, grey when still locked (D2 style).
	if str(inst.get("quality", "")) != "set":
		return
	var gs := get_node("/root/GameState")
	var txt := get_node("/root/ItemText")
	var iname := str(inst.get("name", ""))
	var counts: Dictionary = gs.set_worn_counts()
	var sname := str(gs._setmap.get(iname, ""))
	var worn := int(counts.get(sname, 0))
	var aprops: Array = gs._setbonus.get("items", {}).get(iname, [])
	var any := false
	for i in range(aprops.size()):
		var plist: Array = aprops[i]
		if plist.is_empty():
			continue
		if not any:
			any = true
			_line(" ", Color.WHITE)
		var active: bool = worn >= i + 2
		for line in txt.lines_for({"props": plist}):
			_line("%s (%d items)" % [str(line), i + 2],
					SET_GREEN if active else SET_GREY)
	# set-wide bonuses on every piece of the set
	var sdef: Dictionary = gs._setbonus.get("sets", {}).get(sname, {})
	var partial: Array = sdef.get("partial", [])
	var shown_hdr := false
	for i in range(partial.size()):
		var plist2: Array = partial[i]
		if plist2.is_empty():
			continue
		if not shown_hdr:
			shown_hdr = true
			_line(" ", Color.WHITE)
			_line(sname, SET_GREEN if worn >= 2 else SET_GREY)
		for line in txt.lines_for({"props": plist2}):
			_line("%s (%d items)" % [str(line), i + 2],
					SET_GREEN if worn >= i + 2 else SET_GREY)
	var full: Array = sdef.get("full", [])
	if not full.is_empty():
		if not shown_hdr:
			_line(" ", Color.WHITE)
			_line(sname, SET_GREEN if worn >= 2 else SET_GREY)
		var complete: bool = worn >= 2 and worn >= int(sdef.get("count", 99))
		for line in txt.lines_for({"props": full}):
			_line("%s (full set)" % str(line),
					SET_GREEN if complete else SET_GREY)


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


func _has_code(inst: Dictionary, code: String) -> bool:
	for p in inst.get("props", []):
		if p.has("affix"):
			for q in p.get("props", []):
				if str(q.get("code", "")) == code:
					return true
		elif str(p.get("code", "")) == code:
			return true
	return false


func _base_lines(it: Dictionary, inst: Dictionary) -> void:
	## White base-stat lines: Defense on armor, Damage on weapons, req level.
	var chain: Dictionary = get_node("/root/ItemGen").type_chain(str(it.get("type", "")))
	if chain.has("char"):
		_line("Keep in Inventory to Gain Bonus", Color(0.75, 0.75, 0.75))
	var ed := _inst_mod(inst, "dmg%")
	# ethereal: half again the base damage and defence
	var ethm := 3 if _has_code(inst, "ethereal") else 2
	var mn2 := str(it.get("2handmindam", "")).to_int() * ethm / 2
	var mx2 := str(it.get("2handmaxdam", "")).to_int() * ethm / 2
	var mn1 := str(it.get("mindam", "")).to_int() * ethm / 2
	var mx1 := str(it.get("maxdam", "")).to_int() * ethm / 2
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
				(str(it.get("minac", "")).to_int() + mxac) / 2)) * ethm / 2
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
