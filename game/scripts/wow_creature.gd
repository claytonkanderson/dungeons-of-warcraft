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
var voice := ""              # WowSfx voice group ("goblin", "murloc", ...)
var impact_kind := "sword"   # WowSfx foley when a swing lands on the player
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
var res := {}                # elemental resistances in percent; 100 = immune
var noheal := false          # "Prevents Monster Heal" has landed on it
var _since_hit := 99.0       # seconds since the last damage, for regeneration

# D2 monsters slowly regenerate; here a creature left alone for a while heals
# a share of its life each second, which is what "Prevents Monster Heal" stops
const REGEN_DELAY := 5.0
const REGEN_FRAC := 0.03

@onready var gs := get_node("/root/GameState")


func setup(display_name: String, info: Dictionary, anim_player: AnimationPlayer,
		radius: float) -> void:
	cname = display_name
	anim = anim_player
	stats = info.get("stats", {})
	res = stats.get("res", {}) if stats.get("res", {}) is Dictionary else {}
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


var _freeze_t := 0.0             # frozen solid: no movement, no attacks
var _reveal_t := 0.0             # Inner Sight: lit up, seen through anything
var _slowmis_t := 0.0            # Slow Missiles: its missiles crawl
var _reveal_light: OmniLight3D


func freeze(duration: float) -> void:
	## "Freezes target": stopped dead for the duration. Bosses cannot be
	## frozen in D2, only chilled — they get a hard slow instead.
	if is_boss:
		slow(duration, 0.25)
		return
	_freeze_t = maxf(_freeze_t, duration)
	if anim != null:
		anim.speed_scale = 0.0


func knockback(dir: Vector3, distance := 0.8) -> void:
	## shoved along dir, stopping at walls
	var flat := Vector3(dir.x, 0.0, dir.z).normalized()
	move_and_collide(flat * distance)


func reveal(duration: float) -> void:
	## Inner Sight: the creature carries a light and is visible through walls
	_reveal_t = maxf(_reveal_t, duration)
	if _reveal_light == null:
		_reveal_light = OmniLight3D.new()
		_reveal_light.light_color = Color(1.0, 0.45, 0.35)
		_reveal_light.light_energy = 2.5
		_reveal_light.omni_range = 6.0
		_reveal_light.position = Vector3(0, 1.5, 0)
		add_child(_reveal_light)
	_reveal_light.visible = true


func slow_missiles(duration: float) -> void:
	_slowmis_t = maxf(_slowmis_t, duration)


func missile_speed_factor() -> float:
	return 0.67 if _slowmis_t > 0.0 else 1.0


func burn(dps: float, duration: float, etype := "pois") -> void:
	## damage over time; the resistance is taken off once, up front
	dps *= 1.0 - effective_resist(etype) / 100.0
	if dps <= 0.0:
		return
	_burn_dps = maxf(_burn_dps, dps)
	_burn_t = maxf(_burn_t, duration)


func effective_resist(etype: String) -> float:
	## This creature's resistance to one element after the character's
	## "-N% to Enemy <element> Resistance"; D2 lets an immunity give way to
	## only a fifth of the pierce.
	var key: String = {"fire": "fire", "cold": "cold", "ltng": "ltng",
			"lightning": "ltng", "pois": "pois", "poison": "pois",
			"mag": "mag", "magic": "mag"}.get(etype, "")
	if key == "":
		return 0.0
	var r := float(res.get(key, 0))
	var pierce: float = gs.enemy_res_pierce(key)
	r -= pierce / 5.0 if r >= 100.0 else pierce
	return clampf(r, -100.0, 100.0)


func take_hit(parts: Dictionary) -> void:
	## One blow made of several damage types ("phys", "fire", ...), each
	## resisted on its own, landed as one.
	var total := 0.0
	for et in parts:
		var d := float(parts[et])
		if str(et) != "phys":
			d *= 1.0 - effective_resist(str(et)) / 100.0
		total += maxf(0.0, d)
	take_damage(total)


func _move_speed() -> float:
	if _freeze_t > 0.0:
		return 0.0
	return speed * (_slow_factor if _slow_t > 0.0 else 1.0)


