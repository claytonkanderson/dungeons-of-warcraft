class_name WowCreature
extends CharacterBody3D
## A WoW creature in the D2 combat model: 3D animated GLB visual driven by a
## chase/attack state machine, stats from creatures.json (AzerothCore data
## mapped into D2 terms). Casters loose D2 billboard fire bolts.

enum State { IDLE, CHASE, ATTACK, HURT, DEAD }

const GRAVITY := 22.0
# exported models face -Z at rest (matches the spawn yaw convention)
const MODEL_YAW_OFFSET := 0.0
const TURN_SPEED := 10.0

signal died(mob)

var cname := ""
var stats := {}
var hp := 10.0
var hp_max := 10.0
var speed := 2.0
var defense := 0.0
var mlevel := 1
var xp_value := 0
var attack_period := 2.0
var attack_range := 2.0
var is_boss := false
var is_final_boss := false
var is_caster := false
var passive := false
var state: State = State.IDLE
var target: Node3D
var world = null

var anim: AnimationPlayer
var clips := {}          # role -> clip name (stand/walk/run/attack/wound/death)

var ranged_cel := ""
var ranged_explode := ""
var ranged_vel := 11.0
var ranged_etype := "fire"

var _atk_cd := 0.0
var _retarget_t := 0.0
var _dormant := false
var _los_check_t := 0.0
var _los_lost := 0.0
var _los := true
var _attack_t := 0.0     # time left in the current attack animation
var _hit_t := -1.0       # countdown to the damage frame (-1 = spent)
var _hurt_t := 0.0
var _slow_t := 0.0
var _slow_factor := 0.4
var _burn_dps := 0.0
var _burn_t := 0.0

@onready var gs := get_node("/root/GameState")


func setup(display_name: String, info: Dictionary, anim_player: AnimationPlayer,
		radius: float) -> void:
	cname = display_name
	anim = anim_player
	stats = info.get("stats", {})
	hp = randf_range(float(stats.get("minHP", 10)), float(stats.get("maxHP", 10)))
	hp_max = hp
	defense = float(stats.get("AC", 10))
	mlevel = int(stats.get("Level", 1))
	xp_value = int(stats.get("Exp", 0))
	speed = float(stats.get("Velocity", 3.0))
	attack_period = maxf(1.2, float(stats.get("attack_time", 2.0)))
	attack_range = maxf(2.0, radius + 1.3)
	is_boss = bool(stats.get("boss", false))
	is_final_boss = bool(stats.get("final_boss", false))
	is_caster = str(stats.get("archetype", "melee")) == "caster"
	passive = bool(stats.get("passive", false))
	world = get_parent()
	if is_caster:
		var db := get_node("/root/SpriteDB")
		if db.load_sheet("missiles/shamanfireball") != null:
			ranged_cel = "shamanfireball"
			ranged_explode = "shamanfireballexplodefinal"
	_pick_clips(info.get("anims", []))
	_play("stand")
	if anim != null and anim.current_animation != "":
		anim.seek(randf() * anim.current_animation_length)


func _pick_clips(names: Array) -> void:
	var have := {}
	for n in names:
		have[str(n)] = true
	var pick := func(cands: Array) -> String:
		for c in cands:
			if have.has(c):
				return c
		return ""
	clips = {
		"stand": pick.call(["Stand"]),
		"walk": pick.call(["Walk", "Run"]),
		"run": pick.call(["Run", "Walk"]),
		"attack": pick.call(["Attack1H", "Attack2H", "Attack2HL",
				"AttackUnarmed"]),
		"cast": pick.call(["SpellCast", "ReadySpellDirected", "Attack1H",
				"AttackUnarmed"]),
		"wound": pick.call(["CombatWound", "CombatCritical"]),
		"death": pick.call(["Death", "Dead"]),
	}
	if anim == null:
		return
	for role in clips:
		var clip: String = clips[role]
		if clip == "" or not anim.has_animation(clip):
			continue
		var a := anim.get_animation(clip)
		a.loop_mode = Animation.LOOP_LINEAR \
				if role in ["stand", "walk", "run"] else Animation.LOOP_NONE


func _play(role: String, blend := 0.2) -> void:
	if anim == null:
		return
	var clip: String = clips.get(role, "")
	if clip == "" or not anim.has_animation(clip):
		return
	if anim.current_animation == clip and role in ["stand", "walk", "run"]:
		return
	anim.play(clip, blend)


func slow(duration: float, factor := 0.4) -> void:
	_slow_t = maxf(_slow_t, duration)
	_slow_factor = factor
	if anim != null:
		anim.speed_scale = 0.45   # chilled: the whole body drags


func burn(dps: float, duration: float) -> void:
	_burn_dps = maxf(_burn_dps, dps)
	_burn_t = maxf(_burn_t, duration)


func _move_speed() -> float:
	return speed * (_slow_factor if _slow_t > 0.0 else 1.0)


func take_damage(dmg: float) -> void:
	if state == State.DEAD:
		return
	hp -= dmg
	if hp <= 0.0:
		state = State.DEAD
		if anim != null:
			anim.speed_scale = 1.0
		_play("death", 0.1)
		set_collision_layer_value(1, false)
		died.emit(self)
		gs.award_xp(xp_value)
		return
	if passive:
		# a kicked critter finally fights back
		passive = false
	# bosses shrug off most hits instead of being stun-locked
	if is_boss and randf() > 0.25:
		return
	if clips.get("wound", "") != "" and state != State.ATTACK:
		state = State.HURT
		_hurt_t = 0.45
		_play("wound", 0.1)


