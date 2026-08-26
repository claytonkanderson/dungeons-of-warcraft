class_name Ally
extends CharacterBody3D
## Friendly summon: Valkyrie (chases and strikes monsters) or Decoy (stands).

const GRAVITY := 22.0

var kind := "valkyrie"        # or "decoy"
var hp := 100.0
var damage := Vector2(8, 16)
var speed := 3.2
var lifetime := 45.0
var world = null

@onready var anim: BillboardAnim = $BillboardAnim


static func spawn(world_node, at: Vector3, skind: String, lvl: int) -> Ally:
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
	var an := BillboardAnim.new()
	an.name = "BillboardAnim"
	a.add_child(an)
	world_node.add_child(a)
	a.global_position = at + Vector3(0, 0.2, 0)
	if skind == "valkyrie":
		a.hp = 80.0 + 40.0 * lvl
		a.damage = Vector2(4 + 4 * lvl, 10 + 6 * lvl)
		a.anim.play("monsters/valkyrie/valkyrie_nu_hth", true)
	else:
		a.hp = 30.0 + 15.0 * lvl
		a.lifetime = 12.0 + 2.0 * lvl
		a.anim.play("amazon/am_nu_bow", true)
	return a


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
	else:
		var to := best.global_position - global_position
		to.y = 0.0
		if to.length() > 1.8:
			var dir := to.normalized()
			velocity.x = dir.x * speed
			velocity.z = dir.z * speed
			anim.facing = atan2(dir.x, dir.z)
			var pairs = get_node("/root/SpriteDB").load_sheet(
				"monsters/valkyrie/valkyrie_wl_hth")
			if pairs != null and not str(anim.sheet).contains("wl"):
				pass
		else:
			velocity.x = 0
			velocity.z = 0
			anim.facing = atan2(to.x, to.z)
			if _atk_cd <= 0.0:
				_atk_cd = 1.2
				best.take_damage(randf_range(damage.x, damage.y))
	move_and_slide()
