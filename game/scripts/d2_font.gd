extends Node
## Autoloaded as D2Font: builds a Godot FontFile from the extracted
## font16 glyph atlas + width table. Use D2Font.font in theme overrides.

var font: FontFile
var size := 16
# where the ink of capitals and digits sits inside the glyph cell (rows,
# bottom exclusive): what "vertically centred" has to mean for this font,
# since its cell carries empty rows above the caps
var ink_top := 4.0
var ink_bottom := 14.0


func ink_center() -> float:
	## cell row at the middle of a capital, in the font's native pixels
	return (ink_top + ink_bottom) * 0.5


func _ready() -> void:
	var img := Image.load_from_file(Paths.asset("ui/font16_atlas.png"))
	var f := FileAccess.open(Paths.asset("ui/font16_atlas.json"),
			FileAccess.READ)
	if img == null or f == null:
		push_warning("D2 font assets missing; falling back to default font")
		return
	var meta: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var cw := int(meta["cell"][0])
	var ch := int(meta["cell"][1])
	size = ch
	# measure the caps/digits ink rows off the atlas itself
	var top := ch
	var bottom := 0
	for code in range(256):
		# capitals 65-90 and digits 48-57, by code: char(0) would build a
		# string holding NUL, which the engine reports as a parsing error
		if not ((code >= 65 and code <= 90) or (code >= 48 and code <= 57)):
			continue
		var gx := (code % 16) * cw
		var gy := (code / 16) * ch
		for y in range(ch):
			for x in range(cw):
				if img.get_pixel(gx + x, gy + y).a > 0.0:
					top = mini(top, y)
					bottom = maxi(bottom, y + 1)
					break
	if bottom > top:
		ink_top = float(top)
		ink_bottom = float(bottom)

	font = FontFile.new()
	font.fixed_size = ch
	# a fixed-size bitmap font ignores font_size unless scaling is enabled;
	# D2Field shrinks long values to their box, which needs this
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	font.set_texture_image(0, Vector2i(ch, 0), 0, img)
	font.set_cache_ascent(0, ch, float(meta.get("ascent", ch - 2)))
	font.set_cache_descent(0, ch, 2.0)
	var widths: Dictionary = meta.get("widths", {})
	for code in range(256):
		var gx := (code % 16) * cw
		var gy := (code / 16) * ch
		var w := int(widths.get(str(code), cw))
		font.set_glyph_texture_idx(0, Vector2i(ch, 0), code, 0)
		font.set_glyph_uv_rect(0, Vector2i(ch, 0), code, Rect2(gx, gy, cw, ch))
		font.set_glyph_size(0, Vector2i(ch, 0), code, Vector2(cw, ch))
		font.set_glyph_offset(0, Vector2i(ch, 0), code, Vector2(0, -float(meta.get("ascent", ch - 2))))
		font.set_glyph_advance(0, ch, code, Vector2(w + 1, 0))


func style(label: Control, px := 16) -> void:
	if font != null:
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", px)
