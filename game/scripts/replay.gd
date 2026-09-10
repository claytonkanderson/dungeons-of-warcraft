extends Node
## Autoloaded as Replay: records what a session looked like, and plays a
## recording back as puppetry. Nothing is simulated on playback: the world
## builds its geometry as usual, then every tick the player, the creatures,
## the projectiles and effects (every BillboardAnim under the world), the
## items on the floor, the doors, the HUD numbers and the panels are placed
## from the log, and the sounds it heard are played again. So a replay
## cannot drift, and gameplay code owes it nothing beyond what is logged.
##
## Recording is on with --record (run_game.bat passes it) or the
## record_sessions line in settings.json, and off with --no-record;
## --replay=<log> plays one back.
## render_replay.bat runs a playback under Godot's movie maker
## (--write-movie, --fixed-fps 60), one frame per tick, to a video.
##
## A log (user://sessions/<stamp>-<character>-<dungeon>.jsonl), one JSON
## object per line, only the ticks with something to say:
##   header  {"h":2, "dungeon", "character", "state": <save dict>,
##            "tick_rate", "sample"}
##   tick    {"t":n,
##            "p":[x,y,z,yaw,pitch]            player, every tick it moved
##            "h":[hp,mana,stamina,xp,level,gold,poisoned]   on change
##            "l":1                            loot labels held
##            "c":{rid:[x,y,z,yaw,clip,speed,hp]}  creatures that changed,
##                                             every `sample` ticks
##            "c-":[rid]                       corpses gone
##            "b":{bid:[sheet,loop,anchor,x,y,z,facing]}  billboards: arrows,
##                                             missiles, bolts, summons
##            "b-":[bid]
##            "i":{iid:[code,gold,inst,x,y,z]} items dropped
##            "i-":[iid]                       picked up
##            "d":[door index]                 doors that opened
##            "u":[inv,tree,char,menu]         panel visibility changed
##            "m":[x,y]                        the cursor while a panel is open
##                                             (canvas pixels), so hover
##                                             tooltips show on playback
##            "s": <save dict>                 the character, with "u"
##            "e":[[kind, ...], ...]           sounds, HUD flashes, area text
##           }
## Playback interpolates positions between samples that are close in time,
## so a 20 Hz world sample still moves smoothly at 60 frames a second.

# LIVE: a co-op joiner. The host's ticks arrive over the network (net.gd)
# in this same format and are played as puppetry a few ticks behind, the
# player's own Amazon and HUD left alone.
enum Mode { OFF, RECORD, PLAY, LIVE }

const FORMAT := 2
const DIR := "user://sessions"
const SAMPLE_EVERY := 3          # ticks between world samples (20 Hz at 60)
const TAIL_TICKS := 60           # ticks a playback runs on past its last line
const DORMANT_DIST := 45.0       # puppet creatures this far off stop animating
const LIVE_JITTER := 6           # ticks a joiner plays behind the newest line
const LIVE_KEEP := 120           # ticks of history a joiner keeps

var mode: int = Mode.OFF
var tick := -1                   # -1 until armed; the first tick is 0
var path := ""
var alt := false                 # PLAY: the loot labels were held this tick
var world: Node = null
var player: Node = null

var _armed := false
var _file: FileAccess = null
var _header := {}

# ---- record: the last values written, so only changes go to the file
var _last_p: Array = []
var _last_h: Array = []
var _creatures := {}             # rid -> WowCreature (fixed at arm)
var _last_c := {}                # rid -> Array
var _bb_ids := {}                # instance id -> bid
var _bb_last := {}               # bid -> Array
var _bb_next := 0
var _item_ids := {}              # instance id -> iid
var _item_next := 0
var _doors_open: Array = []
var _events: Array = []
var _ui_line = null              # [flags, state] pending for this tick
var _last_m: Array = []          # the cursor last written (record) or seen (play)
var cursor_override := Vector2.INF   # a scripted session's pretend cursor

# ---- play: the log and the puppets
var _ticks := {}                 # tick -> line
var _last_tick := 0
var _pkeys: Array = []           # [[t, arr], ...] player
var _pcur := 0
var _ckeys := {}                 # rid -> [[t, arr], ...]
var _ccur := {}
var _cclip := {}                 # rid -> clip last played
var _bkeys := {}                 # bid -> [[t, arr], ...]
var _bcur := {}
var _bnodes := {}                # bid -> BillboardAnim
var _inodes := {}                # iid -> GroundItem
var _used: Array = []            # record: interactables used, mirrored like doors
var stream := false              # RECORD: the host sends each tick to the joiners
var _live_latest := -1           # LIVE: the newest host tick received
var live_received := 0


