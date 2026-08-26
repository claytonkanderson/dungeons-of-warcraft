class_name GroundItem
extends BillboardAnim
## A dropped item: plays its flippy (falling) animation once, then rests.

var code := ""
var display_name := ""
var gold_amount := 0
var name_color := Color(1, 1, 1)
var instance := {}          # unique/set/rare payload, empty for plain items


func drop(item_code: String, gold := 0) -> void:
	code = item_code
	gold_amount = gold
	var db := get_node("/root/ItemDB")
	var it: Dictionary = db.item(code)
	display_name = str(it.get("name", code))
	if gold > 0:
		display_name = "%d Gold" % gold
		name_color = Color(0.95, 0.85, 0.4)
	var flippy := str(it.get("flippyfile", "")).to_lower()
	if flippy == "":
		flippy = "flp" + code
	play("items/flippy/%s" % flippy, false)


func drop_instance(inst: Dictionary) -> void:
	drop(str(inst.get("code", "")))
	instance = inst
	display_name = str(inst.get("name", display_name))
	name_color = inst.get("color", Color(1, 1, 1))


func label_height() -> float:
	# flippy canvases bake the whole fall path (150+ px tall), so never use
	# the sheet height - the resting item sits at the canvas bottom
	return 0.45
