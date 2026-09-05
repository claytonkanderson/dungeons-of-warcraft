extends Node
## Autoloaded as D2Font: Godot FontFiles built from the extracted D2 glyph
## atlases and width tables. D2 draws with several bitmap fonts and each is
## only right at its own pixel size: font16 for tooltips and titles, font8
## for the panels' captions and small numbers, fontformal10 for menus.
## style(label, px, name) picks one; the page it sits on does any scaling.

const NAMES := ["font16", "font8", "fontformal10", "fontexocet10", "font24",
		"font30", "font42"]
# the faces screen-space text (menus, HUD titles) chooses among by requested
# size: each drawn at its own pixel size, never resampled. font8 is left out
# (its bold small caps belong to the panels) and so is fontexocet10, whose
# lower case reads as a jumble at menu sizes.
const SCREEN_FACES := ["fontformal10", "font16", "font24", "font30", "font42"]

var fonts := {}        # name -> {font, size, ink_top, ink_bottom}

# the default face (font16), kept as plain fields for the older call sites
var font: FontFile
var size := 16
var ink_top := 4.0
var ink_bottom := 14.0


func _ready() -> void:
	for n in NAMES:
		var f := _load(n)
		if not f.is_empty():
			fonts[n] = f
	if fonts.has("font16"):
		font = fonts["font16"]["font"]
		size = fonts["font16"]["size"]
		ink_top = fonts["font16"]["ink_top"]
		ink_bottom = fonts["font16"]["ink_bottom"]
	else:
		push_warning("D2 font assets missing; falling back to default font")


func _load(name: String) -> Dictionary:
	var img := Image.load_from_file(Paths.asset("ui/%s_atlas.png" % name))
	var f := FileAccess.open(Paths.asset("ui/%s_atlas.json" % name), FileAccess.READ)
	if img == null or f == null:
		return {}
	var meta: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var cw := int(meta["cell"][0])
	var ch := int(meta["cell"][1])
	# where the ink of capitals and digits sits inside the cell (rows, bottom
	# exclusive): what "vertically centred" has to mean for a font whose cell
	# carries empty rows above the caps. The exporter measures it; older
	# atlases are measured here.
	var top := ch
	var bottom := 0
	if meta.has("ink"):
		top = int(meta["ink"][0])
		bottom = int(meta["ink"][1])
	else:
		for code in range(256):
			if not ((code >= 65 and code <= 90) or (code >= 48 and code <= 57)):
				continue
			var gx := (code % 16) * cw
			var gy := (code / 16) * ch
			for y in range(ch):
				for x in range(cw):
					if img.get_pixel(gx + x, gy + y).a > 0.5:
						top = mini(top, y)
						bottom = maxi(bottom, y + 1)
						break
	var ff := FontFile.new()
	ff.fixed_size = ch
	# a fixed-size bitmap font ignores font_size unless scaling is enabled;
	# D2Field shrinks long values to their box, which needs this
	ff.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	ff.set_texture_image(0, Vector2i(ch, 0), 0, img)
	var ascent := float(meta.get("ascent", ch - 2))
	ff.set_cache_ascent(0, ch, ascent)
	ff.set_cache_descent(0, ch, 2.0)
	var widths: Dictionary = meta.get("widths", {})
	for code in range(256):
		var gx := (code % 16) * cw
		var gy := (code / 16) * ch
		var w := int(widths.get(str(code), cw))
		ff.set_glyph_texture_idx(0, Vector2i(ch, 0), code, 0)
		ff.set_glyph_uv_rect(0, Vector2i(ch, 0), code, Rect2(gx, gy, cw, ch))
		ff.set_glyph_size(0, Vector2i(ch, 0), code, Vector2(cw, ch))
		ff.set_glyph_offset(0, Vector2i(ch, 0), code, Vector2(0, -ascent))
		ff.set_glyph_advance(0, ch, code, Vector2(w + 1, 0))
	return {"font": ff, "size": ch, "ink_top": float(top),
			"ink_bottom": float(bottom if bottom > top else ch)}


func has_font(name: String) -> bool:
	return fonts.has(name)


func font_of(name := "font16") -> FontFile:
	return fonts.get(name, fonts.get("font16", {})).get("font", null)


func size_of(name := "font16") -> int:
	## the font's native pixel size: draw it at this and nothing is resampled
	return int(fonts.get(name, fonts.get("font16", {})).get("size", 16))


func ink_center() -> float:
	## cell row at the middle of a capital, in the font's native pixels
	return ink_center_of("font16")


func ink_center_of(name: String) -> float:
	var f: Dictionary = fonts.get(name, fonts.get("font16", {}))
	return (float(f.get("ink_top", 4.0)) + float(f.get("ink_bottom", 14.0))) * 0.5


func style(label: Control, px := 16, name := "font16") -> void:
	var ff := font_of(name)
	if ff != null:
		label.add_theme_font_override("font", ff)
		label.add_theme_font_size_override("font_size", px)


func face_for(px: int) -> String:
	## The screen face whose native size is nearest the size asked for.
	var best := "font16"
	var bd := 1000
	for n in SCREEN_FACES:
		if not fonts.has(n):
			continue
		var d := absi(size_of(n) - px)
		if d < bd:
			bd = d
			best = n
	return best


func style_near(label: Control, px: int) -> int:
	## Style with the nearest screen face at that face's own size (a bitmap
	## font is only right at its native pixels). -> the size actually used.
	var n := face_for(px)
	style(label, size_of(n), n)
	return size_of(n)