func _ready() -> void:
	# after every gameplay node: a sample is what the tick left behind
	process_physics_priority = 100
	process_mode = Node.PROCESS_MODE_ALWAYS


func recording() -> bool:
	return mode == Mode.RECORD


func playing() -> bool:
	return mode == Mode.PLAY


func live() -> bool:
	return mode == Mode.LIVE


# ---------------------------------------------------------------------------
# Session lifecycle: the world calls these around its build
# ---------------------------------------------------------------------------
func load_replay(p: String, gs: Node) -> bool:
	## --replay=<path>: read the log and put its character and dungeon into
	## GameState. The world then builds as usual and is puppeted from arm().
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		printerr("replay: cannot open %s" % p)
		return false
	_ticks.clear()
	_pkeys.clear()
	_ckeys.clear()
	_bkeys.clear()
	_header = {}
	_last_tick = 0
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var d = JSON.parse_string(line)
		if not (d is Dictionary):
			continue
		if not d.has("t"):
			if d.has("h"):
				_header = d      # the header: no tick, unlike a HUD "h" line
			continue
		var t := int(d["t"])
		_ticks[t] = d
		_last_tick = maxi(_last_tick, t)
		if d.has("p"):
			_pkeys.append([t, d["p"]])
		if d.has("c"):
			for rid in d["c"]:
				if not _ckeys.has(rid):
					_ckeys[rid] = []
				_ckeys[rid].append([t, d["c"][rid]])
		if d.has("b"):
			for bid in d["b"]:
				if not _bkeys.has(bid):
					_bkeys[bid] = []
				_bkeys[bid].append([t, d["b"][bid]])
	f.close()
	if _header.is_empty():
		printerr("replay: %s has no header" % p)
		return false
	if int(_header.get("h", 0)) != FORMAT:
		printerr("replay: %s is format %s; this build plays format %d (state logs)"
				% [p, _header.get("h"), FORMAT])
		return false
	mode = Mode.PLAY
	path = p
	gs.character = str(_header.get("character", ""))
	gs.apply(_header.get("state", {}), null)
	gs.current_dungeon = str(_header.get("dungeon", gs.current_dungeon))
	gs.session_loaded = true
	print("replay: %s, %d ticks (%.1f s)" % [p, _last_tick + 1,
			float(_last_tick + 1) / Engine.physics_ticks_per_second])
	return true


func begin_session(gs: Node) -> void:
	## Before the world builds: open the log and write the header when this
	## session is to be recorded. Idempotent within a session.
	if mode != Mode.OFF:
		return
	if Net.is_client():
		mode = Mode.LIVE          # the host's stream is this session's log
		return
	if Net.is_host():
		# the host samples every tick for the joiners whether or not it
		# keeps a file of its own
		mode = Mode.RECORD
		stream = true
	if Cli.has("--no-record") or Cli.has("--replay="):
		return
	if not (Cli.has("--record") or get_node("/root/Settings").record_sessions):
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var who: String = str(gs.character) if str(gs.character) != "" else "amazon"
	path = DIR.path_join("%s-%s-%s.jsonl" % [stamp, who, gs.current_dungeon])
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		printerr("replay: cannot write %s, not recording" % path)
		return
	mode = Mode.RECORD
	_header = {"h": FORMAT, "dungeon": gs.current_dungeon,
			"character": gs.character, "state": gs.snapshot(null),
			"tick_rate": Engine.physics_ticks_per_second, "sample": SAMPLE_EVERY}
	_file.store_line(JSON.stringify(_header))
	print("recording session to %s" % ProjectSettings.globalize_path(path))


func end_session() -> void:
	## The world left the tree (back to the menu, or quitting): stop ticking,
	## flush and close the log. The next dungeon starts a new session.
	_armed = false
	if _file != null:
		_file.flush()
		_file.close()
		_file = null
	if mode == Mode.RECORD and path != "":
		print("session log closed: %s" % ProjectSettings.globalize_path(path))
	if mode != Mode.PLAY:
		mode = Mode.OFF
	stream = false
	path = ""
	_live_latest = -1
	_ticks.clear()
	_pkeys.clear()
	_ckeys.clear()
	_bkeys.clear()
	world = null
	player = null


