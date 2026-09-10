extends Node
## Autoloaded as Net: co-op sessions over the internet, straight between the
## players' machines (no server in between). One player hosts; the host's
## router is asked to open the port through UPnP and the host's public
## address is what the others type in. Up to four in a session.
##
## The host runs the dungeon: creatures, drops, doors and chests live only
## there, and what changes each tick goes to the others as the same state
## stream a session recording is made of (replay.gd), which their world
## plays as puppetry. Each player simulates their own Amazon — movement,
## aim, arrows, skills, the D2 hit rolls against their own gear — and what
## lands on a creature is sent to the host to apply. Creatures pick their
## targets among every player; a blow at someone else's Amazon goes to
## that player, who rolls their own defence against it. Drops are the
## host's until a player asks for one, when the host hands it over; kills
## pay every player their experience, as a D2 party does.
##
## The transport came from the p2p-nat-spike: ENet, UPnP mapping renewed
## every five minutes (routers expire it), the public address from the
## internet's side, and a verdict on whether this side can host at all.

signal log_line(text: String)
signal roster_changed
signal status_changed
signal launched(did: String)          # everyone: the host started a dungeon
signal start_refused(who: String, did: String, why: String)
signal session_ended(why: String)     # this side is out of the session

const APP := "dungeons-of-warcraft"
const PORT := 24601
const MAX_PLAYERS := 4
const RENEW_SEC := 300.0
const POSE_EVERY := 3                 # ticks between pose sends (20 Hz at 60)
# A world takes ten to thirty seconds to build, during which that machine
# answers nothing; ENet's stock timeout (about five seconds) dropped a
# joiner for exactly that. Both ends give the other a couple of minutes.
const TIMEOUT_MIN_MS := 60000
const TIMEOUT_MAX_MS := 150000
const CHANNEL_STREAM := 0
const CHANNEL_POSE := 1
const CHANNEL_FX := 2

enum Role { OFF, HOST, CLIENT }

var role: int = Role.OFF
var peer: ENetMultiplayerPeer
var public_ip := ""
var upnp_external := ""
var mapped := false
var status := ""                      # one line for the lobby
var roster := {}                      # peer id -> {"name", "level", "wclass"}
var session_dungeon := ""
var last_error := ""                  # for the menu after a drop

var world = null                      # the World while in a dungeon
var remote := {}                      # peer id -> RemotePlayer
var _pending := {}                    # host: did -> {peer id: bool}
var _upnp: UPNP
var _upnp_thread: Thread
var _upnp_state := ""
var _http: HTTPRequest
var _renew_timer: Timer
var _renewals := 0
var _sent := 0
var _got := 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_public_ip)
	_renew_timer = Timer.new()
	_renew_timer.wait_time = RENEW_SEC
	_renew_timer.timeout.connect(_renew_tick)
	add_child(_renew_timer)


func _exit_tree() -> void:
	_unmap()
	if _upnp_thread != null and _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()


func log_it(text: String) -> void:
	var line := "[%s] net: %s" % [Time.get_time_string_from_system(), text]
	print(line)
	log_line.emit(line)


func _set_status(s: String) -> void:
	status = s
	status_changed.emit()


func is_host() -> bool:
	return role == Role.HOST


func is_client() -> bool:
	return role == Role.CLIENT


func active() -> bool:
	## in a session with the transport up
	return role != Role.OFF and peer != null \
			and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func player_count() -> int:
	return 1 + multiplayer.get_peers().size() if active() else 1


func my_id() -> int:
	return multiplayer.get_unique_id() if active() else 1


func player_index() -> int:
	## this player's place among everyone in the session, for spawn spacing
	var ids: Array = [my_id()]
	if active():
		for p in multiplayer.get_peers():
			ids.append(int(p))
	ids.sort()
	return ids.find(my_id())


func name_of(id: int) -> String:
	return str(roster.get(id, {}).get("name", "player %d" % id))


# ---------------------------------------------------------------- host / join

func host() -> String:
	## Open a session on this machine. Returns "" or what went wrong.
	if role != Role.OFF:
		return "already in a session"
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1, 8)
	if err != OK:
		peer = null
		return "could not open UDP %d: %s (port in use?)" % [PORT, error_string(err)]
	multiplayer.multiplayer_peer = peer
	role = Role.HOST
	roster = {1: _me()}
	log_it("hosting on UDP %d; LAN addresses %s" % [PORT, ", ".join(_local_ips())])
	_set_status("Hosting. Looking up the public address ...")
	var herr := _http.request("https://api.ipify.org/?format=text")
	if herr != OK:
		log_it("public ip lookup could not start (%s)" % error_string(herr))
	_start_upnp()
	roster_changed.emit()
	return ""


