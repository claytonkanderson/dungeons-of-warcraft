extends Node3D
## The Deadmines: WoW instance geometry (WMOs + doodads from placements.json),
## D2 Amazon gameplay on top — combat, skills, loot, UI, save/load.
## Verification: -- --shots=<dir> screenshots the spawn; --combat-test runs
## a scripted bow fight; --at=x,y,z overrides the spawn point.

const ASSETS := "res://../assets"          # D2 data (items, ui, amazon, sounds)
const ARROW_SPEED := 24.0

var wow_dir := ""                          # assets/wow/deadmines (absolute)
var player: Player
var spawn := Vector3(0, 2, 0)
var spawn_yaw := 0.0
var floor_y := -200.0
var monsters: Array = []
var arrows: Array = []
var enemy_missiles: Array = []
var ground_items: Array = []
var friendlies: Array = []
var hud_node: HUD
var inv_ui: InventoryUI
var tree_ui: SkillTreeUI
var char_ui: CharSheet
var force_labels := false
var _shot_dir := ""
var _at_override := Vector3.INF


func _assets_dir() -> String:
	var proj := ProjectSettings.globalize_path("res://")
	if proj.ends_with("/"):
		proj = proj.substr(0, proj.length() - 1)
	return proj.get_base_dir().path_join("assets")


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d != null else {}


func _ready() -> void:
	add_to_group("world")
	wow_dir = _assets_dir().path_join("wow/deadmines")
	var gs := get_node("/root/GameState")
	if not gs.session_loaded:
		gs.session_loaded = true
		var loaded := false
		if not OS.get_cmdline_user_args().has("--fresh"):
			loaded = gs.load_game(null)
		if not loaded:
			gs.grant_starter_kit()
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with("--shots="):
			_shot_dir = str(a).substr(8)
		elif str(a).begins_with("--at="):
			var p := str(a).substr(5).split(",")
			_at_override = Vector3(float(p[0]), float(p[1]), float(p[2]))

	_lighting()
	var placements := _load_json(wow_dir.path_join("placements.json"))
	if placements.is_empty():
		push_error("missing placements.json — run the pipeline")
		return
	_build_world(placements)
	if placements.has("spawn"):
		var sp: Array = placements.spawn["pos"]
		spawn = Vector3(sp[0], sp[1] + 0.5, sp[2])
		spawn_yaw = float(placements.spawn["yaw"])
	if _at_override != Vector3.INF:
		spawn = _at_override
	_spawn_player(gs)
	_spawn_creatures(placements.get("creatures", []))

	hud_node = HUD.new()
	add_child(hud_node)
	player.hud = hud_node
	inv_ui = InventoryUI.new()
	add_child(inv_ui)
	tree_ui = SkillTreeUI.new()
	add_child(tree_ui)
	char_ui = CharSheet.new()
	add_child(char_ui)
	player.action_skill = [str(gs._saved_action[0]), str(gs._saved_action[1])]
	hud_node.show_area("The Deadmines")
	# WASAPI init fails intermittently on this machine (sleepy BT headset as
	# the default device) and Godot falls back to a silent dummy driver —
	# surface it instead of letting the session be quietly mute
	var devs := AudioServer.get_output_device_list()
	if devs.is_empty() or (devs.size() == 1
			and str(devs[0]).to_lower().contains("dummy")):
		hud_node.show_area("Audio device failed - game will be silent\n(check the Windows default output device, then restart)",
				Color(1.0, 0.55, 0.3), 8.0)
	var timer := Timer.new()
	timer.wait_time = 15.0
	timer.timeout.connect(func(): gs.save_game(player))
	add_child(timer)
	timer.start()
	gs.equip_refused.connect(func(reason): hud_node.show_area(reason))
	gs.equipment_changed.connect(player.refresh_attack_style)
	player.refresh_attack_style()

	if _shot_dir != "":
		await _spawn_shots()
		get_tree().quit()
	elif OS.get_cmdline_user_args().has("--combat-test"):
		await _combat_test()
		get_tree().quit()
	elif OS.get_cmdline_user_args().has("--ui-test"):
		await _ui_test()
		get_tree().quit()
	elif OS.get_cmdline_user_args().has("--fps-probe"):
		print("audio devices: ", AudioServer.get_output_device_list(),
				" current: ", AudioServer.output_device,
				" mix_rate: ", AudioServer.get_mix_rate())
		for i in range(90):
			await get_tree().process_frame
		var t0 := Time.get_ticks_msec()
		for i in range(300):
			await get_tree().process_frame
		var dt := Time.get_ticks_msec() - t0
		print("fps over 300 frames: %.1f (engine says %.1f)"
				% [300000.0 / dt, Engine.get_frames_per_second()])
		get_tree().quit()