func _start_attack(casting: bool) -> void:
	state = State.ATTACK
	var role := "cast" if casting else "attack"
	_play(role, 0.1)
	var clip: String = clips.get(role, "")
	var length := 1.0
	if anim != null and clip != "" and anim.has_animation(clip):
		length = anim.get_animation(clip).length
	_attack_t = length
	_hit_t = length * 0.45
	_atk_cd = attack_period
	velocity.x = 0
	velocity.z = 0


func _strike() -> void:
	if target == null or state == State.DEAD:
		return
	var to_t := target.global_position - global_position
	to_t.y = 0.0
	var d := to_t.length()
	if is_caster and d > attack_range + 0.5:
		if world != null and world.has_method("spawn_enemy_missile"):
			var dir := (target.global_position + Vector3(0, 1.0, 0)
					- global_position - Vector3(0, 1.4, 0)).normalized()
			world.spawn_enemy_missile(global_position + Vector3(0, 1.4, 0),
					dir, self)
		return
	if d > attack_range + 0.8:
		return
	var dmg := randf_range(float(stats.get("A1MinD", 1)),
			float(stats.get("A1MaxD", 3)))
	if target is Ally:
		target.take_damage(dmg * 2.0)
		return
	var ar := float(stats.get("A1TH", 30)) + mlevel * 5.0
	var chance := GameState.chance_to_hit(ar, 25.0 + gs.player_defense(),
			mlevel, gs.level)
	if randf() < chance:
		if randf() < gs.dodge_chance():
			return
		get_node("/root/Sfx").event("player_gethit", target.global_position, 0.5)
		if gs.take_damage(dmg) and target.has_method("die"):
			target.die()


func _update_los(dt: float) -> void:
	## Walls (StaticBody3D) block sight; other creatures don't.
	_los_check_t -= dt
	if _los_check_t > 0.0 or target == null:
		return
	_los_check_t = 0.5
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 1.4, 0),
		target.global_position + Vector3(0, 1.2, 0))
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	_los = hit.is_empty() or not (hit["collider"] is StaticBody3D)


func _face(dir: Vector3, dt: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	rotation.y = lerp_angle(rotation.y,
			atan2(-dir.x, -dir.z) + MODEL_YAW_OFFSET, TURN_SPEED * dt)


func _physics_process(dt: float) -> void:
	if state == State.DEAD:
		return
	if _slow_t > 0.0:
		_slow_t -= dt
		if _slow_t <= 0.0:
			_slow_factor = 0.4
			if anim != null:
				anim.speed_scale = 1.0
	if _burn_t > 0.0:
		_burn_t -= dt
		take_damage(_burn_dps * dt)
		if _burn_t <= 0.0:
			_burn_dps = 0.0
	_retarget_t -= dt
	if _retarget_t <= 0.0 and world != null and world.has_method("combat_targets"):
		_retarget_t = 1.2
		var bd := 1e9
		for t in world.combat_targets():
			var d: float = global_position.distance_to(t.global_position)
			if d < bd:
				bd = d
				target = t
		# LOD: idle creatures far from everyone stop animating and skip
		# physics — 213 live skeletons were costing the whole frame budget
		var far: bool = state == State.IDLE and bd > 45.0
		if far != _dormant:
			_dormant = far
			if anim != null:
				anim.process_mode = Node.PROCESS_MODE_DISABLED if far \
						else Node.PROCESS_MODE_INHERIT
	if _dormant:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * dt
	else:
		velocity.y = 0.0

	if target == null or passive:
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return
	var to_t := target.global_position - global_position
	to_t.y = 0.0
	var dist := to_t.length()
	_update_los(dt)

	match state:
		State.IDLE:
			if dist < 22.0 and _los:
				state = State.CHASE
				_los_lost = 0.0
				_play("run")
		State.CHASE:
			_atk_cd -= dt
			if _los:
				_los_lost = 0.0
			else:
				_los_lost += dt
				if _los_lost > 8.0:
					state = State.IDLE
					velocity.x = 0
					velocity.z = 0
					_play("stand")
					move_and_slide()
					return
			if dist < attack_range and _atk_cd <= 0.0:
				_face(to_t.normalized(), 1.0)
				_start_attack(false)
			elif is_caster and _atk_cd <= 0.0 and dist > 4.0 and dist < 20.0 \
					and _los:
				_face(to_t.normalized(), 1.0)
				_start_attack(true)
			elif is_caster and dist < 6.0:
				# casters back away from the closing amazon
				var away := -to_t.normalized()
				velocity.x = away.x * _move_speed() * 0.7
				velocity.z = away.z * _move_speed() * 0.7
				_face(to_t.normalized(), dt)
				_play("walk")
			elif dist >= attack_range * 0.8:
				var dir := to_t.normalized()
				velocity.x = dir.x * _move_speed()
				velocity.z = dir.z * _move_speed()
				_face(dir, dt)
				_play("run")
			else:
				velocity.x = 0
				velocity.z = 0
				_face(to_t.normalized(), dt)
				_play("stand")
		State.ATTACK:
			velocity.x = 0
			velocity.z = 0
			_face(to_t.normalized(), dt)
			var before := _hit_t
			_attack_t -= dt
			_hit_t -= dt
			if before > 0.0 and _hit_t <= 0.0:
				_strike()
			if _attack_t <= 0.0:
				state = State.CHASE
				_play("run" if dist > attack_range else "stand")
		State.HURT:
			velocity.x = 0
			velocity.z = 0
			_hurt_t -= dt
			if _hurt_t <= 0.0:
				state = State.CHASE
				_play("run")
	move_and_slide()
