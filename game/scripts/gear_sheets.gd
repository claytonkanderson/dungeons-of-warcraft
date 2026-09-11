extends Node
## Autoloaded as GearSheets: the Amazon in her own gear, for the dungeon.
##
## The paperdoll composes the idle pose for the menu from one strip per
## equipment layer; this does the same for every direction of the idle,
## walk, run and attack animations (assets/amazon/layers, from
## export_paperdoll.build_layers) and registers the result with SpriteDB
## as a sheet a BillboardAnim can play, so another player's Amazon is
## drawn wearing what she wears. One composite per outfit, animation and
## weapon class, made the first time it is asked for.

const DIR := "amazon/layers"
const BODY := {"Torso": "TR", "Legs": "LG", "rArm": "RA", "lArm": "LA",
		"rSPad": "S1", "lSPad": "S2"}
const ARMOR_CLASS := ["LIT", "MED", "HVY"]
const MODES := {"nu": "nu", "wl": "wl", "ru": "rn", "a1": "a1"}   # pose -> layer mode

var manifest: Dictionary = {}
var _strips := {}                # strip key -> Image
var _made := {}                  # sheet key -> true once registered


func _ready() -> void:
	var f := FileAccess.open(ProjectSettings.globalize_path(
			Paths.asset(DIR + "/layers.json")), FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		manifest = parsed


func available() -> bool:
	return not manifest.is_empty()


static func outfit_key(gear: Dictionary) -> String:
	## one short string per outfit, for the sheet cache
	var parts := []
	var slots: Array = gear.keys()
	slots.sort()
	for s in slots:
		parts.append("%s=%s" % [s, str(gear[s].get("code", ""))])
	return ",".join(parts).md5_text().substr(0, 12)


func sheet_for(gear: Dictionary, pose: String) -> String:
	## The SpriteDB key of the composite for this outfit in this pose, made
	## on first use; "" when the layers were never exported or the pose has
	## no art, so the caller falls back to the bare sheets.
	if manifest.is_empty():
		return ""
	var mode: String = MODES.get(pose, "")
	if mode == "":
		return ""
	var classes: Dictionary = manifest.get("modes", {}).get(mode, {})
	if classes.is_empty():
		return ""
	var gs := get_node("/root/GameState")
	var wc: String = gs.weapon_class(str(gear.get("weap", {}).get("code", "")))
	if not classes.has(wc):
		wc = "hth"
	var cls: Dictionary = classes.get(wc, {})
	if cls.is_empty():
		return ""
	var key := "gear/%s/%s_%s" % [outfit_key(gear), mode, wc]
	if _made.has(key):
		return key
	var sheet = _compose(gear, cls, mode)
	if sheet == null:
		return ""
	get_node("/root/SpriteDB").register(key, sheet)
	_made[key] = true
	return key


func _gear_codes(gear: Dictionary, cls: Dictionary) -> Dictionary:
	## Equipment slots -> the layer code each COF component draws (the
	## paperdoll's rule: bare skin where nothing is worn, the body armour's
	## light/medium/heavy per part, the helm's, shield's and weapon's own art)
	var db := get_node("/root/ItemDB")
	var gen := get_node("/root/ItemGen")
	var codes: Dictionary = cls.get("codes", {})
	var out := {}
	for comp in codes:
		if BODY.values().has(comp) or comp == "HD":
			out[comp] = "LIT"
	var tors := str(gear.get("tors", {}).get("code", ""))
	if tors != "":
		var it: Dictionary = db.item(tors)
		for col in BODY:
			var v := str(it.get(col, ""))
			if v != "":
				out[BODY[col]] = ARMOR_CLASS[clampi(v.to_int(), 0, 2)]
	var head := str(gear.get("head", {}).get("code", ""))
	if head != "":
		out["HD"] = str(db.item(head).get("gfx", "")).to_upper()
	var off := str(gear.get("shie", {}).get("code", ""))
	if off != "":
		var chain: Dictionary = gen.type_chain(str(db.item(off).get("type", "")))
		if chain.has("shie") or chain.has("ashd"):
			out["SH"] = str(db.item(off).get("gfx", "")).to_upper()
	var weap := str(gear.get("weap", {}).get("code", ""))
	var wcomp := str(cls.get("weapon_comp", ""))
	if weap != "" and wcomp != "":
		out[wcomp] = str(db.item(weap).get("gfx", "")).to_upper()
	for comp in out.keys():
		var avail: Array = codes.get(comp, [])
		if not avail.has(out[comp]):
			if comp == "HD" or BODY.values().has(comp):
				out[comp] = "LIT"
			else:
				out.erase(comp)
	return out


func _strip(key: String) -> Image:
	if _strips.has(key):
		return _strips[key]
	var img := Image.load_from_file(ProjectSettings.globalize_path(
			Paths.asset(DIR + "/%s.png" % key)))
	if img != null and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	_strips[key] = img
	return img


func _compose(gear: Dictionary, cls: Dictionary, mode: String):
	var gearc := _gear_codes(gear, cls)
	var layer_wc: Dictionary = cls.get("layers", {})
	var strips: Dictionary = manifest.get("strips", {})
	var canvas: Array = cls.get("canvas", [0, 0])
	var origin: Array = cls.get("origin", [0, 0])
	var cw := int(canvas[0])
	var ch := int(canvas[1])
	var frames := int(cls.get("frames", 0))
	var dirs := int(cls.get("dirs", 0))
	var order: Array = cls.get("order", [])
	if cw <= 0 or ch <= 0 or frames <= 0 or dirs <= 0 or order.is_empty():
		return null
	var out := Image.create(cw * frames, ch * dirs, false, Image.FORMAT_RGBA8)
	for di in range(dirs):
		var per_frame: Array = order[di % order.size()]
		for fi in range(frames):
			var comps: Array = per_frame[fi % per_frame.size()]
			for comp in comps:
				var armor := str(gearc.get(comp, ""))
				if armor == "":
					continue
				var key := "%s_%s_%s_%s" % [str(comp).to_lower(), armor.to_lower(),
						mode, str(layer_wc.get(comp, "")).to_lower()]
				var meta: Dictionary = strips.get(key, {})
				var img := _strip(key)
				if img == null or meta.is_empty():
					continue
				var cell: Array = meta["cell"]
				var offs: Array = meta["off"]
				var sf: int = mini(fi, int(meta["frames"]) - 1)
				var sd: int = di % maxi(1, int(meta.get("dirs", 1)))
				out.blend_rect(img,
						Rect2i(sf * int(cell[0]), sd * int(cell[1]), int(cell[0]), int(cell[1])),
						Vector2i(fi * cw + int(origin[0]) + int(offs[0]),
								di * ch + int(origin[1]) + int(offs[1])))
	var db := get_node("/root/SpriteDB")
	var sheet = db.new_sheet()
	sheet.texture = ImageTexture.create_from_image(out)
	sheet.cell = Vector2i(cw, ch)
	sheet.origin = Vector2i(int(origin[0]), int(origin[1]))
	sheet.dirs = dirs
	sheet.frames = frames
	sheet.fps = float(cls.get("fps", 12.5))
	sheet.triggers = cls.get("triggers", [])
	return sheet
