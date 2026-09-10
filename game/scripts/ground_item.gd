class_name GroundItem
extends BillboardAnim
## A dropped item: plays its flippy (falling) animation once, then rests.

var code := ""
var display_name := ""
var gold_amount := 0
var name_color := Color(1, 1, 1)
var instance := {}          # unique/set/rare payload, empty for plain items
var silent := false         # a replay's puppet: the log carries the sound

# D2 plays each item's own sound (items.txt dropsound: item_amulet,
# item_ring, item_gem, item_sword ...) when the flippy lands, at
# dropsfxframe; the generic item_flippy is the fallback for a sound the
# export did not carry
var _land_key := "flippy"
var _land_frame := 12
var _landed := false


func drop(item_code: String, gold := 0) -> void:
	code = item_code
	gold_amount = gold
	var db := get_node("/root/ItemDB")
	var it: Dictionary = db.item(code)
	var sfx := get_node("/root/Sfx")
	var ds := str(it.get("dropsound", ""))
	if ds != "" and sfx.has_event(ds):
		_land_key = ds
	_land_frame = maxi(1, str(it.get("dropsfxframe", "12")).to_int())
	_landed = false
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


func _process(dt: float) -> void:
	super(dt)
	if _landed or sheet == null:
		return
	if int(frame_f) >= _land_frame or not playing:
		_landed = true
		if not silent:
			get_node("/root/Sfx").event(_land_key, global_position)


func label_height() -> float:
	# flippy canvases bake the whole fall path (150+ px tall), so never use
	# the sheet height - the resting item sits at the canvas bottom
	return 0.45
