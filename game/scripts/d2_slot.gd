class_name D2Slot
extends Control
## One well on a D2 page: an equipment slot or a run of grid cells. Sized to
## the well as measured off the page art, so the art beneath is its
## background. Whatever item sprite it is given is forced to fit inside —
## scaled down if larger, centred if smaller — and clipped to the well.

var sprite: TextureRect
var button: Button


func _init(rect: Rect2) -> void:
	position = rect.position
	size = rect.size
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite = TextureRect.new()
	sprite.size = size
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.visible = false
	add_child(sprite)
	button = Button.new()
	button.flat = true
	button.size = size
	button.focus_mode = Control.FOCUS_NONE
	add_child(button)


func set_item(tex: Texture2D) -> void:
	sprite.texture = tex
	sprite.visible = tex != null


func highlight(color: Color) -> void:
	var hl := ColorRect.new()
	hl.color = color
	hl.size = size
	hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hl)
	move_child(hl, button.get_index())
