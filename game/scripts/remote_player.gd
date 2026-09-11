class_name RemotePlayer
extends Node3D
## Another player's Amazon, as this machine sees her: a D2 Amazon
## billboard placed from the poses that player sends, with the name
## overhead. No body to collide with (two players in a doorway should
## not wedge each other), so creatures aim at her position and arrows
## pass through.

var peer_id := 0
var pname := ""
var mode := "nu"
var wclass := "bow"
var gear := {}                  # slot -> {code}: she is drawn wearing it
var _target := Vector3.ZERO
var _yaw := 0.0
var _have_pose := false
var _anim: BillboardAnim
var _label: Label3D
var _bar_bg: MeshInstance3D
var _bar: MeshInstance3D
var _life := 1.0
var _sheet := ""

const BAR_W := 0.9
const BAR_H := 0.08

@onready var _db := get_node("/root/SpriteDB")


func _ready() -> void:
	_anim = BillboardAnim.new()
	add_child(_anim)
	_label = Label3D.new()
	_label.text = pname
	_label.font_size = 40
	_label.pixel_size = 0.006
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.modulate = Color(0.85, 0.9, 1.0)
	_label.outline_modulate = Color(0, 0, 0)
	_label.outline_size = 10
	_label.position.y = 2.1
	add_child(_label)
	# her life, as D2 shows a party member's: a red bar under the name
	_bar_bg = _quad(BAR_W, BAR_H, Color(0, 0, 0, 0.75))
	_bar_bg.position.y = 1.96
	add_child(_bar_bg)
	_bar = _quad(BAR_W, BAR_H * 0.7, Color(0.7, 0.08, 0.08))
	_bar.position.y = 1.96
	add_child(_bar)
	_set_sheet()


func _quad(w: float, h: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	mi.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = true
	m.render_priority = 2 if h < BAR_H else 1
	mi.material_override = m
	return mi


func set_gear(g: Dictionary) -> void:
	gear = g
	_sheet = ""
	if _anim != null:
		_set_sheet()


func _set_sheet() -> void:
	## the Amazon in her own gear when the layer sheets are exported
	## (gear_sheets.gd), else the bare sheet for the pose:
	## am_<mode>_<weapon class>, falling back to the unarmed and then the
	## bow set when the export lacks one
	if not gear.is_empty():
		var key: String = GearSheets.sheet_for(gear, mode)
		if key != "":
			if key != _sheet:
				_anim.play(key, mode != "dt")
				_sheet = key
			return
	for wc in [wclass, "hth", "bow"]:
		for md in [mode, "nu"]:
			var rel := "amazon/am_%s_%s" % [md, wc]
			if rel == _sheet:
				return
			if _db.load_sheet(rel) != null:
				_anim.play(rel, md != "dt")
				_sheet = rel
				return


func apply_pose(a: Array, keep_mode := false) -> void:
	## [x, y, z, yaw, pitch, mode, weapon class]
	if a.size() < 7:
		return
	_target = Vector3(float(a[0]), float(a[1]), float(a[2]))
	_yaw = float(a[3])
	if a.size() >= 8 and float(a[7]) >= 0.0:
		_life = clampf(float(a[7]), 0.0, 1.0)
		if _bar != null:
			_bar.scale.x = maxf(0.01, _life)
			# scaled about the centre: slide it left so it empties rightward
			_bar.position.x = -BAR_W * 0.5 * (1.0 - _life)
	if not _have_pose:
		global_position = _target
		_have_pose = true
	var m := str(a[5])
	var wc := str(a[6])
	if not keep_mode and (m != mode or wc != wclass):
		mode = m
		wclass = wc
		_set_sheet()
	elif keep_mode and wc != wclass:
		wclass = wc
		_set_sheet()


func struck(dmg: float, ar: float, mlevel: int, impact_kind: String,
		missile: bool, etype: String) -> void:
	## A creature's blow at this player: their machine rolls the defence
	Net.strike_player.rpc_id(peer_id, dmg, ar, mlevel, impact_kind, missile, etype)


func _process(dt: float) -> void:
	if not _have_pose:
		return
	global_position = global_position.lerp(_target, minf(1.0, 14.0 * dt))
	# the sprite faces where she looks; a stand pose reads its row from it
	_anim.facing = _yaw + PI
	if _label.text != pname:
		_label.text = pname
