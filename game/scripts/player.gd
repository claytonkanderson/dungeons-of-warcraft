class_name Player
extends CharacterBody3D
## L4D-feel first-person controller. LMB = D2 action 1, RMB = D2 action 2.
## Skills are assigned into the two slots; default both to plain Attack.

signal fire_action(slot: int, origin: Vector3, dir: Vector3)

const EYE := 1.7
const WALK := 4.2
const RUN := 8.4                 # D2 run is ~2x walk
const ACCEL := 60.0              # ground acceleration: near-instant strafe
const FRICTION := 40.0
const GRAVITY := 22.0
const SENS := 0.0022
const PITCH_LIMIT := PI / 4.0   # +/-45 deg: sprites read badly from steep angles
const STAMINA_MAX := 100.0
const STAMINA_DRAIN := 8.0       # per second while running
const STAMINA_REGEN := 12.0
const JUMP_VEL := 7.5            # ~1.3 m hop against the 22 m/s^2 gravity

# Breadcrumbs behind the player, for the Unstuck command. Only spots they
# demonstrably walked away from are kept, so wedging into scenery stops the
# trail instead of overwriting it with the spot they are wedged in.
const SAFE_STEP := 0.75          # metres of travel between breadcrumbs
const SAFE_TRAIL := 8            # roughly the last few seconds of walking

var yaw := 0.0
var pitch := 0.0
var stamina := STAMINA_MAX
var action_skill := ["Attack", "Attack"]   # LMB, RMB
var attack_time := 0.0          # seconds remaining in the current attack
var attack_release := 0.0       # time from attack start until the arrow leaves
var _pending_slot := -1
var _attack_len := 0.55
var _ias := 1.0                  # attack speed factor of the swing in flight
var _block_t := 0.0              # shield arm busy after a block (no attacks)
var _chill_t := 0.0              # hit by cold: half speed until it wears off
var _stun_t := 0.0               # hit recovery: a solid blow stops the swing
# the skills that are cast rather than swung: "+N% Faster Cast Rate" is their
# speed, attack speed everyone else's
const CAST_LIKE := ["Inner Sight", "Slow Missiles", "Decoy", "Dopplezon", "Valkyrie"]


func on_hurt(dmg: float) -> void:
	## D2 hit recovery: a blow of a twelfth of max life or more staggers the
	## character, who cannot start an attack and crawls until it passes
	var gs := get_node("/root/GameState")
	if dmg >= gs.hp_max / 12.0:
		_stun_t = maxf(_stun_t, gs.hit_recovery())


func chill(duration: float) -> void:
	## Cold hits chill the Amazon; "Half Freeze Duration" halves it and
	## "Cannot Be Frozen" ignores it
	var gs := get_node("/root/GameState")
	if int(gs.mods.get("nofreeze", 0)) > 0:
		return
	if int(gs.mods.get("half-freeze", 0)) > 0:
		duration *= 0.5
	_chill_t = maxf(_chill_t, duration)
const KEY_TURN := 2.4            # rad/s with the arrow keys
const KEY_PITCH := 1.6
var _safe: Array[Vector3] = []
# footstep surface, set per-dungeon from placements.json (stone/wood/dirt)
var surface := "stone"
var _step_dist := 0.0            # ground covered since the last footstep
var _was_floor := true
const STRIDE_WALK := 2.0         # metres between footfalls at a walk
const STRIDE_RUN := 2.6          # longer stride running — cadence still rises
const STEP_TRIM := -12.0         # D2 footsteps ship at full volume; soften
const LAND_TRIM := -7.0          # the leap-land thud, less so
var hud: HUD

@onready var cam: Camera3D = $Camera3D


func _ready() -> void:
	# explicit: script-created nodes have silently missed input callbacks before
	set_process_input(true)
	add_to_group("player")
	floor_max_angle = deg_to_rad(55)
	# Warp-based look instead of MOUSE_MODE_CAPTURED: raw-input motion events
	# proved undeliverable on this machine (focus=true, clicks and keys fine,
	# zero motion). Hide the cursor, read its offset from centre every frame,
	# warp it back. Plain WM_MOUSEMOVE path - works everywhere.
	if not Cli.offscreen():
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_center_mouse()


func _center_mouse() -> void:
	# offscreen captures must never touch the real cursor — the whole point is
	# that the machine stays usable while they run
	if Cli.offscreen():
		return
	var vp := get_viewport()
	if vp == null:
		return
	var c := vp.get_visible_rect().size * 0.5
	# the warp itself lands as a motion event: pre-cancel it so re-centring
	# never turns the camera (this replaced the old 2-frame settle window,
	# which threw real motion away and made fast turns feel chunky)
	_warp_comp = vp.get_mouse_position() - c
	# the viewport's own warp, not Input.warp_mouse: everything here is in
	# canvas pixels, and in fullscreen the canvas is stretched, so a warp
	# given in window pixels landed off-centre and the compensation above
	# no longer cancelled it — every re-centre turned the camera
	vp.warp_mouse(c)