func _ui_test() -> void:
	var shots := ProjectSettings.globalize_path("res://../shots")
	DirAccess.make_dir_recursive_absolute(shots)
	var gs := get_node("/root/GameState")
	gs.hp = gs.hp_max * 0.65
	gs.mana = gs.mana_max * 0.4
	var gen := get_node("/root/ItemGen")
	for i in range(3):
		var inst: Dictionary = gen.roll_drop(10)
		gs.inv_try_add(str(inst.get("code", "")), inst)
	for i in range(8):
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots + "/ui_hud.png")
	char_ui.toggle()
	_sync_ui()
	for i in range(8):
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots + "/ui_char.png")
	char_ui.toggle()
	inv_ui.toggle()
	_sync_ui()
	for i in range(8):
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots + "/ui_inv.png")
	inv_ui.toggle()
	tree_ui.toggle()
	_sync_ui()
	for i in range(8):
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots + "/ui_tree.png")
	print("ui captures done")


func respawn_position() -> Vector3:
	return spawn


var _env: Environment


func _lighting() -> void:
	# WMO vertex colors carry the baked lighting; flat ambient reveals them
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.02, 0.02, 0.03)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.55, 0.55, 0.6)
	_env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)


func _outdoor_sky() -> void:
	## Night sky over the cove once terrain exists (WMOs stay unlit/baked).
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.04, 0.06, 0.12)
	sky_mat.sky_horizon_color = Color(0.22, 0.24, 0.32)
	sky_mat.ground_bottom_color = Color(0.02, 0.02, 0.04)
	sky_mat.ground_horizon_color = Color(0.18, 0.20, 0.26)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky


func _load_glb(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	if err != OK:
		push_error("failed to load %s (err %d)" % [path, err])
		return null
	return doc.generate_scene(state)


func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [node]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var found := _find_anim_player(c)
		if found:
			return found
	return null


func _build_world(placements: Dictionary) -> void:
	var mesh_count := 0
	var wmo_nodes: Dictionary = {}
	var cache: Dictionary = {}
	for w in placements.get("wmos", []):
		var glb: String = wow_dir.path_join(w["glb"])
		var node: Node3D
		if cache.has(glb):
			node = cache[glb].duplicate()
		else:
			node = _load_glb(glb)
			if node == null:
				continue
			cache[glb] = node
		node.position = Vector3(w["pos"][0], w["pos"][1], w["pos"][2])
		node.rotation.y = w["yaw"]
		add_child(node)
		wmo_nodes[int(w["uid"])] = node
		for mi in _find_meshes(node):
			mi.create_trimesh_collision()
			mesh_count += 1
	mesh_count += _place_set(placements.get("doodads", []), wmo_nodes)
	mesh_count += _place_set(placements.get("props", []), wmo_nodes)
	print("collision built for %d meshes" % mesh_count)

	# outdoor terrain + water from the ADT pass (optional; run build_terrain.py)
	var terr := _load_json(wow_dir.path_join("terrain/terrain.json"))
	if terr.has("tiles"):
		var t0 := Time.get_ticks_msec()
		for t in terr.tiles:
			var node := _load_glb(wow_dir.path_join("terrain/" + str(t)))
			if node == null:
				continue
			add_child(node)
			for mi in _find_meshes(node):
				mi.create_trimesh_collision()
		if str(terr.get("water", "")) != "":
			var wnode := _load_glb(wow_dir.path_join("terrain/" + str(terr.water)))
			if wnode != null:
				add_child(wnode)
		_outdoor_sky()
		print("terrain: %d tiles in %d ms" % [terr.tiles.size(),
				Time.get_ticks_msec() - t0])

	# fall-through guard from the main WMO's lowest group
	var meta := _load_json(wow_dir.path_join("deadmines_meta.json"))
	if meta.has("groups"):
		var lo := 1e9
		for g in meta.groups:
			lo = minf(lo, g["min"][1])
		floor_y = lo - 60.0


func _place_set(entries: Array, wmo_nodes: Dictionary) -> int:
	var cache: Dictionary = {}
	var collisions := 0
	var placed := 0
	for d in entries:
		var glb := wow_dir.path_join("doodads/%d.glb" % int(d["fdid"]))
		var node: Node3D
		var fresh := false
		if cache.has(glb):
			node = cache[glb].duplicate()
		elif FileAccess.file_exists(glb):
			node = _load_glb(glb)
			fresh = node != null
			if fresh:
				cache[glb] = node
		if node == null:
			continue
		var parent: Node3D = self
		if d.has("parent_uid"):
			parent = wmo_nodes.get(int(d["parent_uid"]), self)
		parent.add_child(node)
		node.position = Vector3(d["pos"][0], d["pos"][1], d["pos"][2])
		if d.has("quat"):
			node.quaternion = Quaternion(d["quat"][0], d["quat"][1],
					d["quat"][2], d["quat"][3]).normalized()
		elif d.has("yaw"):
			node.rotation.y = d["yaw"]
		var sc: float = d.get("scale", 1.0)
		node.scale = Vector3.ONE * sc
		placed += 1
		if fresh:  # duplicates inherit the collision children
			for mi in _find_meshes(node):
				if mi.get_aabb().get_longest_axis_size() * sc > 4.0:
					mi.create_trimesh_collision()
					collisions += 1
	print("placed %d instances (%d with collision)" % [placed, collisions])
	return collisions


func _spawn_player(gs) -> void:
	player = Player.new()
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	player.add_child(cs)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.fov = 70.0
	cam.far = 600.0
	cam.position.y = Player.EYE
	player.add_child(cam)
	player.position = spawn
	player.yaw = spawn_yaw
	if gs.saved_pos != Vector3.ZERO:
		player.position = gs.saved_pos
		player.yaw = gs.saved_yaw
		gs.saved_pos = Vector3.ZERO
	player.fire_action.connect(_on_fire)
	add_child(player)


func _spawn_creatures(entries: Array) -> void:
	var cinfo := _load_json(wow_dir.path_join("creatures/creatures.json"))
	var cache: Dictionary = {}
	var count := 0
	for c in entries:
		var key := str(int(c["entry"]))
		var glb := wow_dir.path_join("creatures/%s.glb" % key)
		if not FileAccess.file_exists(glb) or not cinfo.has(key):
			continue
		var info: Dictionary = cinfo[key]
		var model: Node3D
		if cache.has(glb):
			model = cache[glb].duplicate()
		else:
			model = _load_glb(glb)
			if model == null:
				continue
			cache[glb] = model
		var sc: float = float(info.get("scale", 1.0))
		model.scale = Vector3.ONE * sc

		# capsule sized from the model bounds
		var aabb := AABB()
		var first := true
		for mi in _find_meshes(model):
			var b := mi.get_aabb()
			if first:
				aabb = b
				first = false
			else:
				aabb = aabb.merge(b)
		var radius: float = clampf(
			maxf(aabb.size.x, aabb.size.z) * 0.5 * sc * 0.7, 0.3, 1.3)
		var height: float = clampf(aabb.size.y * sc, 1.0, 4.0)

		var mob := WowCreature.new()
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = radius
		cap.height = maxf(height, radius * 2.1)
		cs.shape = cap
		cs.position.y = cap.height * 0.5
		mob.add_child(cs)
		mob.add_child(model)
		mob.position = Vector3(c["pos"][0], c["pos"][1] + 0.2, c["pos"][2])
		mob.rotation.y = float(c["yaw"])
		add_child(mob)
		mob.setup(str(info.get("name", key)), info, _find_anim_player(model),
				radius)
		mob.target = player
		mob.died.connect(_on_monster_died)
		monsters.append(mob)
		count += 1
	print("creatures placed: %d" % count)


func combat_targets() -> Array:
	var out := [player]
	for f in friendlies.duplicate():
		if not is_instance_valid(f):
			friendlies.erase(f)
		else:
			out.append(f)
	return out


# ---------------------------------------------------------------------------
# Combat: the D2 Amazon arsenal (ported from the D2 Billboard prototype)
# ---------------------------------------------------------------------------
func spawn_enemy_missile(origin: Vector3, dir: Vector3, mob: WowCreature) -> void:
	var node := BillboardAnim.new()
	add_child(node)
	node.play("missiles/" + mob.ranged_cel, true, "center")
	node.global_position = origin + dir * 0.8
	node.facing = atan2(dir.x, dir.z)
	var dmg := randf_range(float(mob.stats.get("A1MinD", 5)),
			float(mob.stats.get("A1MaxD", 10)))
	enemy_missiles.append({"node": node, "vel": dir * mob.ranged_vel,
			"life": 2.6, "dmg": dmg, "etype": mob.ranged_etype,
			"ar": float(mob.stats.get("A1TH", 40)) + mob.mlevel * 5.0,
			"mlvl": mob.mlevel, "explode": mob.ranged_explode})


func _update_enemy_missiles(dt: float) -> void:
	if enemy_missiles.is_empty():
		return
	var gs := get_node("/root/GameState")
	for m in enemy_missiles.duplicate():
		var node: BillboardAnim = m["node"]
		node.global_position += m["vel"] * dt
		m["life"] -= dt
		var to_p := player.global_position + Vector3(0, 1.0, 0) - node.global_position
		if to_p.length() < 0.85:
			var chance := GameState.chance_to_hit(m["ar"], 25.0 + gs.player_defense(),
					int(m["mlvl"]), gs.level)
			if randf() < chance and randf() >= gs.avoid_chance():
				var resf: float = 1.0 - gs.resist(str(m["etype"])) / 100.0
				var dmg: float = m["dmg"] * resf
				get_node("/root/Sfx").event("player_gethit", node.global_position, 0.4)
				if gs.take_damage(dmg) and player.has_method("die"):
					player.die()
			m["life"] = 0.0
		if m["life"] <= 0.0:
			if str(m.get("explode", "")) != "":
				var boom := BillboardAnim.new()
				add_child(boom)
				boom.play("missiles/" + str(m["explode"]), false, "center")
				boom.global_position = node.global_position
				boom.finished.connect(boom.queue_free)
				get_node("/root/Sfx").event("fire_impact", node.global_position)
			enemy_missiles.erase(m)
			node.queue_free()


func _skill_impact(a: Dictionary, pos: Vector3) -> void:
	## Area effects on arrow impact.
	var gs := get_node("/root/GameState")
	var sk := str(a.get("skill", ""))
	var lvl := maxi(1, gs.skill_level(sk))
	var radius := 0.0
	match sk:
		"Exploding Arrow": radius = 2.5
		"Immolation Arrow": radius = 3.0
		"Freezing Arrow": radius = 3.0
	if radius <= 0.0:
		return
	for mob in monsters:
		if not (mob is WowCreature) or mob.state == WowCreature.State.DEAD:
			continue
		if mob.global_position.distance_to(pos) > radius:
			continue
		if sk == "Freezing Arrow":
			mob.slow(2.0 + 0.4 * lvl, 0.25)
			mob.take_damage((4.0 + 3.0 * lvl) * GameState.DMG_MULT / 5.0)
		else:
			mob.take_damage((3.0 + 4.0 * lvl) * GameState.DMG_MULT / 5.0)
			if sk == "Immolation Arrow":
				mob.burn(4.0 * lvl * GameState.DMG_MULT / 5.0, 3.0)


func _melee_swing(origin: Vector3, dir: Vector3) -> void:
	var gs := get_node("/root/GameState")
	var sfx := get_node("/root/Sfx")
	sfx.event("staff_swing" if player.weapon_class == "stf" else "melee_swing", origin)
	var flat_dir := Vector3(dir.x, 0, dir.z).normalized()
	var connected := false
	for mob in monsters:
		if not (mob is WowCreature) or mob.state == WowCreature.State.DEAD:
			continue
		var to: Vector3 = mob.global_position - player.global_position
		to.y = 0.0
		if to.length() > 3.0 + mob.attack_range - 2.0:
			continue
		if flat_dir.angle_to(to.normalized()) > 0.9:
			continue
		var chance := GameState.chance_to_hit(
			gs.attack_rating(), mob.defense, gs.level, mob.mlevel)
		if randf() < chance:
			var wd: Vector2 = gs.weapon_damage()
			mob.take_damage(randf_range(wd.x, wd.y)
					+ gs.gear_elemental() * GameState.DMG_MULT)
			if not connected:
				connected = true
				sfx.event("blade_impact", mob.global_position)


func _on_fire(slot: int, origin: Vector3, dir: Vector3) -> void:
	var gs := get_node("/root/GameState")
	var skill: String = player.action_skill[slot]
	# summons cast with any weapon
	if skill in ["Decoy", "Dopplezon", "Valkyrie"]:
		var cost: float = gs.mana_cost(skill)
		if gs.mana < cost:
			return
		gs.mana -= cost
		var lvl: int = maxi(1, gs.skill_level(skill))
		var at := origin + dir * 3.0
		at.y = player.global_position.y
		var kind := "valkyrie" if skill == "Valkyrie" else "decoy"
		for f in friendlies.duplicate():
			if is_instance_valid(f) and f.kind == kind:
				f.queue_free()
				friendlies.erase(f)
		friendlies.append(Ally.spawn(self, at, kind, lvl))
		return
	if player.melee:
		var mcost: float = gs.mana_cost(skill)
		var mskill := skill
		if gs.mana < mcost:
			mskill = "Attack"
		else:
			gs.mana -= mcost
		var mlvl: int = maxi(1, gs.skill_level(mskill))
		match mskill:
			"Jab", "Fend":
				for k in range(2 + mini(mlvl / 3, 3)):
					get_tree().create_timer(0.09 * k).timeout.connect(
						_melee_swing.bind(origin, dir))
			"Power Strike", "Charged Strike":
				_melee_swing(origin, dir)
				for mob in monsters:
					if mob is WowCreature and mob.state != WowCreature.State.DEAD \
							and mob.global_position.distance_to(
								player.global_position) < 4.0:
						mob.take_damage((3.0 + 3.0 * mlvl) * GameState.DMG_MULT / 5.0)
			"Poison Javelin", "Plague Javelin":
				_melee_swing(origin, dir)
				for mob in monsters:
					if mob is WowCreature and mob.state != WowCreature.State.DEAD \
							and mob.global_position.distance_to(
								player.global_position) < 5.0:
						mob.burn((2.0 + 2.0 * mlvl) * GameState.DMG_MULT / 5.0, 4.0)
			_:
				_melee_swing(origin, dir)
		return
	if skill == "Strafe":
		var cost2: float = gs.mana_cost(skill)
		if gs.mana >= cost2:
			gs.mana -= cost2
			var lvl2: int = maxi(1, gs.skill_level(skill))
			var shots := 0
			for mob in monsters:
				if shots >= 2 + lvl2:
					break
				if mob is WowCreature and mob.state != WowCreature.State.DEAD:
					var to: Vector3 = mob.global_position + Vector3(0, 0.9, 0) - origin
					if to.length() < 30.0 and to.normalized().dot(dir) > 0.0:
						_launch_arrow(gs, "Attack", origin, to.normalized())
						shots += 1
			if shots > 0:
				return
	var cost: float = gs.mana_cost(skill)
	if gs.mana < cost:
		skill = "Attack"        # D2 falls back to normal attack when oom
		cost = 0.0
	gs.mana -= cost
	var lvl: int = maxi(1, gs.skill_level(skill))
	var count := 1
	if skill == "Multiple Shot":
		count = 1 + lvl
	for i in range(count):
		var spread := 0.0
		if count > 1:
			spread = deg_to_rad(-4.0 * (count - 1) * 0.5 + 4.0 * i)
		_launch_arrow(gs, skill, origin, dir.rotated(Vector3.UP, spread))


func _launch_arrow(gs, skill: String, origin: Vector3, d2: Vector3) -> void:
	var lvl: int = maxi(1, gs.skill_level(skill))
	var gd: Dictionary = get_node("/root/SpriteDB").gamedata()
	var srow: Dictionary = gs.skill_row(skill)
	# resolve missile art + explosion through missiles.txt
	var cel := "arrow"
	var explode := ""
	var mis := str(srow.get("srvmissile", "")).strip_edges()
	if mis == "":
		mis = str(srow.get("srvmissilea", "")).strip_edges()
	var mrow: Dictionary = gd.get("missiles", {}).get(mis, {})
	if not mrow.is_empty():
		var cf := str(mrow.get("CelFile", "")).strip_edges().to_lower()
		if cf != "":
			if get_node("/root/SpriteDB").load_sheet("missiles/" + cf) != null:
				cel = cf
			elif cf.contains("lightning") and get_node("/root/SpriteDB") \
					.load_sheet("missiles/lightningbolt") != null:
				cel = "lightningbolt"   # javelin-tree bolts reuse the bolt art
		var ex := str(mrow.get("ExplosionMissile", "")).strip_edges()
		if ex != "":
			var xrow: Dictionary = gd.get("missiles", {}).get(ex, {})
			var xcf := str(xrow.get("CelFile", "")).strip_edges().to_lower()
			if xcf != "" and get_node("/root/SpriteDB").load_sheet("missiles/" + xcf) != null:
				explode = xcf
	if skill in ["Exploding Arrow", "Immolation Arrow"] and explode == "":
		explode = "exparrowexplode"
	elif skill == "Freezing Arrow" and explode == "":
		explode = "icearrowexplode"
	var etype := str(srow.get("EType", "")).strip_edges()
	var escale := 1.0 + 0.5 * (lvl - 1)
	var edmg := Vector2(float(str(srow.get("EMin", "0")).to_int()),
			float(str(srow.get("EMax", "0")).to_int())) * escale
	var arrow := BillboardAnim.new()
	add_child(arrow)
	arrow.play("missiles/" + cel, true, "center")
	arrow.global_position = origin + d2 * 0.5
	arrow.facing = atan2(d2.x, d2.z)
	arrows.append({"node": arrow, "vel": d2 * ARROW_SPEED, "life": 3.0,
			"skill": skill, "edmg": edmg, "etype": etype, "explode": explode,
			"homing": skill == "Guided Arrow"})
	get_node("/root/Sfx").event(
		"xbow_fire" if player.weapon_class == "xbw" else "bow_fire", origin)


func _physics_process(dt: float) -> void:
	_update_enemy_missiles(dt)
	if player != null and player.global_position.y < floor_y:
		player.global_position = spawn
		player.velocity = Vector3.ZERO
	if arrows.is_empty():
		return
	var gs := get_node("/root/GameState")
	var space := get_world_3d().direct_space_state
	for a in arrows.duplicate():
		var node: BillboardAnim = a["node"]
		# Guided Arrow homes on the nearest living creature
		if a.get("homing", false):
			var best: WowCreature = null
			var bd := 30.0
			for mob in monsters:
				if mob is WowCreature and mob.state != WowCreature.State.DEAD:
					var dm: float = node.global_position.distance_to(mob.global_position)
					if dm < bd:
						bd = dm
						best = mob
			if best != null:
				var want: Vector3 = (best.global_position + Vector3(0, 0.9, 0)
						- node.global_position).normalized() * ARROW_SPEED
				a["vel"] = a["vel"].lerp(want, 6.0 * dt)
				node.facing = atan2(a["vel"].x, a["vel"].z)
		var from: Vector3 = node.global_position
		var to: Vector3 = from + a["vel"] * dt
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = [player.get_rid()]
		var hit := space.intersect_ray(q)
		if hit:
			var col: Object = hit["collider"]
			if col is WowCreature and col.state != WowCreature.State.DEAD:
				# an arrow that physically connects always hits — the FPS aim
				# replaces D2's attack-rating roll for missiles
				var wd: Vector2 = gs.weapon_damage()
				var dmg := randf_range(wd.x, wd.y)
				if randf() < gs.crit_chance():
					dmg *= 2.0
				dmg += gs.gear_elemental() * GameState.DMG_MULT
				var edmg: Vector2 = a.get("edmg", Vector2.ZERO)
				if edmg.y > 0.0:
					dmg += randf_range(edmg.x, edmg.y) * GameState.DMG_MULT
				var sk := str(a.get("skill", ""))
				if a.get("etype", "") == "cold":
					var factor := 0.25 if sk in ["Ice Arrow", "Freezing Arrow"] else 0.4
					col.slow(2.0 + 0.5 * gs.skill_level(sk), factor)
				if sk == "Immolation Arrow":
					col.burn(6.0 * gs.skill_level(sk) * GameState.DMG_MULT / 5.0, 3.0)
				col.take_damage(dmg)
				get_node("/root/Sfx").event("arrow_impact", hit["position"])
				_skill_impact(a, hit["position"])
				if randf() < gs.pierce_chance():
					continue    # arrow pierces through
			var explode := str(a.get("explode", ""))
			if explode != "":
				var boom := BillboardAnim.new()
				add_child(boom)
				boom.play("missiles/" + explode, false, "center")
				boom.global_position = hit["position"]
				boom.finished.connect(boom.queue_free)
			arrows.erase(a)
			node.queue_free()
			continue
		node.global_position = to
		a["life"] -= dt
		if a["life"] <= 0.0:
			arrows.erase(a)
			node.queue_free()


# ---------------------------------------------------------------------------
# Loot
# ---------------------------------------------------------------------------
func _on_monster_died(dead: WowCreature) -> void:
	# treasure-class flavour drops (gold, potions, bases)
	var tc := str(dead.stats.get("TC", ""))
	for res in get_node("/root/ItemDB").roll(tc):
		var gi := GroundItem.new()
		add_child(gi)
		var minst: Dictionary = {}
		if int(res["gold"]) == 0:
			minst = get_node("/root/ItemGen").maybe_magic(str(res["code"]), dead.mlevel)
		if minst.is_empty():
			gi.drop(res["code"], res["gold"])
		else:
			gi.drop_instance(minst)
		var a := randf() * TAU
		var r := randf_range(0.3, 1.0)
		gi.global_position = dead.global_position \
				+ Vector3(cos(a) * r, 0.02, sin(a) * r)
		ground_items.append(gi)
	get_node("/root/Sfx").event("flippy", dead.global_position)
	# guaranteed quality drops: one per kill, more for bosses, a shower
	# for the Kingpin himself
	var ndrops := 1
	if dead.is_final_boss:
		ndrops = 7
	elif dead.is_boss:
		ndrops = 2
	for di in range(ndrops):
		var inst: Dictionary = get_node("/root/ItemGen").roll_drop(dead.mlevel)
		if inst.is_empty():
			continue
		var qi := GroundItem.new()
		add_child(qi)
		qi.drop_instance(inst)
		var qa := randf() * TAU
		var qr := randf_range(0.5, 1.6) if ndrops > 1 else 0.7
		qi.global_position = dead.global_position \
				+ Vector3(cos(qa) * qr, 0.02, sin(qa) * qr)
		ground_items.append(qi)


func _pickup_nearest() -> void:
	var best: GroundItem = null
	var bd := 2.5
	for gi in ground_items:
		var d: float = player.global_position.distance_to(gi.global_position)
		if d < bd:
			bd = d
			best = gi
	if best == null:
		return
	var gs := get_node("/root/GameState")
	var sfx := get_node("/root/Sfx")
	if best.gold_amount > 0:
		gs.add_gold(best.gold_amount)
		sfx.event_ui("gold_drop")
	elif gs.is_potion(best.code) and gs.belt_add(best.code):
		sfx.event_ui("potion_belt")
	elif gs.inv_try_add(best.code, best.instance):
		sfx.event_ui("pickup")
	else:
		if hud_node != null:
			hud_node.show_area("Inventory full")
		return
	ground_items.erase(best)
	best.queue_free()


func _sync_ui() -> void:
	## One owner for mouse/look state: panels open -> visible cursor, no
	## attacks, no warp-look; all closed -> back to FPS control.
	var any_open: bool = (inv_ui != null and inv_ui.open) \
			or (tree_ui != null and tree_ui.open) \
			or (char_ui != null and char_ui.open)
	if player == null:
		return
	player.ui_locked = any_open
	player.look_enabled = not any_open
	if any_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		player._center_mouse()


func drop_entry(entry: Dictionary) -> void:
	## An item dragged out of the inventory lands at the amazon's feet.
	var gs := get_node("/root/GameState")
	gs.inv_items.erase(entry)
	var gi := GroundItem.new()
	add_child(gi)
	var inst: Dictionary = entry.get("inst", {})
	if inst.is_empty():
		gi.drop(str(entry.get("code", "")))
	else:
		gi.drop_instance(inst)
	var fwd: Vector3 = -player.global_transform.basis.z
	gi.global_position = player.global_position \
			+ Vector3(fwd.x, 0, fwd.z).normalized() * 1.2 + Vector3(0, 0.02, 0)
	ground_items.append(gi)
	get_node("/root/Sfx").event("flippy", gi.global_position)
	gs.inventory_changed.emit()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if e.keycode == KEY_E:
			_pickup_nearest()
		elif e.keycode >= KEY_1 and e.keycode <= KEY_4:
			get_node("/root/GameState").drink(e.keycode - KEY_1)
		elif e.keycode >= KEY_F1 and e.keycode <= KEY_F5:
			# skill hotkeys: swap the RMB skill (binding happens in the tree)
			if player != null and not player.ui_locked:
				var gsk := get_node("/root/GameState")
				var sk := str(gsk.hotkeys.get("F%d" % (e.keycode - KEY_F1 + 1), ""))
				if sk != "" and (sk == "Attack" or gsk.skill_level(sk) > 0):
					player.action_skill[1] = sk
					get_node("/root/Sfx").event_ui("button")
		elif e.keycode == KEY_F9:
			get_node("/root/GameState").save_game(player)
			if hud_node != null:
				hud_node.show_area("Saved")
		elif e.keycode == KEY_I:
			if inv_ui != null:
				inv_ui.toggle()
				_sync_ui()
				get_node("/root/Sfx").event_ui("button")
		elif e.keycode == KEY_T:
			if tree_ui != null:
				tree_ui.toggle()
				_sync_ui()
		elif e.keycode == KEY_C:
			if char_ui != null:
				char_ui.toggle()
				_sync_ui()
		elif e.keycode == KEY_ESCAPE:
			# Esc closes whatever panels are up before it ever frees the look
			var closed := false
			for panel in [inv_ui, tree_ui, char_ui]:
				if panel != null and panel.open:
					panel.toggle()
					closed = true
			if closed:
				_sync_ui()


func _process(_dt: float) -> void:
	if hud_node == null or player == null:
		return
	if (Input.is_key_pressed(KEY_ALT) or force_labels) and not ground_items.is_empty():
		var cam: Camera3D = player.get_node("Camera3D")
		hud_node.show_item_labels(ground_items, cam)
	else:
		hud_node.hide_item_labels()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_node("/root/GameState").save_game(player)
		get_tree().quit()


# ---------------------------------------------------------------------------
# Verification modes
# ---------------------------------------------------------------------------
func _spawn_shots() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	for k in 4:
		player.yaw = spawn_yaw + k * PI / 2.0
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			_shot_dir.path_join("spawn_%d.png" % k))
	print("spawn shots done")