func arm(w: Node, p: Node) -> void:
	## After the world is built: the next physics tick is tick 0. Recording
	## learns the cast; playback turns it into puppets.
	world = w
	player = p
	tick = -1
	_creatures.clear()
	_last_c.clear()
	_last_p = []
	_last_h = []
	_bb_ids.clear()
	_bb_last.clear()
	_item_ids.clear()
	_doors_open = []
	for d in world.doors:
		_doors_open.append(bool(d["open"]))
	_used = []
	for it in world.interactables:
		_used.append(bool(it["used"]))
	for i in range(world.monsters.size()):
		_creatures[i] = world.monsters[i]
	_ccur.clear()
	_cclip.clear()
	_bcur.clear()
	_bnodes.clear()
	_inodes.clear()
	_pcur = 0
	if mode == Mode.PLAY:
		world.puppet = true
		player.puppet = true
		for mob in world.monsters:
			mob.puppet = true
		get_node("/root/GameState").set_physics_process(false)
	elif mode == Mode.LIVE:
		# the creatures are the host's: placed from the stream, and every
		# blow at them goes there to be applied
		for mob in world.monsters:
			mob.puppet = true
			mob.remote = true
		_ticks.clear()
		_pkeys.clear()
		_ckeys.clear()
		_bkeys.clear()
		_live_latest = -1
		live_received = 0
	_armed = mode != Mode.OFF


# ---------------------------------------------------------------------------
# Recording hooks: sounds, HUD flashes, panels
# ---------------------------------------------------------------------------
func log_event(ev: Array) -> void:
	if mode == Mode.RECORD and _armed:
		_events.append(ev)


func log_ui(flags: Array, state: Dictionary) -> void:
	if mode == Mode.RECORD and _armed:
		_ui_line = [flags, state]


# ---------------------------------------------------------------------------
# The tick
# ---------------------------------------------------------------------------
func _physics_process(_dt: float) -> void:
	if not _armed or world == null or not is_instance_valid(player):
		return
	if mode == Mode.LIVE:
		_live_step()
		return
	tick += 1
	if mode == Mode.RECORD:
		_record_tick()
	elif mode == Mode.PLAY:
		_play_tick()


func _live_step() -> void:
	## A joiner's clock: one host tick per physics tick, a jitter buffer
	## behind the newest line; held when the stream stalls, caught up in a
	## few steps when it runs ahead (every tick is played, so nothing that
	## happens once is skipped).
	if _live_latest < 0:
		return
	var target := _live_latest - LIVE_JITTER
	if tick < 0:
		tick = target - 1
	if tick >= target:
		return
	var steps := 1
	if target - tick > LIVE_JITTER * 2:
		steps = mini(target - tick, 10)
	for i in range(steps):
		tick += 1
		_play_tick()
	if tick % 300 == 0:
		_prune_live()


func live_line(line: Dictionary) -> void:
	## Net: one of the host's ticks (or its whole state, for a late arrival)
	if mode != Mode.LIVE or not line.has("t"):
		return
	var t := int(line["t"])
	live_received += 1
	if _ticks.has(t):
		_ticks[t].merge(line, true)
	else:
		_ticks[t] = line
	_live_latest = maxi(_live_latest, t)
	if line.has("p"):
		_pkeys.append([t, line["p"]])
	if line.has("c"):
		for rid in line["c"]:
			if not _ckeys.has(rid):
				_ckeys[rid] = []
			_ckeys[rid].append([t, line["c"][rid]])
	if line.has("b"):
		for bid in line["b"]:
			if not _bkeys.has(bid):
				_bkeys[bid] = []
			_bkeys[bid].append([t, line["b"][bid]])


func _prune_live() -> void:
	var cut := tick - LIVE_KEEP
	for t in _ticks.keys():
		if int(t) < cut:
			_ticks.erase(t)
	_pcur = _prune_keys(_pkeys, _pcur, cut)
	for rid in _ckeys:
		_ccur[rid] = _prune_keys(_ckeys[rid], int(_ccur.get(rid, 0)), cut)
	for bid in _bkeys:
		_bcur[bid] = _prune_keys(_bkeys[bid], int(_bcur.get(bid, 0)), cut)


static func _prune_keys(keys: Array, cur: int, cut: int) -> int:
	## drop keys older than cut, keeping the one the cursor is on
	var drop := 0
	while drop < cur and drop + 1 < keys.size() and int(keys[drop + 1][0]) < cut:
		drop += 1
	if drop > 0:
		for i in range(drop):
			keys.pop_front()
		cur -= drop
	return cur


