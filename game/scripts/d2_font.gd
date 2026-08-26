extends Node
## Autoloaded as D2Font: builds a Godot FontFile from the extracted
## font16 glyph atlas + width table. Use D2Font.font in theme overrides.

var font: FontFile
var size := 16


func _ready() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(
		"res://../assets/ui/font16_atlas.png"))
	var f := FileAccess.open(ProjectSettings.globalize_path(
		"res://../assets/ui/font16_atlas.json"), FileAccess.READ)
	if img == null or f == null:
		push_warning("D2 font assets missing; falling back to default font")
		return
	var meta: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var cw := int(meta["cell"][0])
	var ch := int(meta["cell"][1])
	size = ch

	font = FontFile.new()
	font.fixed_size = ch
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