func _combat_test() -> void:
	var shots := ProjectSettings.globalize_path("res://../shots/combat")
	DirAccess.make_dir_recursive_absolute(shots)
	if not OS.has_feature("movie"):
		Engine.max_fps = 60
	print("attack len=%.2f release=%.2f" % [player._attack_len, player.attack_release])
	var fired := 0
	var best: WowCreature = null
	for f in range(900):
		if best == null or best.state == WowCreature.State.DEAD \
				or player.global_position.distance_to(best.global_position) > 30.0:
			best = null
			var bd := 1e9
			for mob in monsters:
				if mob.state == WowCreature.State.DEAD or mob.passive:
					continue
				var d: float = player.global_position.distance_to(mob.global_position)
				if d < bd:
					bd = d
					best = mob
		if best != null:
			var lead: Vector3 = best.global_position \
					+ best.velocity * (player.global_position.distance_to(best.global_position) / ARROW_SPEED)
			var to := lead - player.global_position
			player.yaw = atan2(-to.x, -to.z)
			var eye := player.global_position + Vector3(0, Player.EYE, 0)
			var aim := lead + Vector3(0, 1.0, 0)
			player.pitch = atan2(aim.y - eye.y, Vector2(to.x, to.z).length())
			if player.attack_time <= 0.0:
				player._start_attack(0)
				fired += 1
			var horiz := Vector2(to.x, to.z).length()
			var dir3 := Vector3(to.x, 0, to.z).normalized()
			if horiz > 12.0:
				player.velocity.x = dir3.x * Player.WALK
				player.velocity.z = dir3.z * Player.WALK
				player.move_and_slide()
			elif horiz < 6.0:
				player.velocity.x = -dir3.x * Player.RUN
				player.velocity.z = -dir3.z * Player.RUN
				player.move_and_slide()
		await get_tree().physics_frame
		if f % 30 == 0 and best != null:
			print("f=%d atk=%.2f arrows=%d target=%s state=%d hp=%.0f dist=%.1f" % [
				f, player.attack_time, arrows.size(), best.cname, best.state,
				best.hp, player.global_position.distance_to(best.global_position)])
		if f % 20 == 0 and not OS.has_feature("movie"):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(
				shots + "/c_%03d.png" % (f / 20))
	# the loot moment: labels on, sweep the pile, admire the haul
	force_labels = true
	var guard := 0
	while not ground_items.is_empty() and guard < 1400:
		guard += 1
		var nearest: GroundItem = null
		var nd := 1e9
		for gi in ground_items:
			var d: float = player.global_position.distance_to(gi.global_position)
			if d < nd:
				nd = d
				nearest = gi
		if nearest == null:
			break
		var to := nearest.global_position - player.global_position
		to.y = 0.0
		player.yaw = lerp_angle(player.yaw, atan2(-to.x, -to.z), 0.15)
		player.pitch = lerpf(player.pitch, -0.4, 0.1)
		if to.length() > 1.8:
			var dir := to.normalized()
			player.velocity.x = dir.x * Player.WALK
			player.velocity.z = dir.z * Player.WALK
			player.move_and_slide()
		else:
			player.velocity = Vector3.ZERO
			_pickup_nearest()
			for w in range(18):
				await get_tree().physics_frame
		await get_tree().physics_frame
	force_labels = false
	player.pitch = 0.0
	inv_ui.toggle()
	_sync_ui()
	for f in range(240):
		await get_tree().physics_frame
	var alive := 0
	var dead := 0
	for mob in monsters:
		if mob.state == WowCreature.State.DEAD:
			dead += 1
	var gs := get_node("/root/GameState")
	var drops := []
	for gi in ground_items:
		drops.append(gi.display_name)
	print("combat test: fired %d arrows, %d dead, player hp %.0f, xp %d, level %d"
			% [fired, dead, gs.hp, gs.xp, gs.level])
	print("drops on ground: ", drops)