func snapshot_line() -> Dictionary:
	## Host: everything a joiner arriving now needs, as one line of the
	## stream: every creature, every drop on the floor, the doors open and
	## the chests used so far.
	var line := {"t": tick}
	var cs := {}
	var gone: Array = []
	for rid in _creatures:
		var mob = _creatures[rid]
		if not is_instance_valid(mob) or mob.is_queued_for_deletion():
			gone.append(rid)
			continue
		var a: Array = _v3(mob.global_position, 0.01)
		a.append(snappedf(mob.rotation.y, 0.001))
		a.append(mob.anim.current_animation if mob.anim != null else "")
		a.append(snappedf(mob.anim.speed_scale, 0.01) if mob.anim != null else 1.0)
		a.append(snappedf(mob.hp, 0.1))
		cs[str(rid)] = a
	line["c"] = cs
	if not gone.is_empty():
		line["c-"] = gone
	var items := {}
	for gi in world.ground_items:
		if not is_instance_valid(gi) or gi.is_queued_for_deletion():
			continue
		var iid: int = gi.get_instance_id()
		if not _item_ids.has(iid):
			_item_ids[iid] = _item_next
			_item_next += 1
		var rec: Array = [gi.code, gi.gold_amount, gi.instance]
		rec.append_array(_v3(gi.global_position, 0.01))
		items[str(_item_ids[iid])] = rec
	if not items.is_empty():
		line["i"] = items
	var opened: Array = []
	for i in range(world.doors.size()):
		if bool(world.doors[i]["open"]):
			opened.append(i)
	if not opened.is_empty():
		line["d"] = opened
	var used: Array = []
	for i in range(world.interactables.size()):
		if bool(world.interactables[i]["used"]):
			used.append(i)
	if not used.is_empty():
		line["x"] = used
	if not _last_p.is_empty():
		line["p"] = _last_p
	return line


func item_by_id(iid: int) -> GroundItem:
	## Host: the drop a joiner named (the stream's item ids)
	for inst_id in _item_ids:
		if int(_item_ids[inst_id]) == iid:
			var gi = instance_from_id(int(inst_id))
			if gi is GroundItem and is_instance_valid(gi) and not gi.is_queued_for_deletion():
				return gi
	return null


static func _v3(v: Vector3, step: float) -> Array:
	return [snappedf(v.x, step), snappedf(v.y, step), snappedf(v.z, step)]


func _record_tick() -> void:
	var line := {"t": tick}
	var pa: Array = _v3(player.global_position, 0.001)
	pa.append(snappedf(player.yaw, 0.0001))
	pa.append(snappedf(player.pitch, 0.0001))
	if pa != _last_p:
		line["p"] = pa
		_last_p = pa
	var gs := get_node("/root/GameState")
	var h: Array = [snappedf(gs.hp, 0.1), snappedf(gs.mana, 0.1),
			snappedf(player.stamina, 0.1), float(gs.xp), float(gs.level),
			float(gs.gold), 1.0 if gs.is_poisoned() else 0.0]
	# the HUD numbers at the world's rate: stamina and mana creep every tick
	if h != _last_h and tick % SAMPLE_EVERY == 0:
		line["h"] = h
		_last_h = h
	if Input.is_key_pressed(KEY_ALT):
		line["l"] = 1
	# the cursor while a panel owns it: hover tooltips are worth seeing
	if player.ui_locked:
		var mp: Vector2 = cursor_override if cursor_override != Vector2.INF 				else world.get_viewport().get_mouse_position()
		var m: Array = [roundf(mp.x), roundf(mp.y)]
		if m != _last_m or _ui_line != null:
			line["m"] = m
			_last_m = m
	else:
		_last_m = []
	if tick % SAMPLE_EVERY == 0:
		_sample_world(line)
	if not _events.is_empty():
		line["e"] = _events
		_events = []
	if _ui_line != null:
		line["u"] = _ui_line[0]
		line["s"] = _ui_line[1]
		_ui_line = null
	if line.size() > 1:
		if _file != null:
			_file.store_line(JSON.stringify(line))
		if stream:
			# the joiners need the world and the host's pose, not its panels
			var out := line.duplicate()
			for k in ["h", "l", "m", "u", "s"]:
				out.erase(k)
			if out.size() > 1:
				Net.send_line(out)
	if _file != null and tick % 300 == 0:
		_file.flush()


