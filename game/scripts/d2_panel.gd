class_name D2Panel
extends Control
## A Diablo II page (the 320x432 panel art) composed at NATIVE resolution
## inside a SubViewport, then shown at one scale.
##
## Every slot, sprite and text field is a Control positioned in the page's
## own pixel space, so it lands exactly where the art puts its well — no
## separate rounding path can drift. The finished page is scaled once, as a
## whole, the way D2 itself is upscaled: sprites, text and background move
## together. Mouse input is forwarded into the viewport with the inverse
## scale, so hover and clicks land on the widgets underneath.

const NATIVE := Vector2(320, 432)

var content: Control          # native-space root: add widgets here
var page: TextureRect         # the page art, beneath everything
var k := 1.5                  # display scale (see fit)
var _vp: SubViewport
var _view: TextureRect


func _init(page_png: String) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp = SubViewport.new()
	_vp.size = NATIVE
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_vp)
	page = TextureRect.new()
	var img := Image.load_from_file(Paths.asset(page_png))
	if img != null:
		page.texture = ImageTexture.create_from_image(img)
	page.size = NATIVE
	page.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vp.add_child(page)
	content = Control.new()
	content.size = NATIVE
	_vp.add_child(content)
	_view = TextureRect.new()
	_view.texture = _vp.get_texture()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.gui_input.connect(_forward)
	_view.mouse_exited.connect(func():
		# leaving the page: tell the widgets inside so hover states clear
		var e := InputEventMouseMotion.new()
		e.position = Vector2(-10, -10)
		_vp.push_input(e))
	add_child(_view)


func fit(vp_size: Vector2, right: bool, margin := 24.0) -> void:
	## Choose the scale and place the page. An integer scale whenever 2x or
	## more fits the window (pixel-exact); otherwise the largest fraction up
	## to 1.5x, which is what a 720p window allows.
	var whole: float = floor(vp_size.y * 0.95 / NATIVE.y)
	k = whole if whole >= 2.0 else minf(1.5, vp_size.y * 0.95 / NATIVE.y)
	size = NATIVE * k
	_view.size = size
	position = Vector2(vp_size.x - size.x - margin if right else margin,
			(vp_size.y - size.y) * 0.5)


func to_screen(native: Vector2) -> Vector2:
	## A native page point in screen space (for tooltips drawn outside).
	return global_position + native * k


func _forward(ev: InputEvent) -> void:
	if not (ev is InputEventMouse):
		return
	var e: InputEventMouse = ev.duplicate()
	e.position = ev.position / k
	if e is InputEventMouseMotion:
		e.relative = (ev as InputEventMouseMotion).relative / k
	_vp.push_input(e)