# Corpses are cleared after a while so a busy corridor does not fill with
# bodies (and their physics) for the rest of the run.
const CORPSE_SECONDS := 30.0
var _corpse_t := -1.0


func take_damage(dmg: float, etype := "phys") -> void:
	if state == State.DEAD:
		return
	if etype != "phys":
		dmg *= 1.0 - effective_resist(etype) / 100.0
	if dmg <= 0.0:
		return
	_since_hit = 0.0
	hp -= dmg
	if hp <= 0.0:
		state = State.DEAD
		_corpse_t = CORPSE_SECONDS
		if anim != null:
			anim.speed_scale = 1.0
		_play("death", 0.1)
		get_node("/root/WowSfx").voice(voice, "death", global_position)
		set_collision_layer_value(1, false)
		died.emit(self)
		gs.award_xp(xp_value)
		return
	if passive:
		# a kicked critter finally fights back
		passive = false
	get_node("/root/WowSfx").voice(voice, "wound", global_position, 0.4)
	# bosses shrug off most hits instead of being stun-locked
	if is_boss and randf() > 0.25:
		return
	if clips.get("wound", "") != "" and state != State.ATTACK:
		state = State.HURT
		_hurt_t = 0.45
		_play("wound", 0.1)


func _start_attack(casting: bool) -> void:
	if _freeze_t > 0.0:
		return
	state = State.ATTACK
	var role := "cast" if casting else "attack"
	get_node("/root/WowSfx").voice(voice, "attack", global_position, 0.35)
	# every swing makes a sound even when a creature has no voice set —
	# three of four dungeons used to attack in total silence
	get_node("/root/Sfx").event("melee_swing", global_position, 0.8)
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
	# attack rating straight off D2's per-level curve (MonLvl TH); defense
	# is the character's own, no hidden base
	var ar := float(stats.get("A1TH", 30))
	var chance := GameState.chance_to_hit(ar,
			gs.player_defense() + float(gs.mods.get("ac-hth", 0)), mlevel, gs.level)
	if randf() < chance:
		if randf() < gs.dodge_chance():
			return
		if randf() < gs.block_chance():
			# the shield takes it: a clang, the arm busy for a moment, no damage
			get_node("/root/Sfx").event("blade_impact", target.global_position)
			if target.has_method("on_block"):
				target.on_block()
			return
		get_node("/root/WowSfx").impact(impact_kind, target.global_position, 0.9)
		get_node("/root/Sfx").event("player_gethit", target.global_position, 0.5)
		if gs.take_damage(dmg) and target.has_method("die"):
			target.die()
		elif target.has_method("on_hurt"):
			target.on_hurt(dmg)
		# "Attacker Takes Damage of N" / "Attacker Takes Lightning Damage"
		var thorns := float(gs.mods.get("thorns", 0)) + float(gs.mods.get("light-thorns", 0))
		if thorns > 0.0:
			take_damage(thorns)


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
		if _corpse_t > 0.0:
			_corpse_t -= dt
			if _corpse_t <= 0.0:
				if world != null and "monsters" in world:
					world.monsters.erase(self)
				queue_free()
		return
	_since_hit += dt
	if hp < hp_max and not noheal and _since_hit > REGEN_DELAY:
		hp = minf(hp_max, hp + hp_max * REGEN_FRAC * dt)
	if _reveal_t > 0.0:
		_reveal_t -= dt
		if _reveal_t <= 0.0 and _reveal_light != null:
			_reveal_light.visible = false
	if _slowmis_t > 0.0:
		_slowmis_t -= dt
	if _freeze_t > 0.0:
		_freeze_t -= dt
		if _freeze_t <= 0.0 and anim != null:
			anim.speed_scale = 0.45 if _slow_t > 0.0 else 1.0
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
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
				get_node("/root/WowSfx").voice(voice, "aggro", global_position)
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
	var wish := Vector3(velocity.x, 0.0, velocity.z)
	var grounded := is_on_floor()
	move_and_slide()
	if grounded:
		Stepper.climb(self, wish, dt)   # creatures climb stairs like the player
