extends Node3D
## One dungeon: WoW instance geometry (WMOs + doodads from placements.json)
## for GameState.current_dungeon, with D2 Amazon gameplay on top — combat,
## skills, loot, UI, save/load.
## Verification: -- --shots=<dir> screenshots the spawn; --combat-test runs
## a scripted bow fight; --at=x,y,z overrides the spawn point.

const ARROW_SPEED := 24.0

var wow_dir := ""                          # assets/wow/<dungeon-id> (absolute)
var player: Player
var spawn := Vector3(0, 2, 0)
var spawn_yaw := 0.0
var floor_y := -200.0
var monsters: Array = []
var arrows: Array = []
var enemy_missiles: Array = []
var ground_items: Array = []
var friendlies: Array = []
const INTERACT_RANGE := 3.2     # E reach; the HUD prompt uses it too, so what
                                # the prompt offers is exactly what E does
var doors: Array = []           # {name, node, open, rule}
var interactables: Array = []   # {kind, name, node, used}


func _spawn_gameobjects(placements: Dictionary) -> void:
	var rules: Dictionary = placements.get("door_rules", {})
	# Type-5 GENERIC gameobjects are decoration (tables, candelabra, cages) and
	# are not lootable — they were being treated as chests, which surfaced their
	# raw internal names ("Standing, Interior, Small - Val") and dropped free
	# gold. The exceptions are genuine reward containers that WoW happens to
	# model as GENERIC; the pipeline lists those per dungeon.
	var loot_generic := {}
	for n in placements.get("loot_generic", []):
		loot_generic[str(n)] = true
	var cache: Dictionary = {}
	for g in placements.get("gameobjects", []):
		# Levers are gone, so their models are never even loaded. Every one in
		# the Deadmines stood on the far side of the door it opened and could
		# only be reached by first getting through that door; doors open by
		# hand now, and a wall fixture that invites a click and does nothing is
		# worse than no fixture at all.
		if int(g["type"]) == 1:
			continue
		# Type 2 is QUESTGIVER: the "Mysterious <Dungeon> Chest" quest
		# containers. They are big, they look like loot, and they belong to a
		# quest this game does not have — not placed at all.
		if int(g["type"]) == 2:
			continue
		var glb := wow_dir.path_join("gobj/%d.glb" % int(g["fdid"]))
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
		add_child(node)
		node.position = Vector3(g["pos"][0], g["pos"][1], g["pos"][2])
		node.rotation.y = float(g["yaw"])
		var gname := str(g["name"])
		var gtype := int(g["type"])
		if gtype == 0:
			# a door is solid until something opens it
			if fresh:
				for mi in _find_meshes(node):
					mi.create_trimesh_collision()
			doors.append({"name": gname, "node": node, "open": false,
					"rule": rules.get(gname, {})})
			# Every door opens by hand. Its rule still fires as well, so a boss
			# kill and the cannon still swing their doors open from across the
			# room, but a rule is never the only way through: two Deadmines
			# doors have no opener in AzerothCore at all, so trusting the rules
			# sealed the dungeon.
			interactables.append({"kind": "door", "name": gname,
					"node": node, "used": false})
		elif gtype == 10 and gname.containsn("cannon"):
			interactables.append({"kind": "cannon", "name": gname,
					"node": node, "used": false})
		elif gname.containsn("vein"):
			interactables.append({"kind": "vein", "name": gname,
					"node": node, "used": false})
		elif gtype in [2, 3, 25] or (gtype == 5 and loot_generic.has(gname)):
			interactables.append({"kind": "chest", "name": gname,
					"node": node, "used": false})

	print("gameobjects: %d doors, %d interactables" %
			[doors.size(), interactables.size()])


func _open_door(d: Dictionary, boom := false) -> void:
	if d["open"]:
		return
	d["open"] = true
	var node: Node3D = d["node"]
	for mi in _find_meshes(node):
		for b in mi.get_children():
			if b is StaticBody3D:
				b.set_collision_layer_value(1, false)
	get_node("/root/WowSfx").impact("wood", node.global_position)
	if boom:
		get_node("/root/Sfx").event("fire_impact", node.global_position)
	var tw := create_tween()
	tw.tween_property(node, "rotation:y", node.rotation.y + 1.85, 1.1) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if hud_node != null:
		hud_node.show_area("%s opens" % d["name"], Color(0.9, 0.82, 0.6), 2.5)


func _try_interact() -> bool:
	var gs := get_node("/root/GameState")
	for it in interactables:
		if it["used"]:
			continue
		var node: Node3D = it["node"]
		if player.global_position.distance_to(node.global_position) > INTERACT_RANGE:
			continue
		var pos := node.global_position
		match str(it["kind"]):
			"door":
				for d in doors:
					if d["node"] == node:
						_open_door(d)
				it["used"] = true
			"cannon":
				it["used"] = true
				get_node("/root/Sfx").event("fire_impact", pos)
				for d in doors:
					if not d["open"] and str(d.get("rule", {})
							.get("cannon", "")) == str(it["name"]):
						_open_door(d, true)
			"chest":
				it["used"] = true
				get_node("/root/Sfx").event_ui("pickup")
				# D2's chest class for the act; the big reward chests roll it
				# twice and floor at magic like a champion's drop
				var db := get_node("/root/ItemDB")
				var gen := get_node("/root/ItemGen")
				var big: bool = str(it["name"]).containsn("smite") \
						or str(it["name"]).containsn("mysterious")
				var tc: String = db.tc_for(gs.level, "chest")
				for i in range(2 if big else 1):
					for res in db.roll(tc, gs.level):
						var qi := GroundItem.new()
						add_child(qi)
						if int(res["gold"]) > 0:
							qi.drop("gold", int(res["gold"]))
						else:
							var inst: Dictionary = gen.roll_item(str(res["code"]), gs.level,
									db.quality_bonus(tc, "chest"), "magic" if big else "")
							if inst.is_empty():
								qi.drop(res["code"], 0)
							else:
								qi.drop_instance(inst)
						qi.global_position = pos + Vector3(
								randf_range(-0.6, 0.6), 0.05, randf_range(-0.6, 0.6))
						ground_items.append(qi)
			"vein":
				it["used"] = true
				get_node("/root/WowSfx").impact("wood", pos, 0.8)
				var vg := GroundItem.new()
				add_child(vg)
				vg.drop("gold", randi_range(30, 90))
				vg.global_position = pos + Vector3(0, 0.05, 0.3)
				ground_items.append(vg)
		return true
	return false
var hud_node: HUD
var inv_ui: InventoryUI
var tree_ui: SkillTreeUI
var char_ui: CharSheet
var menu_ui: MenuUI
var force_labels := false
var _shot_dir := ""
var _at_override := Vector3.INF


func _assets_dir() -> String:
	return Paths.root()


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d != null else {}