func _sample_world(line: Dictionary) -> void:
	# creatures
	var cs := {}
	var cgone: Array = []
	for rid in _creatures:
		var mob = _creatures[rid]
		if not is_instance_valid(mob) or mob.is_queued_for_deletion():
			if _last_c.has(rid):
				cgone.append(rid)
				_last_c.erase(rid)
			continue
		var a: Array = _v3(mob.global_position, 0.01)
		a.append(snappedf(mob.rotation.y, 0.001))
		a.append(mob.anim.current_animation if mob.anim != null else "")
		a.append(snappedf(mob.anim.speed_scale, 0.01) if mob.anim != null else 1.0)
		a.append(snappedf(mob.hp, 0.1))
		if _last_c.get(rid) != a:
			cs[str(rid)] = a
			_last_c[rid] = a
	if not cs.is_empty():
		line["c"] = cs
	if not cgone.is_empty():
		line["c-"] = cgone
	# billboards under the world (arrows, enemy missiles, bolts, explosions)
	# and the summons, which carry theirs
	var bs := {}
	var seen := {}
	for ch in world.get_children():
		if ch is BillboardAnim and not (ch is GroundItem):
			_sample_billboard(ch, ch, bs, seen)
	for f in world.friendlies:
		if is_instance_valid(f) and f.anim != null:
			_sample_billboard(f, f.anim, bs, seen)
	var bgone: Array = []
	for bid in _bb_last.keys():
		if not seen.has(bid):
			bgone.append(bid)
			_bb_last.erase(bid)
	if not bs.is_empty():
		line["b"] = bs
	if not bgone.is_empty():
		line["b-"] = bgone
	# items on the floor
	var items := {}
	var iseen := {}
	for gi in world.ground_items:
		if not is_instance_valid(gi) or gi.is_queued_for_deletion():
			continue
		var iid: int = gi.get_instance_id()
		if not _item_ids.has(iid):
			_item_ids[iid] = _item_next
			_item_next += 1
			var rec: Array = [gi.code, gi.gold_amount, gi.instance]
			rec.append_array(_v3(gi.global_position, 0.01))
			items[str(_item_ids[iid])] = rec
		iseen[int(_item_ids[iid])] = true
	var igone: Array = []
	for iid in _item_ids.keys():
		var id: int = _item_ids[iid]
		if not iseen.has(id):
			igone.append(id)
			_item_ids.erase(iid)
	if not items.is_empty():
		line["i"] = items
	if not igone.is_empty():
		line["i-"] = igone
	# doors
	var opened: Array = []
	for i in range(world.doors.size()):
		var is_open := bool(world.doors[i]["open"])
		if is_open and not _doors_open[i]:
			opened.append(i)
		_doors_open[i] = is_open
	if not opened.is_empty():
		line["d"] = opened
	# chests, veins and cannons used (the joiners' prompts drop them)
	var used: Array = []
	for i in range(world.interactables.size()):
		var u := bool(world.interactables[i]["used"])
		if u and not _used[i]:
			used.append(i)
		_used[i] = u
	if not used.is_empty():
		line["x"] = used


func _sample_billboard(owner: Node, bb: BillboardAnim, bs: Dictionary, seen: Dictionary) -> void:
	if owner.is_queued_for_deletion() or bb.rel == "":
		return
	var iid: int = owner.get_instance_id()
	if not _bb_ids.has(iid):
		_bb_ids[iid] = _bb_next
		_bb_next += 1
	var bid: int = _bb_ids[iid]
	seen[bid] = true
	var a: Array = [bb.rel, 1 if bb.looping else 0, bb.anchor]
	a.append_array(_v3(owner.global_position, 0.01))
	a.append(snappedf(bb.facing, 0.001))
	if _bb_last.get(bid) != a:
		bs[str(bid)] = a
		_bb_last[bid] = a


# ---------------------------------------------------------------------------
# Playback
# ---------------------------------------------------------------------------
static func _seek(keys: Array, cur: int, t: int) -> int:
	while cur + 1 < keys.size() and int(keys[cur + 1][0]) <= t:
		cur += 1
	return cur


