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

var yaw := 0.0
var pitch := 0.0
var stamina := STAMINA_MAX
var action_skill := ["Attack", "Attack"]   # LMB, RMB
var attack_time := 0.0          # seconds remaining in the current attack
var attack_release := 0.0       # time from attack start until the arrow leaves
var _pending_slot := -1
var _attack_len := 0.55
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
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_center_mouse()


func _center_mouse() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var c := vp.get_visible_rect().size * 0.5
	# the warp itself lands as a motion event: pre-cancel it so re-centring
	# never turns the camera (this replaced the old 2-frame settle window,
	# which threw real motion away and made fast turns feel chunky)
	_warp_comp = vp.get_mouse_position() - c
	Input.warp_mouse(c)


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
			yaw -= _accum.x * SENS
			pitch = clampf(pitch - _accum.y * SENS, -PITCH_LIMIT, PITCH_LIMIT)
			_accum = Vector2.ZERO
		# rotation applied per rendered frame (not per physics tick) so the
		# camera stays smooth when the frame rate drifts off 60
		rotation.y = yaw
		if cam != null:
			cam.rotation = Vector3(pitch, 0, 0)
		var vp := get_viewport()
		var c := vp.get_visible_rect().size * 0.5
		var pos := vp.get_mouse_position()
		if absf(pos.x - c.x) > c.x * 0.5 or absf(pos.y - c.y) > c.y * 0.5:
			_center_mouse()
	# attack timing from the real A1/BOW animation: length and release frame
	var sheet = get_node("/root/SpriteDB").load_sheet("amazon/am_a1_bow")
	if sheet != null and sheet.fps > 0.0:
		_attack_len = sheet.frames / sheet.fps
		var trig: int = sheet.triggers[0] if sheet.triggers.size() > 0 else int(sheet.frames * 0.6)
		attack_release = trig / sheet.fps


var melee := false
var weapon_class := "bow"


func refresh_attack_style() -> void:
	## Attack timing + style follow the equipped weapon's class.
	var gs := get_node("/root/GameState")
	var gen := get_node("/root/ItemGen")
	var db := get_node("/root/SpriteDB")
	var w: Dictionary = gs.equipped.get("weap", {})
	var wc := "bow"
	melee = false
	if not w.is_empty():
		var chain: Dictionary = gen.type_chain(str(
			get_node("/root/ItemDB").item(str(w.get("code", ""))).get("type", "")))
		if chain.has("bow"):
			wc = "bow"
		elif chain.has("xbow"):
			wc = "xbw"
		elif chain.has("jave") or chain.has("spea"):
			wc = "1ht"
			melee = true
		elif chain.has("staf") or chain.has("pole"):
			wc = "stf"
			melee = true
		else:
			wc = "1hs"
			melee = true
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
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		if not ui_locked:
			look_enabled = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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


func _start_attack(slot: int) -> void:
	if attack_time > 0.0:
		return
	attack_time = _attack_len
	_pending_slot = slot


func _fire(slot: int) -> void:
	if hud != null:
		hud.kick()
	var origin := cam.global_position
	var dir := -cam.global_transform.basis.z
	fire_action.emit(slot, origin, dir)


func _physics_process(dt: float) -> void:
	if attack_time > 0.0:
		var before := attack_time
		attack_time -= dt
		# release the arrow when the animation crosses its trigger frame
		var rel := _attack_len - attack_release
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

	var want_run := Input.is_key_pressed(KEY_SHIFT) and stamina > 0.0
	var speed := RUN if want_run else WALK
	if want_run and input != Vector2.ZERO:
		stamina = max(0.0, stamina - STAMINA_DRAIN * dt)
	else:
		stamina = min(STAMINA_MAX, stamina + STAMINA_REGEN * dt)

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

	if is_on_floor():
		velocity.y = 0.0
		if Input.is_key_pressed(KEY_SPACE) and not ui_locked:
			velocity.y = JUMP_VEL
	else:
		velocity.y -= GRAVITY * dt
	move_and_slide()