func _ready() -> void:
	add_to_group("world")
	var gs := get_node("/root/GameState")
	if not gs.session_loaded:
		gs.session_loaded = true
		var loaded := false
		if not OS.get_cmdline_user_args().has("--fresh"):
			loaded = gs.load_game(null)
		if not loaded:
			gs.grant_starter_kit()
	# CLI flags are read after the load, not before: load_game restores
	# its own current_dungeon, which used to win over a requested one and
	# leave the geometry and the game state naming different dungeons.
	Cli.warn_unknown()
	var did := Cli.value("--dungeon=")
	if did != "":
		var dg := get_node("/root/Dungeons")
		if dg.entry(did).is_empty():
			printerr("unknown dungeon '%s' — staying in %s." % [did, gs.current_dungeon])
		elif not dg.built(did):
			printerr("dungeon '%s' is not built yet — staying in %s."
					% [did, gs.current_dungeon])
		else:
			gs.current_dungeon = did
	_shot_dir = Cli.value("--shots=")
	_at_override = Cli.vec3("--at=", Vector3.INF)
	if OS.get_cmdline_user_args().has("--loot-test"):
		# pure table work: no world needed, so it runs before the build
		if Cli.offscreen():
			Cli.hide_window()
		_loot_test()
		get_tree().quit()
		return
	wow_dir = _assets_dir().path_join("wow/%s" % gs.current_dungeon)

	# loading screen: the dungeon's backdrop and name while the world builds.
	# Everything below is synchronous, so yield two frames first so it draws
	# instead of the player staring at a frozen frame for the load.
	var loading := _loading_screen(str(gs.current_dungeon))
	await get_tree().process_frame
	await get_tree().process_frame

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
	player.surface = str(placements.get("footstep", "stone"))
	_spawn_creatures(placements.get("creatures", []))
	_spawn_gameobjects(placements)

	hud_node = HUD.new()
	add_child(hud_node)
	player.hud = hud_node
	loading.queue_free()
	inv_ui = InventoryUI.new()
	add_child(inv_ui)
	tree_ui = SkillTreeUI.new()
	add_child(tree_ui)
	char_ui = CharSheet.new()
	add_child(char_ui)
	menu_ui = MenuUI.new()
	menu_ui.world = self
	add_child(menu_ui)
	player.action_skill = [str(gs._saved_action[0]), str(gs._saved_action[1])]
	hud_node.show_area(get_node("/root/Dungeons").display_name(gs.current_dungeon))
	get_node("/root/Music").set_dungeon(str(gs.current_dungeon))
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

	# every verification mode keeps the window minimized under --offscreen,
	# so probes can run while the machine is in use
	if Cli.offscreen():
		Cli.hide_window()
	if _shot_dir != "":
		await _spawn_shots()
		get_tree().quit()
	elif OS.get_cmdline_user_args().has("--combat-test"):
		await _combat_test()
		get_tree().quit()
	elif OS.get_cmdline_user_args().has("--ui-test"):
		await _ui_test()
		get_tree().quit()
	elif OS.get_cmdline_user_args().has("--item-test"):
		await _item_test()
		get_tree().quit()
	elif Cli.value("--mob-shot=") != "":
		# stand in front of the first creature of this entry, capture it, kill
		# it, capture what remains
		var want := Cli.value("--mob-shot=").to_int()
		var target_mob: WowCreature = null
		for mob in monsters:
			if mob is WowCreature and int(mob.stats.get("entry", mob.get_meta("entry", -1))) == want:
				target_mob = mob
				break
		if target_mob == null:
			for mob in monsters:
				if mob is WowCreature and mob.cname == Cli.value("--mob-name=", "?"):
					target_mob = mob
					break
		if target_mob == null:
			print("MOB-SHOT: entry %d not found" % want)
		else:
			var dir_out := Basis(Vector3.UP, target_mob.rotation.y) * Vector3(0, 0, -1)
			player.global_position = target_mob.global_position + dir_out * 5.0 + Vector3(0, 0.5, 0)
			player.yaw = atan2(-(target_mob.global_position - player.global_position).x,
					-(target_mob.global_position - player.global_position).z)
			player.pitch = -0.15
			target_mob.passive = true
			var dirn := ProjectSettings.globalize_path("res://../shots")
			await _ui_shot(dirn + "/mob_alive.png")
			target_mob.take_damage(1.0e6)
			await get_tree().create_timer(2.0).timeout
			await _ui_shot(dirn + "/mob_dead.png")
			await get_tree().create_timer(4.0).timeout
			await _ui_shot(dirn + "/mob_gone.png")
			print("MOB-SHOT done: %s corpse still in tree: %s" % [
					Cli.value("--mob-name=", "?"), is_instance_valid(target_mob)])
		get_tree().quit()
	elif OS.get_cmdline_user_args().has("--loot-run"):
		_loot_run()
		get_tree().quit()
	elif OS.get_cmdline_user_args().has("--what-here"):
		# which placed models' world bounds enclose the camera: the engine's
		# own transforms, so no offline reconstruction can be wrong
		await get_tree().process_frame
		await get_tree().process_frame
		var cam: Vector3 = player.get_node("Camera3D").global_position
		var names := _load_json(wow_dir.path_join("doodads/names.json"))
		var placed: Array = []
		var stack: Array = [self]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is Node3D and n.has_meta("fdid"):
				var lo := Vector3.INF
				var hi := -Vector3.INF
				for mi in _find_meshes(n):
					var ab: AABB = mi.global_transform * mi.get_aabb()
					lo = lo.min(ab.position)
					hi = hi.max(ab.end)
				if lo.x < hi.x:
					placed.append([n, AABB(lo, hi - lo)])
			stack.append_array(n.get_children())
		# everything close, whatever direction: the stray objects overhead
		var near := []
		for pr in placed:
			var box: AABB = pr[1]
			var q := cam.clamp(box.position, box.end)
			if cam.distance_to(q) < 15.0:
				var n: Node3D = pr[0]
				near.append([cam.distance_to(q), "%s fdid=%d %s at %s scale=%.2f size=%s parent=%s" % [
						n.get_meta("src"), n.get_meta("fdid"),
						str(names.get(str(n.get_meta("fdid")), "")),
						n.global_position, n.scale.x, box.size, n.get_parent().name]])
		near.sort_custom(func(a, b): return a[0] < b[0])
		print("WHAT-HERE within 15 m: %d placements" % near.size())
		for h in near.slice(0, 20):
			print("  %5.1f m  %s" % [h[0], h[1]])
		# the four capture directions: what does the crosshair ray hit first
		for k in 4:
			var dir: Vector3 = Basis(Vector3.UP, spawn_yaw + k * PI / 2.0) * Vector3(0, 0, -1)
			var hits := []
			for pr in placed:
				var hp = (pr[1] as AABB).intersects_ray(cam, dir)
				if hp != null and cam.distance_to(hp) < 40.0:
					var n: Node3D = pr[0]
					hits.append([cam.distance_to(hp), "%s fdid=%d %s at %s scale=%.2f size=%s" % [
							n.get_meta("src"), n.get_meta("fdid"),
							str(names.get(str(n.get_meta("fdid")), "")),
							n.global_position, n.scale.x, (pr[1] as AABB).size]])
			hits.sort_custom(func(a, b): return a[0] < b[0])
			print("WHAT-HERE dir %d: %d placements on the crosshair ray within 40 m" % [k, hits.size()])
			for h in hits.slice(0, 6):
				print("  %5.1f m  %s" % [h[0], h[1]])
		get_tree().quit()
	elif OS.get_cmdline_user_args().has("--stair-test"):
		# push the player up the entrance staircase with and without the
		# stepper and report height gained: risers are climbed, not walls.
		# Shadowfang's grand stair is the reference (3.7 m up / 31 m along
		# with the stepper, 1.2 m / 7.5 m without, when this landed)
		var fwd: Vector3 = Basis(Vector3.UP, spawn_yaw) * Vector3(0, 0, -1)
		for use_step in [false, true]:
			player.global_position = spawn
			player.velocity = Vector3.ZERO
			for f in range(240):
				await get_tree().physics_frame
			var y0 := player.global_position.y
			for f in range(300):
				player.velocity.x = fwd.x * 4.2
				player.velocity.z = fwd.z * 4.2
				player.velocity.y = 0.0 if player.is_on_floor() else player.velocity.y - 22.0 / 60.0
				var g := player.is_on_floor()
				var before_p := player.global_position
				player.move_and_slide()
				if use_step and g:
					Stepper.climb(player, Vector3(fwd.x, 0, fwd.z) * 4.2, 1.0 / 60.0)
				await get_tree().physics_frame
			print("STAIR TEST stepper=%s: climbed %.2f m, moved %.1f m" % [
					use_step, player.global_position.y - y0,
					(player.global_position - spawn).length()])
		get_tree().quit()
	elif OS.get_cmdline_user_args().has("--walk-test"):
		# stride around the cove ground between dock and ship — the area
		# that swallowed the player — and report footing
		player.global_position = Vector3(50, 16, 125)
		var lost := 0
		for f in range(900):
			var a := f * 0.01
			player.velocity.x = cos(a) * 3.5
			player.velocity.z = sin(a) * 3.5
			player.move_and_slide()
			if not player.is_on_floor() and player.velocity.y < -12.0:
				lost += 1
			await get_tree().physics_frame
			if f % 150 == 0:
				print("f=%d pos=(%.1f, %.1f, %.1f) floor=%s" % [f,
						player.global_position.x, player.global_position.y,
						player.global_position.z, player.is_on_floor()])
		print("walk test done: y=%.1f freefall_frames=%d" %
				[player.global_position.y, lost])
		get_tree().quit()
	elif OS.get_cmdline_user_args().has("--perf-test"):
		await _perf_test()
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