static func _blend(keys: Array, cur: int, t: int) -> float:
	## 0..1 toward the next key when it is one sample away; else 0 (hold).
	if cur + 1 >= keys.size():
		return 0.0
	var t0 := int(keys[cur][0])
	var t1 := int(keys[cur + 1][0])
	if t1 - t0 > SAMPLE_EVERY * 2 or t >= t1:
		return 0.0
	return float(t - t0) / float(t1 - t0)


func _play_tick() -> void:
	var line: Dictionary = _ticks.get(tick, {})
	var gs := get_node("/root/GameState")
	var is_live := mode == Mode.LIVE
	# the character and the panels, before anything reads them
	if line.has("s") and not is_live:
		gs.apply(line["s"], player)
		player.refresh_attack_style()
	if line.has("u") and not is_live:
		_set_panels(line["u"])
	if line.has("m") and not is_live:
		_last_m = line["m"]
	if (line.has("m") or line.has("u")) and not is_live:
		_inject_cursor()
	if line.has("h") and not is_live:
		var h: Array = line["h"]
		gs.hp = float(h[0])
		gs.mana = float(h[1])
		player.stamina = float(h[2])
		gs.xp = int(h[3])
		gs.level = int(h[4])
		gs.gold = int(h[5])
		gs.poison_t = 1.0 if float(h[6]) > 0.0 else 0.0
		gs.hp_changed.emit()
		gs.xp_changed.emit()
	alt = line.has("l") and not is_live
	# the player: the recording's own, or in a co-op session the host's
	# Amazon as a puppet beside this player's own
	if not _pkeys.is_empty():
		_pcur = _seek(_pkeys, _pcur, tick)
		var k: Array = _pkeys[_pcur][1]
		if is_live:
			Net.host_pose(k)
		else:
			player.global_position = Vector3(float(k[0]), float(k[1]), float(k[2]))
			player.yaw = float(k[3])
			player.pitch = float(k[4])
	# creatures: hold or blend between samples
	for rid in _ckeys:
		var keys: Array = _ckeys[rid]
		var cur: int = _seek(keys, int(_ccur.get(rid, 0)), tick)
		_ccur[rid] = cur
		if int(keys[cur][0]) > tick:
			continue
		var mob = _creatures.get(str(rid).to_int())
		if mob == null or not is_instance_valid(mob):
			continue
		var a: Array = keys[cur][1]
		var pos := Vector3(float(a[0]), float(a[1]), float(a[2]))
		var yaw := float(a[3])
		var f := _blend(keys, cur, tick)
		if f > 0.0:
			var b: Array = keys[cur + 1][1]
			pos = pos.lerp(Vector3(float(b[0]), float(b[1]), float(b[2])), f)
			yaw = lerp_angle(yaw, float(b[3]), f)
		mob.global_position = pos
		mob.rotation.y = yaw
		mob.hp = float(a[6])
		mob.state = WowCreature.State.DEAD if mob.hp <= 0.0 else WowCreature.State.IDLE
		if mob.anim != null:
			var clip := str(a[4])
			if clip != "" and _cclip.get(rid, "") != clip and mob.anim.has_animation(clip):
				mob.anim.play(clip, 0.2)
				_cclip[rid] = clip
			mob.anim.speed_scale = float(a[5])
			var far: bool = mob.hp > 0.0 and clip == str(mob.clips.get("stand", "")) \
					and mob.global_position.distance_to(player.global_position) > DORMANT_DIST
			mob.anim.process_mode = Node.PROCESS_MODE_DISABLED if far \
					else Node.PROCESS_MODE_INHERIT
	if line.has("c-"):
		for rid in line["c-"]:
			var key := int(float(rid))
			var mob = _creatures.get(key)
			if mob != null and is_instance_valid(mob):
				mob.queue_free()
			_creatures.erase(key)
	# billboards
	for bid in _bkeys:
		var keys: Array = _bkeys[bid]
		var cur: int = _seek(keys, int(_bcur.get(bid, 0)), tick)
		_bcur[bid] = cur
		if int(keys[cur][0]) > tick:
			continue
		var a: Array = keys[cur][1]
		var node = null
		if _bnodes.has(bid):
			node = _bnodes[bid]
			if node != null and not is_instance_valid(node):
				_bnodes[bid] = null     # a one-shot that finished and freed itself
				node = null
			if node == null:
				continue
		if node == null:
			node = BillboardAnim.new()
			world.add_child(node)
			node.play(str(a[0]), int(a[1]) == 1, str(a[2]))
			_bnodes[bid] = node
			if int(a[1]) == 0:
				node.finished.connect(node.queue_free)
		elif node.rel != str(a[0]):
			node.play(str(a[0]), int(a[1]) == 1, str(a[2]))
		var pos := Vector3(float(a[3]), float(a[4]), float(a[5]))
		var facing := float(a[6])
		var f := _blend(keys, cur, tick)
		if f > 0.0:
			var b: Array = keys[cur + 1][1]
			pos = pos.lerp(Vector3(float(b[3]), float(b[4]), float(b[5])), f)
			facing = lerp_angle(facing, float(b[6]), f)
		node.global_position = pos
		node.facing = facing
	if line.has("b-"):
		for bid in line["b-"]:
			var key := str(int(float(bid)))
			var node = _bnodes.get(key)
			if node != null and is_instance_valid(node):
				node.queue_free()
			_bnodes[key] = null
	# items
	if line.has("i"):
		for iid in line["i"]:
			var rec: Array = line["i"][iid]
			var gi := GroundItem.new()
			gi.silent = true      # the log carries the drop's sound event
			world.add_child(gi)
			var inst = rec[2]
			if inst is Dictionary and not inst.is_empty():
				gi.drop_instance(inst)
			else:
				gi.drop(str(rec[0]), int(rec[1]))
			gi.global_position = Vector3(float(rec[3]), float(rec[4]), float(rec[5]))
			gi.set_meta("iid", int(str(iid)))
			world.ground_items.append(gi)
			_inodes[str(iid)] = gi
	if line.has("i-"):
		for iid in line["i-"]:
			var key := str(int(float(iid)))
			var gi = _inodes.get(key)
			if gi != null and is_instance_valid(gi):
				world.ground_items.erase(gi)
				gi.queue_free()
			_inodes.erase(key)
	if line.has("d"):
		for i in line["d"]:
			if int(i) < world.doors.size():
				world._open_door(world.doors[int(i)], false, true)
	if line.has("x"):
		for i in line["x"]:
			if int(i) < world.interactables.size():
				world.interactables[int(i)]["used"] = true
	if line.has("e"):
		_play_events(line["e"])
	if is_live:
		return
	if tick > _last_tick + TAIL_TICKS:
		print("REPLAY done: %d ticks" % tick)
		_armed = false
		get_tree().quit()


