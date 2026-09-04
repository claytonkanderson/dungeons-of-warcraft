class_name D2Field
extends Label
## A text box on a D2 page: a value that must sit inside its measured box.
## Centred, clipped, and shrunk a point at a time when a long value would
## spill past the box — the box is the constraint, never the text.

var _px := 16
var _min_px := 8
var _fit := true
var _rect: Rect2


func _init(rect: Rect2, px := 16, color := Color(1, 1, 1),
		align := HORIZONTAL_ALIGNMENT_CENTER, fit := true) -> void:
	## fit: shrink and clip to the box (values). Labels pass false — a
	## caption like "Attack Rating" is drawn at full size over the art, as
	## D2 does, and must never be cut to "Attack Rat".
	_rect = rect
	position = rect.position
	size = rect.size
	_px = px
	_fit = fit
	horizontal_alignment = align
	# vertical centring is done by hand (see _place): the font's cell has
	# empty rows above its capitals, so centring the cell sets the ink low
	vertical_alignment = VERTICAL_ALIGNMENT_TOP
	clip_text = fit
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_color_override("font_color", color)


func set_value(t: String) -> void:
	text = t
	var d2font := get_node("/root/D2Font")
	var px := _px
	d2font.style(self, px)
	if _fit:
		while px > _min_px and _text_width() > size.x - 2.0:
			px -= 1
			d2font.style(self, px)
	_place(px)


func _place(px: int) -> void:
	## Put the middle of a capital letter on the middle of the box. With TOP
	## alignment the glyph cell's top row is the label's top edge, so the ink
	## centre sits ink_center() cell rows down, scaled to this size.
	var d2font := get_node("/root/D2Font")
	var s := float(px) / float(d2font.size)
	position.y = _rect.position.y + _rect.size.y * 0.5 - d2font.ink_center() * s


func _text_width() -> float:
	var f := get_theme_font("font")
	var fs := get_theme_font_size("font_size")
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
