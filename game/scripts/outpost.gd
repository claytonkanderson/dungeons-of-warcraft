extends Node3D
## The Outpost: a goblin who gambles and buys, and a chest that is the
## stash, a few steps into every dungeon from the entrance, one to each
## side of the way in. Both are the WoW client's own models (the pipeline's
## build_outpost.py exports them once, to assets/wow/outpost); with the
## folder missing they are plain stand-ins so the dungeon still works.
## E on the goblin opens his talk menu (npc_menu.gd), E on the chest the
## stash (stash_ui.gd); world.gd owns both.

const VENDOR_NAME := "Fizzwick"
const VENDOR_TITLE := "Fizzwick the Gambler"
const STASH_TITLE := "Your Stash"

var vendor: Node3D
var stash: Node3D
var _to_settle: Array = []          # nodes still to be dropped onto the floor


func setup(spawn: Vector3, yaw: float) -> void:
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var side := Vector3(cos(yaw), 0.0, -sin(yaw))
	var dir := Paths.asset("wow/outpost")
	vendor = _model(dir.path_join("vendor.glb"), true)
	vendor.position = spawn + fwd * 2.2 + side * 1.9
	_face(vendor, spawn)
	_label(vendor, VENDOR_NAME, 2.05, Color(0.95, 0.85, 0.4))
	_body(vendor, 0.42, 1.4)
	# the client's treasure chest is a metre and a half wide; a chest by
	# the door is two thirds of that, and a step further out of the way in
	stash = _model(dir.path_join("stash.glb"), false)
	stash.scale = Vector3.ONE * 0.7
	stash.position = spawn + fwd * 2.4 - side * 2.1
	_face(stash, spawn)
	_label(stash, "Stash", 1.9, Color(0.75, 0.9, 1.0))
	_body(stash, 0.9, 1.3)
	_to_settle = [vendor, stash]


func _model(path: String, animated: bool) -> Node3D:
	var node: Node3D = null
	if FileAccess.file_exists(path):
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		if doc.append_from_file(path, state) == OK:
			node = doc.generate_scene(state)
	if node == null:
		push_warning("outpost: %s missing; a stand-in" % path)
		node = _stand_in(animated)
	add_child(node)
	if animated:
		var anim := _anim_player(node)
		if anim != null:
			var clip := ""
			for c in ["Stand", "Stand.001"]:
				if anim.has_animation(c):
					clip = c
					break
			if clip != "":
				anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
				anim.play(clip)
	return node


func _stand_in(tall: bool) -> Node3D:
	## no model: a dark post for the goblin, a low block for the chest
	var n := Node3D.new()
	var m := MeshInstance3D.new()
	if tall:
		var cap := CapsuleMesh.new()
		cap.radius = 0.35
		cap.height = 1.3
		m.mesh = cap
		m.position.y = 0.65
	else:
		var box := BoxMesh.new()
		box.size = Vector3(1.1, 0.7, 0.7)
		m.mesh = box
		m.position.y = 0.35
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.2, 0.15)
	m.material_override = mat
	n.add_child(m)
	return n


func _anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var found := _anim_player(c)
		if found != null:
			return found
	return null


func _face(node: Node3D, at: Vector3) -> void:
	var to := at - node.position
	to.y = 0.0
	if to.length() > 0.01:
		node.rotation.y = atan2(-to.x, -to.z)


func _label(node: Node3D, text: String, height: float, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 40
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = color
	label.outline_modulate = Color(0, 0, 0)
	label.outline_size = 10
	label.position.y = height
	node.add_child(label)


func _body(node: Node3D, radius: float, height: float) -> void:
	## solid, so nobody walks through the goblin or the chest
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = height
	shape.shape = cyl
	shape.position.y = height * 0.5
	body.add_child(shape)
	node.add_child(body)


func extent(node: Node3D) -> AABB:
	## the model's bounds in its own space (for the probe's report)
	var box := AABB()
	var first := true
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var t := node.global_transform.affine_inverse() * mi.global_transform
			var b := t * mi.mesh.get_aabb()
			box = b if first else box.merge(b)
			first = false
		for c in n.get_children():
			stack.append(c)
	return box


func _physics_process(_dt: float) -> void:
	## onto the floor, once the world's collision is in: a ray from a little
	## above each one's feet, down
	if _to_settle.is_empty():
		set_physics_process(false)
		return
	var space := get_world_3d().direct_space_state
	for n in _to_settle:
		var node: Node3D = n
		var from: Vector3 = node.global_position + Vector3(0, 0.6, 0)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -4.0, 0))
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			node.global_position.y = float(hit["position"].y)
	_to_settle.clear()
