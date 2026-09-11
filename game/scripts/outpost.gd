extends Node3D
## The Outpost's brazier, by every dungeon's entrance: a pedestal with a
## fire of gold and a light, E opens the shop (shop_ui.gd). Neither game
## ships a merchant this build can reach, so the place stands for one.

var _flame: MeshInstance3D
var _settled := false
var _t := 0.0


func setup() -> void:
	var stone := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.45
	cyl.bottom_radius = 0.6
	cyl.height = 1.0
	stone.mesh = cyl
	stone.position.y = 0.5
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # the caves are dim
	sm.albedo_color = Color(0.4, 0.36, 0.32)
	stone.material_override = sm
	add_child(stone)
	var bowl := MeshInstance3D.new()
	var b := CylinderMesh.new()
	b.top_radius = 0.7
	b.bottom_radius = 0.5
	b.height = 0.3
	bowl.mesh = b
	bowl.position.y = 1.15
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.albedo_color = Color(0.7, 0.55, 0.25)
	bowl.material_override = bm
	add_child(bowl)
	_flame = MeshInstance3D.new()
	var f := SphereMesh.new()
	f.radius = 0.4
	f.height = 0.9
	_flame.mesh = f
	_flame.position.y = 1.6
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.75, 0.25, 0.7)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.emission_enabled = true
	fm.emission = Color(1.0, 0.6, 0.15)
	fm.emission_energy_multiplier = 3.0
	_flame.material_override = fm
	add_child(_flame)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.4)
	light.light_energy = 3.5
	light.omni_range = 9.0
	light.position.y = 1.9
	add_child(light)
	var label := Label3D.new()
	label.text = "The Outpost\ngamble, respec, stash"
	label.font_size = 40
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(0.95, 0.85, 0.5)
	label.outline_modulate = Color(0, 0, 0)
	label.outline_size = 10
	label.position.y = 2.7
	add_child(label)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.6
	shape.height = 1.3
	cs.shape = shape
	cs.position.y = 0.65
	body.add_child(cs)
	add_child(body)


func _physics_process(dt: float) -> void:
	if not _settled:
		# onto the floor under the entrance, like a creature
		_settled = true
		# from knee height down: a pipe or a beam above must not catch it
		var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.6,
				global_position - Vector3.UP * 6.0)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit:
			global_position.y = float(hit["position"].y)
	_t += dt
	if _flame != null:
		_flame.scale = Vector3(1.0 + 0.08 * sin(_t * 7.0), 1.0 + 0.15 * sin(_t * 5.3), 1.0 + 0.08 * cos(_t * 6.1))
