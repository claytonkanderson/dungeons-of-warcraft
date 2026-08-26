class_name BillboardAnim
extends Sprite3D
## A Doom-style animated billboard. Plays one sheet (rows = directions,
## cols = frames); each frame the direction row is picked from the camera
## angle relative to `facing`, so entities visibly turn.

signal action_frame(index: int)   # fired on COF/animdata trigger frames
signal finished                   # fired at end when not looping

const PIXEL := 0.024              # world metres per sprite pixel

# D2 sheet row 0 faces screen-down in the original isometric view, i.e.
# toward the camera at world -Z here; rows advance clockwise. Calibrated
# with the direction test scene; adjust DIR_OFFSET if art proves otherwise.
const DIR_OFFSET := 0.0

var sheet: SpriteDB.Sheet
var facing := 0.0                 # world yaw the entity is looking toward
var looping := true
var playing := false
var frame_f := 0.0
var _fired := {}

@onready var db := get_node("/root/SpriteDB")


func _ready() -> void:
	billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	shaded = false
	pixel_size = PIXEL
	centered = false
	region_enabled = true


func play(rel: String, loop := true, anchor := "feet") -> void:
	var s: SpriteDB.Sheet = db.load_sheet(rel)
	if s == null:
		return
	sheet = s
	texture = s.texture
	looping = loop
	playing = true
	frame_f = 0.0
	_fired.clear()
	if anchor == "center":
		# projectiles: node position is the sprite centre (same convention as
		# the feet anchor below, with the origin at the cell midpoint)
		offset = Vector2(-s.cell.x * 0.5, -s.cell.y * 0.5)
	else:
		# feet at local origin: cell's origin pixel sits at (0,0)
		offset = Vector2(-s.origin.x, -(s.cell.y - s.origin.y))


func _process(dt: float) -> void:
	if sheet == null or not playing:
		return
	var prev := int(frame_f)
	frame_f += sheet.fps * dt
	if int(frame_f) != prev:
		for t in sheet.triggers:
			var ti := int(t)
			if prev < ti and int(frame_f) >= ti and not _fired.has(ti):
				_fired[ti] = true
				action_frame.emit(ti)
	if frame_f >= sheet.frames:
		if looping:
			frame_f = fmod(frame_f, float(sheet.frames))
			_fired.clear()
		else:
			frame_f = sheet.frames - 1
			playing = false
			finished.emit()

	var cam := get_viewport().get_camera_3d()
	var row := 0
	if cam != null and sheet.dirs > 1:
		var to_cam := cam.global_position - global_position
		var cam_yaw := atan2(to_cam.x, to_cam.z)
		var rel_angle := wrapf(facing - cam_yaw + DIR_OFFSET, 0.0, TAU)
		row = int(round(rel_angle / TAU * sheet.dirs)) % sheet.dirs
	region_rect = Rect2(int(frame_f) * sheet.cell.x, row * sheet.cell.y,
			sheet.cell.x, sheet.cell.y)
