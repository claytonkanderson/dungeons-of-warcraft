class_name Ally
extends CharacterBody3D
## Friendly summon: Valkyrie (chases and strikes monsters) or Decoy (stands).
##
## The Valkyrie wears the Amazon's own spear sheets in a pale gold: the
## Diablo II install this is built from carries only 65-byte stubs for
## her token's art (data/global/monsters/VK), which came out as a 2x2
## dot nobody could see. The idle, walk and attack poses follow what she
## is doing; the Decoy is the Amazon at rest with a bow.

const GRAVITY := 22.0

var kind := "valkyrie"        # or "decoy"
var hp := 100.0
var damage := Vector2(8, 16)
var speed := 3.2
var lifetime := 45.0
var world = null
var _mode := ""
var _attacking := false

@onready var anim: BillboardAnim = $BillboardAnim

const VALKYRIE_TINT := Color(1.0, 0.92, 0.7)


static func spawn(world_node, at: Vector3, skind: String, sn: Dictionary) -> Ally:
	## sn: the skill's numbers (GameState.skill_numbers): life, damage, time
	var a := Ally.new()
	a.kind = skind
	a.world = world_node
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.6
	cs.shape = cap
	cs.position.y = 0.8
	a.add_child(cs)
	if world_node.has_method("_debug_capsule"):
		a.add_child(world_node._debug_capsule(cap, cs.position, Color(1.0, 0.9, 0.3, 0.25)))
	var an := BillboardAnim.new()
	an.name = "BillboardAnim"
	a.add_child(an)
	world_node.add_child(a)
	a.global_position = at + Vector3(0, 0.2, 0)
	a.hp = float(sn.get("ally_life", a.hp))
	a.lifetime = float(sn.get("ally_time", a.lifetime))
	if skind == "valkyrie":
		a.damage = sn.get("ally_dmg", a.damage)
		a.anim.modulate = VALKYRIE_TINT
		a._pose("nu")
	else:
		a.anim.play("amazon/am_nu_bow", true)
	return a


func _pose(mode: String) -> void:
	## nu / wl / a1 on the spear sheets; a1 plays once and falls back to nu
	if mode == _mode:
		return
	_mode = mode
	var loop := mode != "a1"
	anim.play("amazon/am_%s_2ht" % mode, loop)
	if not loop:
		_attacking = true
		if not anim.finished.is_connected(_attack_done):
			anim.finished.connect(_attack_done)


func _attack_done() -> void:
	_attacking = false
	_mode = ""
	_pose("nu")


func take_damage(dmg: float) -> void:
	hp -= dmg
	if hp <= 0.0:
		queue_free()


var _atk_cd := 0.0


func _physics_process(dt: float) -> void:
	lifetime -= dt
	if lifetime <= 0.0:
		queue_free()
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * dt
	else:
		velocity.y = 0.0
	if kind == "decoy" or world == null:
		move_and_slide()
		return
	_atk_cd -= dt
	var best: WowCreature = null
	var bd := 25.0
	for mob in world.monsters:
		if mob is WowCreature and mob.state != WowCreature.State.DEAD:
			var d: float = global_position.distance_to(mob.global_position)
			if d < bd:
				bd = d
				best = mob
	if best == null:
		velocity.x = 0
		velocity.z = 0
		if not _attacking:
			_pose("nu")
	else:
		var to := best.global_position - global_position
		to.y = 0.0
		if to.length() > 1.8:
			var dir := to.normalized()
			velocity.x = dir.x * speed
			velocity.z = dir.z * speed
			anim.facing = atan2(dir.x, dir.z)
			if not _attacking:
				_pose("wl")
		else:
			velocity.x = 0
			velocity.z = 0
			anim.facing = atan2(to.x, to.z)
			if _atk_cd <= 0.0:
				_atk_cd = 1.2
				_pose("a1")
				best.take_damage(randf_range(damage.x, damage.y))
	move_and_slide()