func _ui_shot(path: String) -> void:
	## settle the panel for a few frames, then capture (offscreen-safe)
	for i in range(8):
		await get_tree().process_frame
	await Cli.capture(get_viewport(), path)


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
	# a few skill levels so the tree's per-socket numbers are in the capture
	for sk in ["Magic Arrow", "Magic Arrow", "Fire Arrow", "Cold Arrow"]:
		if gs.skill_points > 0:
			gs.allocate(sk)
	await _ui_shot(shots + "/ui_hud.png")
	gs.stat_points = 5
	char_ui.toggle()
	_sync_ui()
	await _ui_shot(shots + "/ui_char.png")
	char_ui.toggle()
	gs.stat_points = 0
	inv_ui.toggle()
	_sync_ui()
	await _ui_shot(shots + "/ui_inv.png")
	inv_ui.toggle()
	tree_ui.toggle()
	_sync_ui()
	await _ui_shot(shots + "/ui_tree.png")
	tree_ui.toggle()
	toggle_menu()
	await _ui_shot(shots + "/ui_menu.png")
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
			if str(mi.name).begins_with("liquid"):
				continue    # water surfaces are visual only
			mi.create_trimesh_collision()
			mesh_count += 1
			if Cli.has("--two-sided"):
				for s in mi.mesh.get_surface_count():
					var m := mi.get_active_material(s)
					if m is BaseMaterial3D:
						m.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Whether a prop blocks movement is the model's own answer: the pipeline
	# lists the fdids whose M2 carries collision geometry. Sizing a collider
	# off the render mesh instead made the giant ferns solid, and their trimesh
	# is a thicket of leaf blades a player wedges inside. Asset builds made
	# before that list existed fall back to the size rule they were built
	# against, rather than turning every crate and cage into fog.
	var solid := {}
	for fd in placements.get("solid", []):
		solid[int(fd)] = true
	var solid_known: bool = placements.has("solid")
	# --no-doodads / --no-props: diagnostic captures that show which list a
	# piece of scenery comes from (or that it is part of the WMO itself)
	if not Cli.has("--no-doodads"):
		mesh_count += _place_set(placements.get("doodads", []), wmo_nodes,
				solid, solid_known)
	if not Cli.has("--no-props"):
		mesh_count += _place_set(placements.get("props", []), wmo_nodes,
				solid, solid_known)
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
				# terrain winding isn't guaranteed upward (the calibrated
				# transform can mirror it) and one-sided trimesh collision
				# let the player fall through near the ship — collide from
				# both sides
				for body in mi.get_children():
					if body is StaticBody3D:
						for cs in body.get_children():
							if cs is CollisionShape3D \
									and cs.shape is ConcavePolygonShape3D:
								cs.shape.backface_collision = true
		if str(terr.get("water", "")) != "":
			var wnode := _load_glb(wow_dir.path_join("terrain/" + str(terr.water)))
			if wnode != null:
				add_child(wnode)
		_outdoor_sky()
		print("terrain: %d tiles in %d ms" % [terr.tiles.size(),
				Time.get_ticks_msec() - t0])

	# fall-through guard, 60m under the lowest WMO group in the dungeon. The
	# pipeline writes one w<fdid>_meta.json per WMO, so scan them all rather
	# than a single fixed name — this used to read "deadmines_meta.json",
	# which no dungeon has shipped since the multi-dungeon build, leaving the
	# guard stuck at its -200 default everywhere.
	var lo := 1e9
	var dir := DirAccess.open(wow_dir)
	if dir != null:
		for f in dir.get_files():
			if not (f.begins_with("w") and f.ends_with("_meta.json")):
				continue
			var meta := _load_json(wow_dir.path_join(f))
			for g in meta.get("groups", []):
				lo = minf(lo, float(g["min"][1]))
	if lo < 1e8:
		floor_y = lo - 60.0
	print("fall guard at y=%.0f" % floor_y)


func _place_set(entries: Array, wmo_nodes: Dictionary, solid: Dictionary,
		solid_known: bool) -> int:
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
		node.set_meta("fdid", int(d["fdid"]))
		node.set_meta("src", "doodad" if d.has("parent_uid") else "prop")
		placed += 1
		if fresh:  # duplicates inherit the collision children
			for mi in _find_meshes(node):
				var blocks := mi.get_aabb().get_longest_axis_size() * sc > 4.0
				if solid_known:
					blocks = solid.has(int(d["fdid"]))
				if blocks:
					mi.create_trimesh_collision()
					collisions += 1
	print("placed %d instances (%d with collision)" % [placed, collisions])
	return collisions


func _loading_screen(did: String) -> CanvasLayer:
	## Full-screen backdrop + dungeon name shown while the world builds. The
	## painted zone art (menu backdrops) stands in for WoW's loading screens,
	## which are not in the local client data.
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var img := Image.load_from_file(ProjectSettings.globalize_path(
			Paths.asset("wow/backdrops/%s.png" % did)))
	if img != null:
		var tr := TextureRect.new()
		tr.texture = ImageTexture.create_from_image(img)
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		layer.add_child(tr)
	var name := Label.new()
	name.text = get_node("/root/Dungeons").display_name(did)
	name.add_theme_font_size_override("font_size", 44)
	name.add_theme_color_override("font_color", Color(0.9, 0.82, 0.6))
	name.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	name.add_theme_constant_override("outline_size", 10)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	name.offset_left = -400
	name.offset_right = 400
	name.offset_top = -130
	name.offset_bottom = -70
	layer.add_child(name)
	var sub := Label.new()
	sub.text = "Loading…"
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6))
	sub.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	sub.add_theme_constant_override("outline_size", 6)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	sub.offset_left = -200
	sub.offset_right = 200
	sub.offset_top = -66
	sub.offset_bottom = -36
	layer.add_child(sub)
	return layer


func unstuck_player() -> void:
	## Free a player wedged in scenery: back to where they were walking a few
	## seconds ago, or to the dungeon entrance if they never got going.
	if player == null:
		return
	if not player.unstuck():
		player.global_position = spawn + Vector3.UP * 0.5
		player.velocity = Vector3.ZERO
	if hud_node != null:
		hud_node.show_area("Unstuck")


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
	# always the dungeon's own entrance: saves carry the character, not a
	# position, so entering a dungeon always starts it from the beginning
	player.position = spawn
	player.yaw = spawn_yaw
	player.fire_action.connect(_on_fire)
	add_child(player)


# WowSfx voice groups by creature entry (peasant files aren't in the local
# storage yet — mapped anyway so they speak the day they extract)
const VOICE_MAP := {598: "peasant", 3586: "peasant", 4416: "peasant",
		622: "goblin", 641: "goblin", 642: "goblin", 647: "goblin",
		1731: "goblin", 1763: "goblin", 3947: "goblin",
		645: "murloc", 644: "ogre"}