func _inject_cursor() -> void:
	## Move the (unseen) cursor to where the session's was, through the
	## input pipeline, so the panels' hover states and tooltips follow.
	if _last_m.is_empty():
		return
	var ev := InputEventMouseMotion.new()
	var canvas := Vector2(float(_last_m[0]), float(_last_m[1]))
	ev.position = world.get_viewport().get_final_transform() * canvas
	ev.global_position = ev.position
	Input.parse_input_event(ev)


func _set_panels(flags: Array) -> void:
	var panels := [world.inv_ui, world.tree_ui, world.char_ui, world.menu_ui]
	for i in range(mini(4, flags.size())):
		var panel = panels[i]
		if panel != null and panel.open != bool(flags[i]):
			panel.toggle()
	world._sync_ui()


func _play_events(evs: Array) -> void:
	var sfx := get_node("/root/Sfx")
	var wsfx := get_node("/root/WowSfx")
	var hud = world.hud_node
	var is_live := mode == Mode.LIVE
	for ev in evs:
		var kind := str(ev[0])
		# a joiner hears the world's sounds; the host's own footsteps, HUD
		# flashes and zone titles are the host's
		if is_live and not (kind in ["sfx", "smon", "voice", "imp"]):
			continue
		match kind:
			"sfx":
				sfx.event(str(ev[1]), Vector3(float(ev[2]), float(ev[3]), float(ev[4])))
			"sui":
				sfx.event_ui(str(ev[1]), float(ev[2]))
			"smon":
				sfx.monster(str(ev[1]), str(ev[2]),
						Vector3(float(ev[3]), float(ev[4]), float(ev[5])))
			"voice":
				wsfx.voice(str(ev[1]), str(ev[2]),
						Vector3(float(ev[3]), float(ev[4]), float(ev[5])))
			"imp":
				wsfx.impact(str(ev[1]), Vector3(float(ev[2]), float(ev[3]), float(ev[4])))
			"kick":
				if hud != null:
					hud.kick()
			"block":
				if hud != null:
					hud.block_flash()
			"area":
				if hud != null:
					hud.show_area(str(ev[1]), Color.html(str(ev[2])), float(ev[3]))