func join(ip: String) -> String:
	if role != Role.OFF:
		return "already in a session"
	ip = ip.strip_edges()
	if not ip.is_valid_ip_address():
		return "'%s' is not an ip address" % ip
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT, 8)
	if err != OK:
		peer = null
		return "could not start the connection: %s" % error_string(err)
	multiplayer.multiplayer_peer = peer
	role = Role.CLIENT
	roster = {}
	log_it("joining %s:%d" % [ip, PORT])
	_set_status("Connecting to %s ... (a failure shows after about 10 s)" % ip)
	return ""


func leave(why := "") -> void:
	## Out of the session: the host's leaving ends it for everyone.
	if role == Role.OFF:
		return
	var was := role
	if multiplayer.multiplayer_peer == peer:
		multiplayer.multiplayer_peer = null
	if peer != null:
		peer.close()
	peer = null
	role = Role.OFF
	roster = {}
	_pending = {}
	session_dungeon = ""
	remote = {}
	world = null
	_unmap()
	_renew_timer.stop()
	_set_status("")
	log_it("left the session (%s)" % (why if why != "" else "by choice"))
	roster_changed.emit()
	if was != Role.OFF:
		session_ended.emit(why)


func _me() -> Dictionary:
	var gs := get_node("/root/GameState")
	return {"name": str(gs.char_name), "level": int(gs.level),
			"wclass": "bow"}


func _local_ips() -> Array:
	var out := []
	for a in IP.get_local_addresses():
		var s := str(a)
		if s.contains(".") and not s.begins_with("127.") and not s.begins_with("169.254."):
			out.append(s)
	return out


func lan_addresses() -> String:
	return ", ".join(_local_ips())


func _on_peer_connected(id: int) -> void:
	log_it("peer %d connected (%d in the session)" % [id, player_count()])
	_patient(id)
	if is_host():
		_set_status(_host_status())


func _patient(id: int) -> void:
	var p := peer.get_peer(id) if peer != null else null
	if p != null:
		p.set_timeout(32, TIMEOUT_MIN_MS, TIMEOUT_MAX_MS)


func _on_peer_disconnected(id: int) -> void:
	log_it("peer %d left" % id)
	if is_host():
		var who := name_of(id)
		roster.erase(id)
		_drop_remote(id)
		set_roster.rpc(roster)
		roster_changed.emit()
		if world != null and world.hud_node != null:
			world.hud_node.show_area("%s left" % who, Color(0.8, 0.7, 0.5), 3.0)
		_set_status(_host_status())
	else:
		_drop_remote(id)


func _on_connected() -> void:
	log_it("connected to the host as peer %d" % multiplayer.get_unique_id())
	_patient(1)
	_set_status("Connected. Waiting for the host to start a dungeon.")
	var me := _me()
	hello.rpc_id(1, me["name"], me["level"], me["wclass"])


func _on_connection_failed() -> void:
	last_error = "Nothing answered at that address: the host is not running, the port is not open, or the address is wrong."
	log_it("connection failed")
	leave("connection failed")


func _on_server_disconnected() -> void:
	last_error = "The host left the session."
	leave("the host went away")


func _host_status() -> String:
	var addr := public_ip if public_ip != "" else "(looking up the public address)"
	var s := "Hosting on UDP %d. Friends join with %s" % [PORT, addr]
	if mapped:
		s += " (router port opened)"
	elif _upnp_state == "failed":
		s += " (UPnP failed: forward UDP %d to this PC by hand)" % PORT
	elif _upnp_state == "refused":
		s += " (router refused the mapping: forward UDP %d by hand)" % PORT
	s += "\nOn this network: %s" % lan_addresses()
	return s


# ---------------------------------------------------------------- lobby