var look_enabled := true
var _accum := Vector2.ZERO       # motion-event relative sum since last frame
var _warp_comp := Vector2.ZERO   # pending warp jump to cancel
var _focused := true             # alt-tabbed: hands off the mouse entirely


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_focused = false
		_accum = Vector2.ZERO
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_focused = true
		_refocus_swallow = true   # the click that refocused us is not an attack
		if look_enabled and not ui_locked:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
			_center_mouse()


var _refocus_swallow := false


func _process(_dt: float) -> void:
	if look_enabled and not ui_locked and _focused:
		if _accum != Vector2.ZERO:
			# motion arrives in canvas pixels, which the stretch shrinks in
			# fullscreen; scale back so a hand movement turns the same amount
			var k: float = get_viewport().get_screen_transform().get_scale().x
			yaw -= _accum.x * SENS * k
			pitch = clampf(pitch - _accum.y * SENS * k, -PITCH_LIMIT, PITCH_LIMIT)
			_accum = Vector2.ZERO
		# rotation applied per rendered frame (not per physics tick) so the
		# camera stays smooth when the frame rate drifts off 60
		# arrow keys as a mouse fallback: left/right turn, up/down pitch
		var turn := float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT))
		var tilt := float(Input.is_key_pressed(KEY_UP)) - float(Input.is_key_pressed(KEY_DOWN))
		if turn != 0.0 or tilt != 0.0:
			yaw -= turn * KEY_TURN * _dt
			pitch = clampf(pitch + tilt * KEY_PITCH * _dt, -PITCH_LIMIT, PITCH_LIMIT)
		rotation.y = yaw
		if cam != null:
			cam.rotation = Vector3(pitch, 0, 0)
		var vp := get_viewport()
		var c := vp.get_visible_rect().size * 0.5
		var pos := vp.get_mouse_position()
		if absf(pos.x - c.x) > c.x * 0.5 or absf(pos.y - c.y) > c.y * 0.5:
			_center_mouse()
	# attack timing is set per weapon by refresh_attack_style() on equip;
	# recomputing it from the bow sheet here overwrote that every frame


var melee := false
var weapon_class := "bow"


func refresh_attack_style() -> void:
	## Attack timing + style follow the equipped weapon's class.
	var gs := get_node("/root/GameState")
	var db := get_node("/root/SpriteDB")
	var w: Dictionary = gs.equipped.get("weap", {})
	var wc: String = gs.weapon_class(str(w.get("code", "")))
	melee = not (wc in ["bow", "xbw"])
	weapon_class = wc
	var sheet = db.load_sheet("amazon/am_a1_" + wc)
	if sheet == null:
		sheet = db.load_sheet("amazon/am_a1_bow")
	if sheet != null and sheet.fps > 0.0:
		_attack_len = sheet.frames / sheet.fps
		var trig: int = sheet.triggers[0] if sheet.triggers.size() > 0 \
				else int(sheet.frames * 0.6)
		attack_release = trig / sheet.fps


var ui_locked := false   # a UI panel owns the mouse: never attack or re-capture


func _input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		if look_enabled and not ui_locked and _focused:
			_accum += e.relative + _warp_comp
		_warp_comp = Vector2.ZERO
		return
	# K and L fire the left and right actions from the keyboard, so the mouse
	# is optional together with the arrow-key look
	if e is InputEventKey and e.pressed and not e.echo 			and e.keycode in [KEY_K, KEY_L]:
		if ui_locked or not look_enabled:
			return
		_start_attack(0 if e.keycode == KEY_K else 1)
		return
	if e is InputEventMouseButton and e.pressed:
		if _refocus_swallow:
			_refocus_swallow = false
			return
		if ui_locked:
			return
		if not look_enabled:
			# click to resume mouse look after Esc
			look_enabled = true
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
			_center_mouse()
			return
		if e.button_index == MOUSE_BUTTON_LEFT:
			_start_attack(0)
		elif e.button_index == MOUSE_BUTTON_RIGHT:
			_start_attack(1)
	# Esc is handled by the world: panels close first, then the menu opens


func die() -> void:
	# death -> respawn at the instance entrance; no other penalty
	get_node("/root/Sfx").event("player_death", global_position)
	var gs := get_node("/root/GameState")
	gs.respawn()
	var t: Node = get_parent()
	if t != null and t.has_method("respawn_position"):
		global_position = t.respawn_position()
		velocity = Vector3.ZERO
	if hud != null:
		hud.show_area("You have died...", Color(0.85, 0.12, 0.12), 4.5)


func on_block() -> void:
	## A blow the shield stopped: the arm is busy for the recovery time
	_block_t = get_node("/root/GameState").block_recovery()
	if hud != null:
		hud.block_flash()


