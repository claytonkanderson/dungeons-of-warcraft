extends Control
## The main-menu paperdoll: the Amazon idle, wearing whatever the selected
## character has equipped.
##
## The pipeline exports one strip per equipment layer rather than per outfit
## (assets/amazon/paperdoll), because the outfit is only known at runtime.
## Here we resolve each equipment slot to a D2 layer code, stack the layers in
## the COF's per-frame draw order, and bake the result into a single texture
## that the idle loop then just scrolls through.

const DIR := "amazon/paperdoll"

# Body armour names a light/medium/heavy variant per body part; the columns
# are 0/1/2 and each maps to one COF component.
const BODY := {"Torso": "TR", "Legs": "LG", "rArm": "RA", "lArm": "LA",
		"rSPad": "S1", "lSPad": "S2"}
const ARMOR_CLASS := ["LIT", "MED", "HVY"]

var px_scale := 3
var manifest: Dictionary = {}

var _layers := {}                # strip key -> Image
var _frames: Array[Texture2D] = []
var _canvas := Vector2i.ZERO
var _frame := 0.0
var _fps := 12.5


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var f := FileAccess.open(ProjectSettings.globalize_path(
			Paths.asset(DIR + "/paperdoll.json")), FileAccess.READ)
	if f == null:
		set_process(false)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		manifest = parsed
		_fps = float(manifest.get("fps", 12.5))
	else:
		set_process(false)


func weapon_class(code: String) -> String:
	## Which animation the equipped weapon puts the Amazon in. weapons.txt
	## names it outright, which is the only way a two-hander gets its own
	## stance instead of the one-handed one.
	if code == "":
		return "hth"
	var it: Dictionary = get_node("/root/ItemDB").item(code)
	var classes: Dictionary = manifest.get("classes", {})
	var named := str(it.get("2handedwclass" if str(it.get("2handed", "")) == "1"
			else "wclass", "")).to_lower()
	if classes.has(named):
		return named
	var chain: Dictionary = get_node("/root/ItemGen").type_chain(
			str(it.get("type", "")))
	if chain.has("bow"):
		return "bow"
	if chain.has("xbow"):
		return "xbw"
	if chain.has("jave") or chain.has("spea"):
		return "1ht"
	if chain.has("staf") or chain.has("pole"):
		return "stf"
	if chain.has("weap"):
		return "1hs"
	return "hth"


func is_shield(code: String) -> bool:
	var chain: Dictionary = get_node("/root/ItemGen").type_chain(
			str(get_node("/root/ItemDB").item(code).get("type", "")))
	return chain.has("shie") or chain.has("ashd")


func _gear_codes(equipped: Dictionary, cls: Dictionary) -> Dictionary:
	## Equipment slots -> the layer code each COF component should draw.
	var db := get_node("/root/ItemDB")
	var codes: Dictionary = cls.get("codes", {})
	var out := {}
	# bare skin everywhere the character wears nothing
	for comp in codes:
		if BODY.values().has(comp) or comp == "HD":
			out[comp] = "LIT"

	var tors := str(equipped.get("tors", {}).get("code", ""))
	if tors != "":
		var it: Dictionary = db.item(tors)
		for col in BODY:
			var v := str(it.get(col, ""))
			if v != "":
				out[BODY[col]] = ARMOR_CLASS[clampi(v.to_int(), 0, 2)]

	var head := str(equipped.get("head", {}).get("code", ""))
	if head != "":
		out["HD"] = str(db.item(head).get("gfx", "")).to_upper()

	var off := str(equipped.get("shie", {}).get("code", ""))
	if off != "" and is_shield(off):
		out["SH"] = str(db.item(off).get("gfx", "")).to_upper()

	var weap := str(equipped.get("weap", {}).get("code", ""))
	var wcomp := str(cls.get("weapon_comp", ""))
	if weap != "" and wcomp != "":
		out[wcomp] = str(db.item(weap).get("gfx", "")).to_upper()

	# drop anything this animation has no art for, so a missing helm code
	# leaves a bare head instead of a hole
	for comp in out.keys():
		var avail: Array = codes.get(comp, [])
		if not avail.has(out[comp]):
			if comp == "HD" or BODY.values().has(comp):
				out[comp] = "LIT"
			else:
				out.erase(comp)
	return out


func _strip(key: String) -> Image:
	if _layers.has(key):
		return _layers[key]
	var img := Image.load_from_file(ProjectSettings.globalize_path(
			Paths.asset(DIR + "/%s.png" % key)))
	if img != null and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	_layers[key] = img
	return img


func show_character(equipped: Dictionary) -> void:
	## Rebuild the composite for this outfit. Cheap enough to call on every
	## selection change: a handful of small blits per frame.
	_frames.clear()
	_frame = 0.0
	if manifest.is_empty():
		queue_redraw()
		return
	var wc := weapon_class(str(equipped.get("weap", {}).get("code", "")))
	var classes: Dictionary = manifest.get("classes", {})
	var cls: Dictionary = classes.get(wc, classes.get("hth", {}))
	if cls.is_empty():
		queue_redraw()
		return
	var gear := _gear_codes(equipped, cls)
	var layer_wc: Dictionary = cls.get("layers", {})
	var strips: Dictionary = manifest.get("strips", {})
	var canvas: Array = cls.get("canvas", [0, 0])
	var origin: Array = cls.get("origin", [0, 0])
	_canvas = Vector2i(int(canvas[0]), int(canvas[1]))
	var order: Array = cls.get("order", [])

	for fi in range(order.size()):
		var out := Image.create(_canvas.x, _canvas.y, false, Image.FORMAT_RGBA8)
		for comp in order[fi]:
			var armor := str(gear.get(comp, ""))
			if armor == "":
				continue
			var key := "%s_%s_%s" % [str(comp).to_lower(), armor.to_lower(),
					str(layer_wc.get(comp, "")).to_lower()]
			var meta: Dictionary = strips.get(key, {})
			var img := _strip(key)
			if img == null or meta.is_empty():
				continue
			var cell: Array = meta["cell"]
			var offs: Array = meta["off"]
			var f: int = mini(fi, int(meta["frames"]) - 1)
			out.blend_rect(img,
					Rect2i(f * int(cell[0]), 0, int(cell[0]), int(cell[1])),
					Vector2i(int(origin[0]) + int(offs[0]),
							int(origin[1]) + int(offs[1])))
		_frames.append(ImageTexture.create_from_image(out))
	# whole-pixel scale, largest that still fits: a two-hander is a much
	# wider canvas than a bow and must not spill out of the panel
	px_scale = 1
	if _canvas.x > 0 and _canvas.y > 0:
		px_scale = clampi(int(minf(size.x / _canvas.x, size.y / _canvas.y)), 1, 6)
	queue_redraw()


func clear() -> void:
	_frames.clear()
	queue_redraw()


func _process(dt: float) -> void:
	if _frames.is_empty():
		return
	_frame = fmod(_frame + _fps * dt, float(_frames.size()))
	queue_redraw()


func _draw() -> void:
	if _frames.is_empty():
		return
	var tex: Texture2D = _frames[int(_frame) % _frames.size()]
	var w := _canvas.x * px_scale
	var h := _canvas.y * px_scale
	# feet on the bottom edge, centred horizontally
	draw_texture_rect(tex, Rect2((size.x - w) * 0.5, size.y - h, w, h), false)