@rpc("any_peer", "call_remote", "reliable")
func hello(pname: String, level: int, wclass: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	roster[id] = {"name": pname, "level": level, "wclass": wclass}
	log_it("%s (level %d) joined as peer %d" % [pname, level, id])
	set_roster.rpc(roster)
	roster_changed.emit()
	if session_dungeon != "":
		# a dungeon is under way: straight in, the world sends the state
		go.rpc_id(id, session_dungeon)
	if world != null and world.hud_node != null:
		world.hud_node.show_area("%s joined" % pname, Color(0.8, 0.9, 0.6), 3.0)


@rpc("authority", "call_remote", "reliable")
func set_roster(r: Dictionary) -> void:
	roster = {}
	for k in r:
		roster[int(k)] = r[k]
	roster_changed.emit()


func request_start(did: String) -> void:
	## Host: ask every player whether they have the dungeon built, then go.
	if not is_host():
		return
	var peers := multiplayer.get_peers()
	if peers.is_empty():
		go.rpc(did)
		return
	_pending[did] = {}
	for p in peers:
		_pending[did][int(p)] = null
	_set_status("Checking that everyone has %s built ..." % did)
	prepare.rpc(did)


@rpc("authority", "call_remote", "reliable")
func prepare(did: String) -> void:
	var dg := get_node("/root/Dungeons")
	var ok: bool = dg.built(did)
	prepared.rpc_id(1, did, ok)


@rpc("any_peer", "call_remote", "reliable")
func prepared(did: String, ok: bool) -> void:
	if not is_host() or not _pending.has(did):
		return
	var id := multiplayer.get_remote_sender_id()
	_pending[did][id] = ok
	if not ok:
		var who := name_of(id)
		_pending.erase(did)
		_set_status("%s has not built %s; pick another dungeon" % [who, did])
		start_refused.emit(who, did, "not built on their machine")
		return
	for p in _pending[did]:
		if _pending[did][p] == null:
			return
	_pending.erase(did)
	go.rpc(did)


@rpc("authority", "call_local", "reliable")
func go(did: String) -> void:
	session_dungeon = did
	log_it("starting %s" % did)
	launched.emit(did)


# ---------------------------------------------------------------- in the dungeon

func attach_world(w) -> void:
	## The world is built and armed: the host starts streaming to whoever
	## is in; a joiner tells the host it is ready for the pile of state
	world = w
	remote = {}
	log_it("world attached (%s, replay mode %d)" % ["host" if is_host() else "joiner", Replay.mode])
	if is_client():
		var me := _me()
		world_ready.rpc_id(1, me["name"], me["wclass"])
	elif is_host():
		# players already in the lobby: their puppets stand at the entrance
		# until their poses arrive
		for p in multiplayer.get_peers():
			_ensure_remote(int(p))


func detach_world() -> void:
	world = null
	remote = {}


func leave_dungeon() -> void:
	## The world is closing on this side. The host's closing sends everyone
	## back to the lobby; a joiner's own closing is just that joiner's.
	detach_world()
	if is_host():
		session_dungeon = ""
		back_to_lobby.rpc()


@rpc("authority", "call_remote", "reliable")
func back_to_lobby() -> void:
	session_dungeon = ""
	if world != null:
		detach_world()
		get_tree().change_scene_to_file.call_deferred("res://scenes/menu.tscn")


func _ensure_remote(id: int):
	if world == null:
		return null
	if remote.has(id) and is_instance_valid(remote[id]):
		return remote[id]
	var rp = load("res://scripts/remote_player.gd").new()
	rp.peer_id = id
	rp.pname = name_of(id)
	world.add_child(rp)
	rp.global_position = world.spawn
	remote[id] = rp
	return rp


func _drop_remote(id: int) -> void:
	if remote.has(id):
		var rp = remote[id]
		if rp != null and is_instance_valid(rp):
			rp.queue_free()
		remote.erase(id)


func remote_players() -> Array:
	var out := []
	for id in remote:
		var rp = remote[id]
		if rp != null and is_instance_valid(rp):
			out.append(rp)
	return out


@rpc("any_peer", "call_remote", "reliable")
func world_ready(pname: String, wclass: String) -> void:
	if not is_host() or world == null:
		return
	var id := multiplayer.get_remote_sender_id()
	log_it("%s is in the dungeon: sending the state" % pname)
	if roster.has(id):
		roster[id]["wclass"] = wclass
	var rp = _ensure_remote(id)
	if rp != null:
		rp.pname = pname
	# everything that is on the floor and every creature, as one line, then
	# the tick-by-tick stream carries on from there
	var snap: Dictionary = Replay.snapshot_line()
	stream_r.rpc_id(id, var_to_bytes(snap))
	creature_count.rpc_id(id, world.monsters.size())


func send_line(line: Dictionary) -> void:
	## Host: one tick's changes to every player (replay.gd's format)
	if not is_host() or multiplayer.get_peers().is_empty():
		return
	var b := var_to_bytes(line)
	_sent += 1
	if _sent == 1:
		log_it("streaming to %d peer(s); first line %d bytes" % [multiplayer.get_peers().size(), b.size()])
	if b.size() > 1100:
		stream_r.rpc(b)          # past a datagram: reliable, so it fragments
	else:
		stream.rpc(b)


@rpc("authority", "call_remote", "unreliable_ordered", CHANNEL_STREAM)
func stream(b: PackedByteArray) -> void:
	_take_line(b)


@rpc("authority", "call_remote", "reliable", CHANNEL_STREAM)
func stream_r(b: PackedByteArray) -> void:
	_take_line(b)


func _take_line(b: PackedByteArray) -> void:
	var line = bytes_to_var(b)
	_got += 1
	if _got == 1:
		log_it("first stream line: %d bytes, replay mode %d, world %s" % [b.size(), Replay.mode, world != null])
	if line is Dictionary:
		Replay.live_line(line)


@rpc("authority", "call_remote", "reliable")
func creature_count(n: int) -> void:
	if world != null and world.monsters.size() != n:
		log_it("!! the host placed %d creatures, this build %d: the asset builds differ, "
				% [n, world.monsters.size()] + "creatures will be mismatched")
		if world.hud_node != null:
			world.hud_node.show_area("Asset builds differ from the host's: rebuild this dungeon",
					Color(1.0, 0.5, 0.3), 8.0)


func send_pose(p) -> void:
	## Every player: where their Amazon is, for everyone else's puppet
	if not active():
		return
	pose.rpc([p.global_position.x, p.global_position.y, p.global_position.z,
			p.yaw, p.pitch, p.pose_mode(), p.weapon_class])


@rpc("any_peer", "call_remote", "unreliable_ordered", CHANNEL_POSE)
func pose(a: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	var rp = _ensure_remote(id)
	if rp != null:
		rp.apply_pose(a)


func host_pose(a: Array) -> void:
	## Client: the host's own Amazon comes through the stream's "p" record
	var rp = _ensure_remote(1)
	if rp != null:
		rp.apply_pose([a[0], a[1], a[2], a[3], a[4], "nu", "bow"], true)


const CREATURE_METHODS := ["take_hit", "take_damage", "slow", "freeze", "knockback",
		"reveal", "slow_missiles", "burn", "mark_noheal"]


@rpc("any_peer", "call_remote", "reliable")
func creature_call(rid: int, method: String, args: Array) -> void:
	## A player's blow or skill effect on a creature, applied by the host
	if not is_host() or world == null or not (method in CREATURE_METHODS):
		return
	if rid < 0 or rid >= world.monsters.size():
		return
	var mob = world.monsters[rid]
	if mob == null or not is_instance_valid(mob):
		return
	mob.callv(method, args)


func forward_creature(mob, method: String, args: Array) -> void:
	if mob.rid >= 0:
		creature_call.rpc_id(1, mob.rid, method, args)


@rpc("authority", "call_remote", "reliable")
func award_xp(amount: int, ctype: String) -> void:
	## D2 party: every player is paid for the kill
	var gs := get_node("/root/GameState")
	gs.award_xp(amount)
	gs.on_kill(ctype)


func request_pickup(gi) -> void:
	if gi.has_meta("iid"):
		pickup.rpc_id(1, int(gi.get_meta("iid")))


@rpc("any_peer", "call_remote", "reliable")
func pickup(iid: int) -> void:
	if not is_host() or world == null:
		return
	var id := multiplayer.get_remote_sender_id()
	var gi = Replay.item_by_id(iid)
	if gi == null:
		return
	var rp = remote.get(id)
	if rp != null and is_instance_valid(rp) \
			and rp.global_position.distance_to(gi.global_position) > world.PICKUP_RANGE + 2.0:
		return
	give.rpc_id(id, gi.code, gi.gold_amount, gi.instance)
	world.ground_items.erase(gi)
	gi.queue_free()


@rpc("authority", "call_remote", "reliable")
func give(code: String, gold: int, inst: Dictionary) -> void:
	if world != null:
		world.receive_item(code, gold, inst)


@rpc("any_peer", "call_remote", "reliable")
func drop_item(code: String, gold: int, inst: Dictionary, pos: Vector3) -> void:
	## A player's own drop (from the inventory, or a pickup that did not fit)
	if is_host() and world != null:
		world.spawn_drop(code, gold, inst, pos)


@rpc("any_peer", "call_remote", "reliable")
func interact(index: int) -> void:
	if is_host() and world != null:
		world.use_interactable(index)


@rpc("authority", "call_remote", "reliable")
func dungeon_complete() -> void:
	if world != null:
		world.on_dungeon_complete()


@rpc("any_peer", "call_remote", "reliable")
func strike_player(dmg: float, ar: float, mlevel: int, impact_kind: String,
		missile: bool, etype: String) -> void:
	## The host: one of its creatures struck at this player's Amazon; the
	## defence is rolled here, against this character's own gear
	if multiplayer.get_remote_sender_id() != 1 or world == null:
		return
	world.player_struck(dmg, ar, mlevel, impact_kind, missile, etype)


@rpc("any_peer", "call_remote", "unreliable", CHANNEL_FX)
func fx_arrow(cel: String, origin: Vector3, dir: Vector3) -> void:
	## Another player's missile, drawn here as a ghost (its hits are theirs)
	if world != null:
		world.ghost_arrow(cel, origin, dir)


# ---------------------------------------------------------------- UPnP

func _start_upnp() -> void:
	_upnp = UPNP.new()
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_work)


func _upnp_work() -> void:
	# discover() blocks for its timeout: off the main thread, results back
	# through call_deferred
	var r := _upnp.discover(3000, 2, "InternetGatewayDevice")
	if r != UPNP.UPNP_RESULT_SUCCESS:
		call_deferred("_upnp_failed", "UPnP: no gateway answered (result %d)" % r)
		return
	var gw := _upnp.get_gateway()
	if gw == null or not gw.is_valid_gateway():
		call_deferred("_upnp_failed", "UPnP: a device answered but it is not a usable gateway")
		return
	var ext := _upnp.query_external_address()
	var m := _upnp.add_port_mapping(PORT, PORT, APP, "UDP", 0)
	call_deferred("_upnp_done", ext, m)


func _upnp_renew() -> void:
	call_deferred("_upnp_renewed", _upnp.add_port_mapping(PORT, PORT, APP, "UDP", 0))


func _renew_tick() -> void:
	if not mapped or _upnp == null or not is_host():
		return
	if _upnp_thread.is_started():
		_upnp_thread.wait_to_finish()
	_upnp_thread.start(_upnp_renew)


func _upnp_renewed(result: int) -> void:
	_renewals += 1
	if result != UPNP.UPNP_RESULT_SUCCESS:
		log_it("UPnP: renewing the mapping failed (result %d): friends may stop getting in" % result)


func _upnp_done(ext: String, mapping_result: int) -> void:
	upnp_external = ext
	if mapping_result == UPNP.UPNP_RESULT_SUCCESS:
		mapped = true
		_renew_timer.start()
		log_it("UPnP: mapped UDP %d to this machine; router WAN %s" % [PORT, ext])
	else:
		_upnp_state = "refused"
		log_it("UPnP: port mapping refused (result %d)" % mapping_result)
	_cgnat_check()
	if is_host():
		_set_status(_host_status())


func _upnp_failed(why: String) -> void:
	_upnp_state = "failed"
	log_it(why)
	if is_host():
		_set_status(_host_status())


func _unmap() -> void:
	if mapped and _upnp != null:
		_upnp.delete_port_mapping(PORT, "UDP")
		mapped = false


func _on_public_ip(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		log_it("public ip lookup failed (result %d, http %d)" % [result, code])
		return
	public_ip = body.get_string_from_utf8().strip_edges()
	log_it("public ip %s" % public_ip)
	_cgnat_check()
	if is_host():
		_set_status(_host_status())


static func _is_private(ip: String) -> bool:
	var p := ip.split(".")
	if p.size() != 4:
		return false
	var a := p[0].to_int()
	var b := p[1].to_int()
	return a == 10 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31) \
			or (a == 100 and b >= 64 and b <= 127)      # 100.64/10: carrier-grade NAT


func _cgnat_check() -> void:
	if public_ip == "" or upnp_external == "":
		return
	if upnp_external == public_ip:
		log_it("router WAN == public ip: this side can host")
	elif _is_private(upnp_external):
		log_it("!! router WAN %s is private while the public ip is %s: carrier-grade NAT; "
				% [upnp_external, public_ip] + "this side cannot host, swap roles")
		_set_status("This connection is behind carrier-grade NAT: friends cannot reach it. "
				+ "Someone else hosts; join them instead.")
	else:
		log_it("!! router WAN %s differs from public ip %s: a second NAT upstream"
				% [upnp_external, public_ip])