func _start_attack(slot: int) -> void:
	if attack_time > 0.0 or _block_t > 0.0 or _stun_t > 0.0:
		return
	# "+N% Increased Attack Speed" shortens the whole swing, release included;
	# a cast is timed by "+N% Faster Cast Rate" instead
	var gs := get_node("/root/GameState")
	_ias = gs.cast_speed_factor() if str(action_skill[slot]) in CAST_LIKE \
			else gs.attack_speed_factor()
	attack_time = _attack_len / _ias
	_pending_slot = slot


func _fire(slot: int) -> void:
	if hud != null:
		hud.kick()
	var origin := cam.global_position
	var dir := -cam.global_transform.basis.z
	fire_action.emit(slot, origin, dir)


func _physics_process(dt: float) -> void:
	if _block_t > 0.0:
		_block_t -= dt
	if _stun_t > 0.0:
		_stun_t -= dt
	if attack_time > 0.0:
		var before := attack_time
		attack_time -= dt
		# release the arrow when the animation crosses its trigger frame
		var rel := (_attack_len - attack_release) / maxf(0.01, _ias)
		if before > rel and attack_time <= rel and _pending_slot >= 0:
			_fire(_pending_slot)
			_pending_slot = -1
	cam.rotation = Vector3(pitch, 0, 0)
	rotation = Vector3(0, yaw, 0)

	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): input.y -= 1.0
	if Input.is_key_pressed(KEY_S): input.y += 1.0
	if Input.is_key_pressed(KEY_A): input.x -= 1.0
	if Input.is_key_pressed(KEY_D): input.x += 1.0

	var gs := get_node("/root/GameState")
	var want_run := Input.is_key_pressed(KEY_SHIFT) and stamina > 0.0
	# "+N% Faster Run/Walk", "+N Maximum Stamina", "Heal Stamina +N%",
	# "Slower Stamina Drain N%"
	var speed: float = (RUN if want_run else WALK) * gs.run_speed_factor()
	if _chill_t > 0.0:
		_chill_t -= dt
		speed *= 0.5
	if _stun_t > 0.0:
		speed *= 0.35
	if want_run and input != Vector2.ZERO:
		var drain := 1.0 - clampf(float(gs.mods.get("stamdrain", 0)) / 100.0, 0.0, 0.9)
		stamina = max(0.0, stamina - STAMINA_DRAIN * drain * dt)
	else:
		var regen := 1.0 + float(gs.mods.get("regen-stam", 0)) / 100.0
		stamina = min(gs.stamina_max(), stamina + STAMINA_REGEN * regen * dt)

	var wish := Vector3.ZERO
	if input != Vector2.ZERO:
		input = input.normalized()
		wish = Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y)

	var hv := Vector3(velocity.x, 0, velocity.z)
	if wish != Vector3.ZERO:
		hv = hv.move_toward(wish * speed, ACCEL * dt)
	else:
		hv = hv.move_toward(Vector3.ZERO, FRICTION * dt)
	velocity.x = hv.x
	velocity.z = hv.z

	var sfx := get_node("/root/Sfx")
	if is_on_floor():
		velocity.y = 0.0
		if Input.is_key_pressed(KEY_SPACE) and not ui_locked:
			velocity.y = JUMP_VEL
			sfx.event_ui("step_%s_%s" % [surface, "run" if want_run else "walk"],
					STEP_TRIM)
	else:
		velocity.y -= GRAVITY * dt
	var grounded := is_on_floor()
	move_and_slide()
	if grounded:
		Stepper.climb(self, hv, dt)     # stairs: lift over risers the slide caught on

	# footsteps and landing. Distance-driven cadence, so it speeds up with the
	# player rather than ticking on a fixed timer; the surface picks the D2
	# footstep set (see EVENTS in export_sounds.py). event_ui keeps them
	# non-positional — they are the player's own feet, always at the listener.
	var on_floor := is_on_floor()
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	if on_floor and ground_speed > 0.6:
		_step_dist += ground_speed * dt
		var stride := STRIDE_RUN if want_run else STRIDE_WALK
		if _step_dist >= stride:
			_step_dist = 0.0
			sfx.event_ui("step_%s_%s" % [surface, "run" if want_run else "walk"],
					STEP_TRIM)
	else:
		# arm the next footfall so it lands a beat after moving off, not instantly
		_step_dist = STRIDE_WALK * 0.6
	if on_floor and not _was_floor:
		sfx.event_ui("jump_land", LAND_TRIM)
	_was_floor = on_floor

	if on_floor and (_safe.is_empty()
			or global_position.distance_to(_safe[-1]) > SAFE_STEP):
		_safe.append(global_position)
		if _safe.size() > SAFE_TRAIL:
			_safe.pop_front()


func unstuck() -> bool:
	## Step back to the oldest breadcrumb — where the player was before they
	## walked into whatever is holding them. False when there is no trail yet.
	if _safe.is_empty():
		return false
	global_position = _safe[0] + Vector3.UP * 0.5
	velocity = Vector3.ZERO
	_safe.clear()
	return true
