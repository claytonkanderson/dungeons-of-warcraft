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
var _target := Vector3.ZERO
var _yaw := 0.0
var _have_pose := false
var _anim: BillboardAnim
var _label: Label3D
var _sheet := ""

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
	_set_sheet()


func _set_sheet() -> void:
	## the Amazon sheet for the pose: am_<mode>_<weapon class>, falling back
	## to the unarmed and then the bow set when the export lacks one
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
