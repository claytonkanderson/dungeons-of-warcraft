extends Node3D
## The way on: opens where a dungeon's final boss fell and leads to the
## next dungeon on the ladder. Drawn here (a ring of light, a veil, a
## glow) since neither game ships a portal this build can reach; E within
## reach takes the player through, and in co-op the host's step takes
## everyone (world.gd travels, net.gd carries the party).

var did := ""                    # the dungeon it leads to ("" when the ladder is done)
var _ring: MeshInstance3D
var _veil: MeshInstance3D
var _t := 0.0


func setup(next_id: String, next_name: String) -> void:
	did = next_id
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.05
	torus.outer_radius = 1.25
	_ring.mesh = torus
	_ring.rotation.x = PI * 0.5
	_ring.position.y = 1.3
	_ring.material_override = _glow(Color(0.35, 0.75, 1.0), 1.0, 2.5)
	add_child(_ring)
	_veil = MeshInstance3D.new()
	var disc := QuadMesh.new()
	disc.size = Vector2(2.1, 2.4)
	_veil.mesh = disc
	_veil.position.y = 1.3
	_veil.material_override = _glow(Color(0.2, 0.5, 1.0), 0.45, 1.2)
	add_child(_veil)
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 0.7, 1.0)
	light.light_energy = 3.0
	light.omni_range = 7.0
	light.position.y = 1.4
	add_child(light)
	var label := Label3D.new()
	label.text = ("To " + next_name) if next_id != "" else "The ladder is climbed"
	label.font_size = 44
	label.pixel_size = 0.006
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = Color(0.75, 0.9, 1.0)
	label.outline_modulate = Color(0, 0, 0)
	label.outline_size = 10
	label.position.y = 2.9
	add_child(label)


func _glow(color: Color, alpha: float, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _process(dt: float) -> void:
	_t += dt
	if _ring != null:
		_ring.rotation.z += dt * 0.8
		_ring.scale = Vector3.ONE * (1.0 + 0.04 * sin(_t * 3.0))
	if _veil != null:
		# the veil faces whoever looks at it, the ring stays flat to the wall
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var to := cam.global_position - _veil.global_position
			to.y = 0.0
			if to.length() > 0.01:
				_veil.look_at(_veil.global_position + to, Vector3.UP)