const HEAVY_HITTERS := [642, 644, 646]   # shredder, ogre, Smite swing heavy


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
		# the pipeline assigns a voice family per model (with per-dungeon
		# overrides); the entry map is only a fallback for older manifests
		mob.voice = str(info.get("voice", VOICE_MAP.get(int(c["entry"]), "")))
		mob.impact_kind = "heavy" if int(c["entry"]) in HEAVY_HITTERS else "sword"
		mob.set_meta("entry", int(c["entry"]))
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
	enemy_missiles.append({"node": node, "vel": dir * mob.ranged_vel * mob.missile_speed_factor(),
			"life": 2.6, "dmg": dmg, "etype": mob.ranged_etype,
			"ar": float(mob.stats.get("A1TH", 40)),
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
			var chance := GameState.chance_to_hit(m["ar"],
					gs.player_defense() + float(gs.mods.get("ac-miss", 0)),
					int(m["mlvl"]), gs.level)
			if randf() < chance and randf() >= gs.avoid_chance() \
					and randf() < gs.block_chance():
				# blocked: D2 shields stop missiles as well as blows
				get_node("/root/Sfx").event("blade_impact", node.global_position)
				player.on_block()
			elif randf() < chance and randf() >= gs.avoid_chance():
				get_node("/root/Sfx").event("player_gethit", node.global_position, 0.4)
				var et := str(m["etype"])
				if et == "cold":
					player.chill(2.0)
				if gs.take_damage(m["dmg"], et if et != "" else "phys", true) \
						and player.has_method("die"):
					player.die()
				else:
					player.on_hurt(float(m["dmg"]))
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
		"Plague Javelin": radius = 3.5
	if radius <= 0.0:
		return
	for mob in monsters:
		if not (mob is WowCreature) or mob.state == WowCreature.State.DEAD:
			continue
		if mob.global_position.distance_to(pos) > radius:
			continue
		if sk == "Freezing Arrow":
			mob.slow(2.0 + 0.4 * lvl, 0.25)
			mob.take_damage((4.0 + 3.0 * lvl) * GameState.DMG_MULT / 5.0
					* gs.skill_elem_mult("cold"), "cold")
		elif sk == "Plague Javelin":
			var pd := _skill_elemental(gs, sk, lvl)
			mob.burn(randf_range(pd.x, pd.y) / 4.0, 4.0)
		else:
			mob.take_damage((3.0 + 4.0 * lvl) * GameState.DMG_MULT / 5.0
					* gs.skill_elem_mult("fire"), "fire")
			if sk == "Immolation Arrow":
				mob.burn(4.0 * lvl * GameState.DMG_MULT / 5.0
						* gs.skill_elem_mult("fire"), 3.0, "fire")


func _hit_monster(mob: WowCreature, ranged: bool, extra: float, thrown := false,
		extra_type := "") -> void:
	## One player blow landing: physical + item elemental damage, crushing
	## blow, open wounds, cold slow and poison from the gear, and the life and
	## mana the blow leeches back. extra: a skill's own elemental damage, of
	## extra_type. Each type is resisted by the creature on its own.
	var gs := get_node("/root/GameState")
	var h: Dictionary = gs.roll_player_hit(ranged, str(mob.stats.get("ctype", "")), thrown)
	var parts := {"phys": float(h["phys"])}
	for el in h["elem"]:
		parts[el] = float(parts.get(el, 0.0)) + float(h["elem"][el])
	if extra > 0.0:
		var et := extra_type if extra_type != "" else "mag"
		parts[et] = float(parts.get(et, 0.0)) + extra
	if float(h["cold_len"]) > 0.0:
		mob.slow(float(h["cold_len"]), 0.5)
	if float(h["pois_total"]) > 0.0:
		mob.burn(float(h["pois_total"]) / maxf(0.5, float(h["pois_len"])), float(h["pois_len"]))
	if h["openwounds"]:
		# bleeding is physical: no resistance applies
		mob.burn(float(h["ow_dps"]), 8.0, "phys")
	if h["crush"]:
		# D2 halves crushing blow against bosses
		parts["phys"] += mob.hp * float(h["crush_frac"]) * (0.5 if mob.is_boss else 1.0)
	for et in parts:
		parts[et] = float(parts[et]) * _melee_mult
	if h["noheal"]:
		mob.noheal = true
	if float(h["slow_pct"]) > 0.0:
		mob.slow(3.0, clampf(1.0 - float(h["slow_pct"]) / 100.0, 0.25, 0.9))
	if float(h["freeze"]) > 0.0:
		mob.freeze(float(h["freeze"]))
	if h["knock"]:
		mob.knockback(mob.global_position - player.global_position)
	gs.on_hit_dealt(h)
	mob.take_hit(parts)


var _melee_mult := 1.0            # Impale: one heavy blow
const THROW_SKILLS := ["Poison Javelin", "Plague Javelin", "Lightning Bolt", "Lightning Fury"]
const CAST_SKILLS := ["Inner Sight", "Slow Missiles"]


func _skill_elemental(gs, skill: String, lvl: int) -> Vector2:
	## the skill's own elemental damage at this level, from the D2 table
	var srow: Dictionary = gs.skill_row(skill)
	var lo := float(str(srow.get("EMin", "0")).to_int()) \
			+ float(str(srow.get("EMinLev1", "0")).to_int()) * (lvl - 1)
	var hi := float(str(srow.get("EMax", "0")).to_int()) \
			+ float(str(srow.get("EMaxLev1", "0")).to_int()) * (lvl - 1)
	var mult: float = gs.skill_elem_mult(str(srow.get("EType", "")).strip_edges())
	return Vector2(lo, maxf(lo, hi)) * GameState.DMG_MULT * mult


func _chain_lightning(from: Vector3, exclude: Node, count: int, dmg: Vector2) -> void:
	## bolts jump to the nearest other creatures within 8 m
	var cands := []
	for mob in monsters:
		if mob is WowCreature and mob != exclude and mob.state != WowCreature.State.DEAD \
				and mob.global_position.distance_to(from) < 8.0:
			cands.append(mob)
	cands.sort_custom(func(a, b):
		return a.global_position.distance_to(from) < b.global_position.distance_to(from))
	for i in range(mini(count, cands.size())):
		var m: WowCreature = cands[i]
		m.take_damage(randf_range(dmg.x, dmg.y), "ltng")
		var bolt := BillboardAnim.new()
		add_child(bolt)
		bolt.play("missiles/lightningbolt", false, "center")
		bolt.global_position = m.global_position + Vector3(0, 1.0, 0)
		bolt.finished.connect(bolt.queue_free)
	if cands.size() > 0:
		get_node("/root/Sfx").event("fire_impact", from, 0.6)


func _melee_params() -> Vector2:
	## (reach, half-arc): bigger D2 weapons cleave further and wider —
	## a dagger pokes, a great poleaxe sweeps the whole doorway.
	var gs := get_node("/root/GameState")
	var reach := 2.6
	var arc := 0.8
	var w: Dictionary = gs.equipped.get("weap", {})
	if not w.is_empty():
		var it: Dictionary = get_node("/root/ItemDB").item(str(w.get("code", "")))
		var cells: int = maxi(1, str(it.get("invwidth", "1")).to_int()) \
				* maxi(1, str(it.get("invheight", "1")).to_int())
		var two_hand: bool = str(it.get("2handmindam", "")).to_int() > 0
		reach = 2.4 + 0.22 * cells + (0.5 if two_hand else 0.0)
		arc = 0.7 + 0.07 * cells + (0.2 if two_hand else 0.0)
	return Vector2(reach, minf(arc, 1.5))


func _melee_swing(origin: Vector3, dir: Vector3) -> void:
	# a swing that geometrically connects always hits (like arrows) — the
	# aim and the weapon's cleave replace D2's attack-rating roll
	var gs := get_node("/root/GameState")
	var sfx := get_node("/root/Sfx")
	sfx.event("staff_swing" if player.weapon_class == "stf" else "melee_swing", origin)
	var p := _melee_params()
	var flat_dir := Vector3(dir.x, 0, dir.z).normalized()
	var connected := false
	for mob in monsters:
		if not (mob is WowCreature) or mob.state == WowCreature.State.DEAD:
			continue
		var to: Vector3 = mob.global_position - player.global_position
		to.y = 0.0
		if to.length() > p.x + mob.attack_range - 2.0:
			continue
		if flat_dir.angle_to(to.normalized()) > p.y:
			continue
		_hit_monster(mob, false, 0.0)
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
	# Inner Sight / Slow Missiles: cast with any weapon on everything in range
	if skill in CAST_SKILLS:
		var ccost: float = gs.mana_cost(skill)
		if gs.mana < ccost:
			return
		gs.mana -= ccost
		var clvl: int = maxi(1, gs.skill_level(skill))
		var radius := 12.0 + float(clvl)
		var dur := 8.0 + 4.0 * float(clvl)
		var hit_n := 0
		for mob in monsters:
			if mob is WowCreature and mob.state != WowCreature.State.DEAD \
					and mob.global_position.distance_to(player.global_position) < radius:
				if skill == "Inner Sight":
					mob.reveal(dur)
				else:
					mob.slow_missiles(dur)
				hit_n += 1
		get_node("/root/Sfx").event_ui("button")
		if hud_node != null:
			hud_node.show_area("%s: %d" % [skill, hit_n], Color(0.7, 0.8, 1.0), 1.5)
		return
	# Throw: the plain javelin throw, no mana, the weapon's own throw damage
	if skill == "Throw":
		if gs.is_javelin():
			_launch_arrow(gs, "Throw", origin, dir)
			return
		skill = "Attack"
	# the javelin throws: a missile that carries the skill's element
	if skill in THROW_SKILLS:
		if not gs.is_javelin():
			skill = "Attack"
		else:
			var tcost: float = gs.mana_cost(skill)
			if gs.mana < tcost:
				skill = "Attack"
			else:
				gs.mana -= tcost
				_launch_arrow(gs, skill, origin, dir)
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
						mob.take_damage((3.0 + 3.0 * mlvl) * GameState.DMG_MULT / 5.0
								* gs.skill_elem_mult("ltng"), "ltng")
			"Impale":
				# one heavy blow (+300% and 25% a level in D2), slow to recover
				_melee_mult = 4.0 + 0.25 * float(mlvl - 1)
				_melee_swing(origin, dir)
				_melee_mult = 1.0
				player.attack_time = player._attack_len * 1.6
			"Lightning Strike":
				_melee_swing(origin, dir)
				_chain_lightning(player.global_position + dir * 2.0, null,
						1 + mlvl, _skill_elemental(gs, "Lightning Strike", mlvl))
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
	# "Fires Magic Arrows" / "Fires Explosive Arrows": the bow converts a plain
	# attack into that skill at the item's level, at no mana cost
	if skill == "Attack" and not player.melee:
		if int(gs.mods.get("magicarrow", 0)) > 0:
			skill = "Magic Arrow"
		elif int(gs.mods.get("explosivearrow", 0)) > 0:
			skill = "Exploding Arrow"
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
	var edmg: Vector2 = Vector2(float(str(srow.get("EMin", "0")).to_int()),
			float(str(srow.get("EMax", "0")).to_int())) * escale \
			* gs.skill_elem_mult(etype)
	if skill in ["Poison Javelin", "Plague Javelin", "Throw"]:
		cel = "javelin"
	elif skill in ["Lightning Bolt", "Lightning Fury"]:
		cel = "lightningbolt"
	var arrow := BillboardAnim.new()
	add_child(arrow)
	arrow.play("missiles/" + cel, true, "center")
	arrow.global_position = origin + d2 * 0.5
	arrow.facing = atan2(d2.x, d2.z)
	arrows.append({"node": arrow, "vel": d2 * ARROW_SPEED, "life": 3.0,
			"skill": skill, "edmg": edmg, "etype": etype, "explode": explode,
			"homing": skill == "Guided Arrow",
			"thrown": skill == "Throw" or skill in THROW_SKILLS})
	get_node("/root/Sfx").event(
		"xbow_fire" if player.weapon_class == "xbw" else "bow_fire", origin)


var _ground_recent := Vector3.ZERO   # solid footing snapshots: falling
var _ground_safe := Vector3.ZERO     # through returns you here, not to spawn
var _ground_t := 0.0


func _physics_process(dt: float) -> void:
	_update_enemy_missiles(dt)
	if player != null:
		if player.is_on_floor():
			_ground_t += dt
			if _ground_t >= 2.0:
				_ground_t = 0.0
				_ground_safe = _ground_recent if _ground_recent != Vector3.ZERO \
						else player.global_position
				_ground_recent = player.global_position
		if player.global_position.y < floor_y:
			player.global_position = _ground_safe + Vector3(0, 1.5, 0) \
					if _ground_safe != Vector3.ZERO else spawn
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
				# the skill's own elemental damage rides on top of the blow
				var extra := 0.0
				var edmg: Vector2 = a.get("edmg", Vector2.ZERO)
				if edmg.y > 0.0:
					extra = randf_range(edmg.x, edmg.y) * GameState.DMG_MULT
				var sk := str(a.get("skill", ""))
				if a.get("etype", "") == "cold":
					var factor := 0.25 if sk in ["Ice Arrow", "Freezing Arrow"] else 0.4
					col.slow(2.0 + 0.5 * gs.skill_level(sk), factor)
				if sk == "Immolation Arrow":
					col.burn(6.0 * gs.skill_level(sk) * GameState.DMG_MULT / 5.0
							* gs.skill_elem_mult("fire"), 3.0, "fire")
				if a.get("etype", "") == "pois" and extra > 0.0:
					# poison is damage over time, not a burst
					col.burn(extra / 4.0, 4.0)
					extra = 0.0
				_hit_monster(col, true, extra, bool(a.get("thrown", false)),
						str(a.get("etype", "")))
				if sk == "Lightning Fury":
					_chain_lightning(hit["position"], col, 2 + gs.skill_level(sk) / 2,
							_skill_elemental(gs, sk, maxi(1, gs.skill_level(sk))))
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
	# D2's drop: the monster's treasure class (by level and kind), rolled
	# through with its NoDrop and Picks; every base that comes out goes
	# through the ItemRatio quality roll with the class's magic-find bonus.
	# Champions and uniques floor their drops at magic, as D2 does.
	var db := get_node("/root/ItemDB")
	var gen := get_node("/root/ItemGen")
	var gs := get_node("/root/GameState")
	var kind := str(dead.stats.get("kind", "boss" if dead.is_boss else "normal"))
	if dead.is_final_boss:
		kind = "final"
	for res in db.drops_for(dead.mlevel, kind, str(dead.stats.get("archetype", "melee"))):
		var gi := GroundItem.new()
		add_child(gi)
		if int(res["gold"]) > 0:
			var amount: int = int(res["gold"]) * (100 + int(gs.mods.get("gold%", 0))) / 100
			gi.drop("gold", maxi(1, amount))
		else:
			var inst: Dictionary = res["inst"]
			if inst.is_empty():
				gi.drop(res["code"], 0)
			else:
				gi.drop_instance(inst)
		var a := randf() * TAU
		var r := randf_range(0.3, 1.4) if kind != "normal" else randf_range(0.3, 1.0)
		gi.global_position = dead.global_position \
				+ Vector3(cos(a) * r, 0.02, sin(a) * r)
		ground_items.append(gi)
	get_node("/root/Sfx").event("flippy", dead.global_position)
	gs.on_kill(str(dead.stats.get("ctype", "")))
	# boss-keyed doors swing open on the kill
	for dr in doors:
		if not dr["open"] and str(dr.get("rule", {}).get("boss", "")) == dead.cname:
			_open_door(dr)
	# the final boss marks the dungeon complete and advances the ladder
	if dead.is_final_boss:
		var gsd := get_node("/root/GameState")
		if gsd.complete_dungeon():
			gsd.save_game(player)
			hud_node.show_area("%s conquered!" % get_node("/root/Dungeons")
					.display_name(gsd.current_dungeon), Color(0.3, 0.95, 0.3), 7.0)


func _item_test() -> void:
	## Every tier-A / Amazon-skill property on one item, equipped, and the
	## numbers it changes — the check that a tooltip line does something.
	var gs := get_node("/root/GameState")
	var gen := get_node("/root/ItemGen")
	var txt := get_node("/root/ItemText")
	print("ITEM-TEST starter charm: +%d%% experience from the inventory" % int(gs.mods.get("addxp", 0)))
	gs.level = 12
	var before := {"hp_max": gs.hp_max, "mana_max": gs.mana_max,
			"dmg": gs.weapon_damage(), "ias": gs.attack_speed_factor(),
			"frw": gs.run_speed_factor(), "stam": gs.stamina_max(),
			"pierce": gs.pierce_chance(), "res_fire": gs.resist("fire"),
			"magic_arrow": gs.skill_level("Magic Arrow"),
			"fire_arrow": gs.skill_level("Fire Arrow")}
	var props := [
		{"code": "dmg-fire", "param": "", "min": "10", "max": "20"},
		{"code": "dmg-cold", "param": "50", "min": "3", "max": "6"},
		{"code": "dmg-pois", "param": "75", "min": "34", "max": "34"},
		{"code": "dmg-norm", "param": "", "min": "2", "max": "5"},
		{"code": "lifesteal", "param": "", "min": "8", "max": "8"},
		{"code": "manasteal", "param": "", "min": "5", "max": "5"},
		{"code": "regen", "param": "", "min": "10", "max": "10"},
		{"code": "regen-mana", "param": "", "min": "25", "max": "25"},
		{"code": "hp%", "param": "", "min": "20", "max": "20"},
		{"code": "hp/lvl", "param": "20", "min": "", "max": ""},
		{"code": "stam", "param": "", "min": "30", "max": "30"},
		{"code": "red-dmg", "param": "", "min": "3", "max": "3"},
		{"code": "red-dmg%", "param": "", "min": "10", "max": "10"},
		{"code": "res-fire", "param": "", "min": "60", "max": "60"},
		{"code": "res-fire-max", "param": "", "min": "10", "max": "10"},
		{"code": "abs-fire", "param": "", "min": "4", "max": "4"},
		{"code": "crush", "param": "", "min": "25", "max": "25"},
		{"code": "deadly", "param": "", "min": "30", "max": "30"},
		{"code": "openwounds", "param": "", "min": "50", "max": "50"},
		{"code": "pierce", "param": "", "min": "30", "max": "30"},
		{"code": "dmg-undead", "param": "", "min": "50", "max": "50"},
		{"code": "swing2", "param": "", "min": "20", "max": "20"},
		{"code": "move2", "param": "", "min": "30", "max": "30"},
		{"code": "ease", "param": "", "min": "-20", "max": "-20"},
		{"code": "addxp", "param": "", "min": "10", "max": "10"},
		{"code": "allskills", "param": "", "min": "1", "max": "1"},
		{"code": "skilltab", "param": "0", "min": "2", "max": "2"},
		{"code": "skill", "param": "7", "min": "3", "max": "3"},
		{"code": "fireskill", "param": "", "min": "1", "max": "1"},
		{"code": "magicarrow", "param": "", "min": "5", "max": "5"},
		# the small rows: mastery, pierce, cast rate, hit recovery, prevent
		# heal, the mis-cased light radius, ethereal
		{"code": "extra-fire", "param": "", "min": "30", "max": "30"},
		{"code": "pierce-fire", "param": "", "min": "40", "max": "40"},
		{"code": "cast2", "param": "", "min": "20", "max": "20"},
		{"code": "balance2", "param": "", "min": "30", "max": "30"},
		{"code": "noheal", "param": "", "min": "1", "max": "1"},
		{"code": "Light", "param": "", "min": "3", "max": "3"},
		{"code": "ethereal", "param": "", "min": "", "max": ""},
	]
	var inst := {"code": "sbw", "quality": "unique", "name": "Test Bow",
			"base_name": "Short Bow", "props": gen._roll_vals(props),
			"color": "ffffff", "reqlvl": 1}
	gs.skills["Fire Arrow"] = 1
	gs.equipped["weap"] = {"code": "sbw", "inst": inst}
	var shield := {"code": "tow", "quality": "magic", "name": "Test Shield",
			"base_name": "Tower Shield", "color": "ffffff", "reqlvl": 1,
			"base_ac": 30,
			"props": gen._roll_vals([
				{"code": "block", "param": "", "min": "20", "max": "20"},
				{"code": "block2", "param": "", "min": "30", "max": "30"},
				{"code": "ac%", "param": "", "min": "50", "max": "50"}])}
	var no_shield: float = gs.block_chance()
	var def0: float = gs.player_defense()
	gs.equipped["shie"] = {"code": "tow", "inst": shield}
	gs._recalc()
	print("ITEM-TEST block chance: quiver %.0f%% -> tower shield +20%% block %.0f%%  recovery %.2fs (30%% fbr)" % [
			no_shield * 100.0, gs.block_chance() * 100.0, gs.block_recovery()])
	# the javelin tree and the two casts, fired once each for runtime errors
	gs.equipped["weap"] = {"code": "jav", "inst": {}}
	player.refresh_attack_style()
	for sk in ["Poison Javelin", "Lightning Bolt", "Plague Javelin", "Lightning Fury",
			"Inner Sight", "Slow Missiles", "Impale", "Lightning Strike", "Jab"]:
		gs.skills[sk] = 3
		gs.mana = 100.0
		player.action_skill[0] = sk
		_on_fire(0, player.global_position + Vector3(0, 1.5, 0), Vector3(0, 0, -1))
		print("ITEM-TEST %s fired: javelin=%s arrows in flight %d" % [sk, gs.is_javelin(), arrows.size()])
	# the overhead slash, three points along the swing
	var shots := ProjectSettings.globalize_path("res://../shots")
	gs.equipment_changed.emit()          # the javelin in hand, not the bow
	player.melee = true
	player.set_physics_process(false)    # hold the swing at each phase
	for e in [0.15, 0.5, 0.85]:
		player.attack_time = player._attack_len * (1.0 - e)
		await _ui_shot(shots + "/ui_swing_%d.png" % int(e * 100))
	player.set_physics_process(true)
	player.attack_time = 0.0
	player.action_skill[0] = "Throw"
	gs.mana = 0.0
	_on_fire(0, player.global_position + Vector3(0, 1.5, 0), Vector3(0, 0, -1))
	print("ITEM-TEST Throw with a javelin and no mana: arrows in flight %d" % arrows.size())
	# and once each at the nearest creature, so the impact paths run
	var nearest: WowCreature = null
	for mob in monsters:
		if mob is WowCreature and mob.state != WowCreature.State.DEAD and (nearest == null
				or mob.global_position.distance_to(player.global_position)
				< nearest.global_position.distance_to(player.global_position)):
			nearest = mob
	if nearest != null:
		var hp0: float = nearest.hp
		for sk in ["Poison Javelin", "Plague Javelin", "Lightning Fury", "Lightning Bolt"]:
			gs.mana = 100.0
			player.action_skill[0] = sk
			var o := player.global_position + Vector3(0, 1.5, 0)
			_on_fire(0, o, (nearest.global_position + Vector3(0, 0.9, 0) - o).normalized())
		await get_tree().create_timer(3.0).timeout
		print("ITEM-TEST throws at %s: hp %.0f -> %.0f, arrows left %d" % [
				nearest.cname, hp0, nearest.hp, arrows.size()])
	gs.equipped["weap"] = {"code": "sbw", "inst": inst}
	player.refresh_attack_style()
	# the shield in the off-hand, on screen
	gs.equipment_changed.emit()
	await _ui_shot(ProjectSettings.globalize_path("res://../shots") + "/ui_offhand.png")
	print("ITEM-TEST lines:")
	for pair in txt.lines_with_codes(inst):
		print("   %s  %s" % ["ok " if gs.applies(str(pair[1])) else "dim", pair[0]])
	print("ITEM-TEST hp_max %.0f -> %.0f   mana_max %.0f -> %.0f   stamina %.0f -> %.0f" % [
			before.hp_max, gs.hp_max, before.mana_max, gs.mana_max, before.stam, gs.stamina_max()])
	print("ITEM-TEST weapon dmg %s -> %s   ias %.2f -> %.2f   frw %.2f -> %.2f   pierce %.2f -> %.2f" % [
			before.dmg, gs.weapon_damage(), before.ias, gs.attack_speed_factor(),
			before.frw, gs.run_speed_factor(), before.pierce, gs.pierce_chance()])
	print("ITEM-TEST fire resist %.0f -> %.0f (cap raised)   Magic Arrow lvl %d -> %d   Fire Arrow lvl %d -> %d" % [
			before.res_fire, gs.resist("fire"), before.magic_arrow, gs.skill_level("Magic Arrow"),
			before.fire_arrow, gs.skill_level("Fire Arrow")])
	print("ITEM-TEST requirements for a bow needing 35 str: %s" % str(
			gs.equip_requirements({"code": "lbw", "inst": inst})))
	var h: Dictionary = gs.roll_player_hit(true, "undead")
	print("ITEM-TEST one ranged hit vs undead: %s" % str(h))
	var hp0: float = gs.hp
	gs.take_damage(20.0, "fire")
	print("ITEM-TEST 20 fire damage in -> %.1f taken (60%% resist, -4 absorb)" % (hp0 - gs.hp))
	hp0 = gs.hp
	gs.take_damage(20.0, "phys")
	print("ITEM-TEST 20 physical in -> %.1f taken (-3 flat, -10%%)" % (hp0 - gs.hp))
	print("ITEM-TEST defense %.1f -> %.1f (tower shield base 30, +50%% enhanced)" % [
			def0, gs.player_defense()])
	print("ITEM-TEST fire skill damage x%.2f   cast speed x%.2f   hit recovery %.2fs   prevents heal %s   ethereal weapon %s" % [
			gs.skill_elem_mult("fire"), gs.cast_speed_factor(), gs.hit_recovery(),
			str(gs.prevents_heal()), str(gs.eth_weapon)])
	# monster resistances: the Molten Elemental is fire-immune and cold-weak
	for mob in monsters:
		if mob is WowCreature and mob.cname == "Molten Elemental":
			var pierce: float = gs.mods.get("pierce-fire", 0)
			gs.mods["pierce-fire"] = 0.0
			var r0: float = mob.effective_resist("fire")
			gs.mods["pierce-fire"] = pierce
			var mhp: float = mob.hp
			mob.take_damage(10.0, "fire")
			var fire_taken: float = mhp - mob.hp
			mhp = mob.hp
			mob.take_damage(10.0, "cold")
			print("ITEM-TEST Molten Elemental res %s: fire %.0f%% -> %.0f%% with -%.0f%% pierce; 10 fire -> %.1f taken, 10 cold -> %.1f taken" % [
					str(mob.res), r0, mob.effective_resist("fire"), pierce,
					fire_taken, mhp - mob.hp])
			break


func _pct(samples: Array) -> Dictionary:
	var s := samples.duplicate()
	s.sort()
	if s.is_empty():
		return {"n": 0, "avg": 0.0, "p50": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0}
	var sum := 0.0
	for v in s:
		sum += v
	return {"n": s.size(), "avg": sum / s.size(),
			"p50": s[int(s.size() * 0.5)], "p95": s[int(s.size() * 0.95)],
			"p99": s[mini(s.size() - 1, int(s.size() * 0.99))], "max": s[s.size() - 1]}


func _perf_test() -> void:
	## Frame-time probe in three parts: two laps of a look-around at the
	## spawn (first-sight costs vs. warmed), a sprint through the dungeon's
	## creature clusters with every spike attributed (chasing creatures,
	## objects entering the frame, sound decodes), and a crowd test that
	## drags N creatures onto the Amazon and holds them there.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var gs := get_node("/root/GameState")
	var sfx := get_node("/root/Sfx")
	var wsfx := get_node("/root/WowSfx")
	gs.hp_max = 1.0e6
	gs.hp = 1.0e6
	for i in range(30):
		await get_tree().process_frame
	print("PERF %s: %d creatures, %d nodes" % [gs.current_dungeon, monsters.size(),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])

	# ---- look-around, twice
	for lap in range(2):
		var samples := []
		var t := 0.0
		while t < 4.0:
			var dt := get_process_delta_time()
			player.yaw += TAU * dt / 4.0
			t += dt
			samples.append(dt * 1000.0)
			await get_tree().process_frame
		var p := _pct(samples)
		print("PERF look lap %d: avg %.1f ms  p50 %.1f  p95 %.1f  p99 %.1f  max %.1f  (%d frames)" % [
				lap + 1, p.avg, p.p50, p.p95, p.p99, p.max, p.n])

	# ---- sprint tour: greedy nearest-cluster route through the spawns
	var cells := {}
	for mob in monsters:
		if mob is WowCreature and mob.state != WowCreature.State.DEAD:
			var k := Vector2i(int(floor(mob.global_position.x / 12.0)), int(floor(mob.global_position.z / 12.0)))
			if not cells.has(k):
				cells[k] = mob.global_position
	var route := []
	var here: Vector3 = player.global_position
	var pool := cells.values()
	while not pool.is_empty() and route.size() < 25:
		var best_i := 0
		for i in range(pool.size()):
			if (pool[i] as Vector3).distance_to(here) < (pool[best_i] as Vector3).distance_to(here):
				best_i = i
		here = pool[best_i]
		route.append(here)
		pool.remove_at(best_i)
	var frames := []           # [t, ms, chasing, objects, drawcalls, loads]
	var t2 := 0.0
	var wi := 0
	var loads0: int = sfx.loads + wsfx.loads
	while wi < route.size() and t2 < 75.0:
		var dt := get_process_delta_time()
		var wp: Vector3 = route[wi]
		var to := wp - player.global_position
		if to.length() < 1.5:
			wi += 1
		else:
			var step := to.normalized() * minf(8.4 * dt, to.length())
			player.global_position += step
			player.velocity = Vector3.ZERO
			player.yaw = atan2(-step.x, -step.z)
		var chasing := 0
		for mob in monsters:
			if mob is WowCreature and mob.state in [WowCreature.State.CHASE, WowCreature.State.ATTACK]:
				chasing += 1
		frames.append([t2, dt * 1000.0, chasing,
				int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
				int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
				sfx.loads + wsfx.loads - loads0])
		t2 += dt
		await get_tree().process_frame
	var ms := []
	for f in frames:
		ms.append(f[1])
	var p := _pct(ms)
	var over33 := 0
	var over66 := 0
	for v in ms:
		if v > 33.0:
			over33 += 1
		if v > 66.0:
			over66 += 1
	print("PERF sprint: %d waypoints, %.0f s, %d frames  avg %.1f ms  p50 %.1f  p95 %.1f  p99 %.1f  max %.1f  spikes >33ms %d  >66ms %d  sound decodes %d" % [
			route.size(), t2, p.n, p.avg, p.p50, p.p95, p.p99, p.max, over33, over66,
			sfx.loads + wsfx.loads - loads0])
	# the worst frames with what changed on them
	var order := range(frames.size())
	order.sort_custom(func(a, b): return frames[a][1] > frames[b][1])
	for k in range(mini(8, order.size())):
		var i: int = order[k]
		var prev: Array = frames[maxi(0, i - 1)]
		var f: Array = frames[i]
		print("PERF   spike t=%5.1fs %6.1f ms  chasing %2d (%+d)  objects %5d (%+d)  drawcalls %4d  decodes this frame %d" % [
				f[0], f[1], f[2], f[2] - prev[2], f[3], f[3] - prev[3], f[4], f[5] - prev[5]])
	# frame time by how many creatures are chasing
	var bins := {"0": [], "1-5": [], "6-10": [], "11-20": [], "21+": []}
	for f in frames:
		var c: int = f[2]
		var key := "0" if c == 0 else ("1-5" if c <= 5 else ("6-10" if c <= 10 else ("11-20" if c <= 20 else "21+")))
		bins[key].append(f[1])
	for key in bins:
		if not bins[key].is_empty():
			var bp := _pct(bins[key])
			print("PERF   chasing %-5s: %4d frames  avg %.1f ms  p95 %.1f" % [key, bp.n, bp.avg, bp.p95])

	# ---- crowd: N creatures pulled onto the Amazon and held there
	for n in [0, 10, 20, 40]:
		var alive := []
		for mob in monsters:
			if mob is WowCreature and mob.state != WowCreature.State.DEAD:
				alive.append(mob)
		alive.sort_custom(func(a, b):
			return a.global_position.distance_to(player.global_position) < b.global_position.distance_to(player.global_position))
		for i in range(mini(n, alive.size())):
			var m: WowCreature = alive[i]
			var a := TAU * i / maxi(1, n)
			m.global_position = player.global_position + Vector3(cos(a) * 5.0, 0.5, sin(a) * 5.0)
			m.target = player
			m.state = WowCreature.State.CHASE
		var samples := []
		var phys := []
		var draws := []
		var t3 := 0.0
		while t3 < 3.0:
			var dt := get_process_delta_time()
			t3 += dt
			samples.append(dt * 1000.0)
			phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			await get_tree().process_frame
		var cp := _pct(samples)
		var pp := _pct(phys)
		var dp := _pct(draws)
		print("PERF crowd n=%2d (%2d placed): avg %.1f ms  p95 %.1f  max %.1f   physics avg %.2f ms  drawcalls avg %.0f" % [
				n, mini(n, alive.size()), cp.avg, cp.p95, cp.max, pp.avg, dp.avg])


func _loot_test() -> void:
	## Drop statistics for the levels the four dungeons span: per kind, the
	## treasure class used, drops per kill, and the quality mix of gear.
	var db := get_node("/root/ItemDB")
	var gen := get_node("/root/ItemGen")
	const N := 200
	for mlvl in [2, 4, 8, 12, 15, 18, 22]:
		for kind in ["normal", "champion", "boss", "final"]:
			var tc: String = db.tc_for(mlvl, kind, "melee")
			var drops := 0
			var gold := 0
			var gear := 0
			var q := {"normal": 0, "magic": 0, "rare": 0, "set": 0, "unique": 0}
			var sample := []
			for i in range(N):
				for res in db.drops_for(mlvl, kind, "melee"):
					drops += 1
					if int(res["gold"]) > 0:
						gold += 1
						continue
					var inst: Dictionary = res["inst"]
					var it: Dictionary = db.item(str(res["code"]))
					if not gen._equippable(gen.type_chain(str(it.get("type", "")))):
						continue
					gear += 1
					var qual := str(inst.get("quality", "normal"))
					q[qual] = int(q[qual]) + 1
					if qual in ["unique", "set"] and sample.size() < 3:
						sample.append("%s (%s, rlvl %d)" % [inst.get("name", ""),
								inst.get("base_name", ""), int(inst.get("reqlvl", 0))])
			print("LOOT mlvl %2d %-8s %-22s drops/kill %.2f  gold %.2f  gear/kill %.2f  "
					% [mlvl, kind, tc, float(drops) / N, float(gold) / N, float(gear) / N]
					+ "per kill r/s/u %.2f %.2f %.2f  %s" % [
					float(q["rare"]) / N, float(q["set"]) / N, float(q["unique"]) / N,
					" | ".join(sample)])


func _loot_run() -> void:
	## A full clear of the first four dungeons, every spawned creature
	## killed once, repeated RUNS times: the expected rares, sets and uniques
	## per dungeon (item level is the monster's, so the character's level
	## does not enter; magic find is whatever is worn, nothing for --fresh).
	var db := get_node("/root/ItemDB")
	var gen := get_node("/root/ItemGen")
	const RUNS := 20
	var grand := {"kills": 0, "drops": 0.0, "gear": 0.0, "rare": 0.0, "set": 0.0, "unique": 0.0}
	for did in ["ragefire-chasm", "wailing-caverns", "deadmines", "shadowfang-keep"]:
		var base := _assets_dir().path_join("wow/%s" % did)
		var placements := _load_json(base.path_join("placements.json"))
		var cinfo := _load_json(base.path_join("creatures/creatures.json"))
		var spawns: Array = placements.get("creatures", [])
		var tally := {"drops": 0, "gear": 0, "rare": 0, "set": 0, "unique": 0}
		var kills := 0
		var names := {}
		for run in range(RUNS):
			for c in spawns:
				var key := str(int(c["entry"]))
				if not cinfo.has(key):
					continue
				var st: Dictionary = cinfo[key].get("stats", {})
				if bool(st.get("passive", false)):
					continue
				if run == 0:
					kills += 1
				var kind := str(st.get("kind", "normal"))
				if bool(st.get("final_boss", false)):
					kind = "final"
				for res in db.drops_for(int(st.get("Level", 1)), kind,
						str(st.get("archetype", "melee"))):
					tally["drops"] += 1
					var inst: Dictionary = res["inst"]
					if int(res["gold"]) > 0:
						continue
					var it: Dictionary = db.item(str(res["code"]))
					if not gen._equippable(gen.type_chain(str(it.get("type", "")))):
						continue
					tally["gear"] += 1
					var qual := str(inst.get("quality", "normal"))
					if tally.has(qual):
						tally[qual] += 1
					if qual in ["set", "unique"] and run == 0:
						names[str(inst.get("name", ""))] = int(names.get(str(inst.get("name", "")), 0)) + 1
		print("LOOT-RUN %-16s kills %3d  per clear: drops %5.0f  gear %4.0f  rare %5.1f  set %4.1f  unique %4.1f" % [
				did, kills, float(tally["drops"]) / RUNS, float(tally["gear"]) / RUNS,
				float(tally["rare"]) / RUNS, float(tally["set"]) / RUNS,
				float(tally["unique"]) / RUNS])
		var sample := []
		for n in names:
			sample.append("%s x%d" % [n, names[n]] if names[n] > 1 else n)
		print("LOOT-RUN   one clear's sets/uniques: %s" % ", ".join(sample))
		grand["kills"] += kills
		for k in ["drops", "gear", "rare", "set", "unique"]:
			grand[k] += float(tally[k]) / RUNS
	print("LOOT-RUN TOTAL kills %d  per full clear of four: drops %.0f  gear %.0f  rare %.1f  set %.1f  unique %.1f" % [
			grand["kills"], grand["drops"], grand["gear"], grand["rare"], grand["set"], grand["unique"]])


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
			or (char_ui != null and char_ui.open) \
			or (menu_ui != null and menu_ui.open)
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
			if not _try_interact():
				_pickup_nearest()
		elif e.keycode >= KEY_1 and e.keycode <= KEY_4:
			# an open panel owns the number keys: the skill tree uses 1-3 for
			# its tabs, and switching tabs used to drink the matching potion
			if player != null and not player.ui_locked:
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
		elif e.keycode == KEY_F11:
			Cli.toggle_fullscreen()
			get_viewport().set_input_as_handled()
		elif e.keycode == KEY_ESCAPE:
			# Esc closes panels first; with nothing open it toggles the menu
			var closed := false
			for panel in [inv_ui, tree_ui, char_ui]:
				if panel != null and panel.open:
					panel.toggle()
					closed = true
			if closed:
				_sync_ui()
			else:
				toggle_menu()


func toggle_menu() -> void:
	if menu_ui == null:
		return
	menu_ui.toggle()
	_sync_ui()


func _process(_dt: float) -> void:
	if hud_node == null or player == null:
		return
	if (Input.is_key_pressed(KEY_ALT) or force_labels) and not ground_items.is_empty():
		var cam: Camera3D = player.get_node("Camera3D")
		hud_node.show_item_labels(_visible_items(cam), cam)
	else:
		hud_node.hide_item_labels()
	# creature under the crosshair -> D2-style name + health plate up top
	var cam2: Camera3D = player.get_node("Camera3D")
	var from := cam2.global_position
	var q := PhysicsRayQueryParameters3D.create(
		from, from - cam2.global_transform.basis.z * 45.0)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit["collider"] is WowCreature \
			and hit["collider"].state != WowCreature.State.DEAD:
		hud_node.show_target(hit["collider"])
	else:
		hud_node.hide_target()
	# name whatever E would act on from here
	var use_name := ""
	var use_d := INTERACT_RANGE
	for it in interactables:
		if it["used"]:
			continue
		var ud: float = player.global_position.distance_to(
				(it["node"] as Node3D).global_position)
		if ud < use_d:
			use_d = ud
			use_name = str(it["name"])
	if use_name == "":
		hud_node.hide_interact()
	else:
		hud_node.show_interact(use_name)


func _visible_items(cam: Camera3D) -> Array:
	## Alt labels only for loot the player can actually see. A ray from the eye
	## to each drop; a wall between them (StaticBody3D, same test wow_creature
	## uses for sight) hides the label. Creatures don't occlude — a mob walking
	## across the pile shouldn't blink the labels. GroundItems are Sprite3D with
	## no body, so the ray never catches the item itself.
	var out: Array = []
	var ss := get_world_3d().direct_space_state
	var from: Vector3 = cam.global_position
	for gi in ground_items:
		if not is_instance_valid(gi):
			continue
		var to: Vector3 = gi.global_position + Vector3.UP * 0.3
		var span := from.distance_to(to)
		if span > 45.0:
			continue
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = [player.get_rid()]
		var hit := ss.intersect_ray(q)
		if hit and hit["collider"] is StaticBody3D \
				and from.distance_to(hit["position"]) < span - 0.5:
			continue
		out.append(gi)
	return out


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_node("/root/GameState").save_game(player)
		get_tree().quit()


# ---------------------------------------------------------------------------
# Verification modes
# ---------------------------------------------------------------------------
func _spawn_shots() -> void:
	if Cli.offscreen():
		Cli.hide_window()
	await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	for k in 4:
		player.yaw = spawn_yaw + k * PI / 2.0
		await get_tree().process_frame
		await Cli.capture(get_viewport(), _shot_dir.path_join("spawn_%d.png" % k))
	print("spawn shots done (window %s)" % (
			"minimized" if DisplayServer.window_get_mode()
			== DisplayServer.WINDOW_MODE_MINIMIZED else "on screen"))


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
