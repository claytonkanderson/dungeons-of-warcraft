extends Node
## Autoloaded as GameState: player stats, XP/levels, D2 combat math.

signal leveled_up(level: int)
signal hp_changed
signal xp_changed

var character := ""           # active character slug ("" = legacy/test save)
var char_name := "Amazon"     # display name
var dungeons_done: Array = [] # completed dungeon ids (per character)
var current_dungeon := "ragefire-chasm"
var level := 1                # D2 start: level 1, nothing allocated
var xp := 0                   # seeded from the exp table in _ready
var skill_points := 0
var current_level := 1        # world level id
var waypoints: Array = [1]    # activated waypoint level ids
var session_loaded := false
var saved_level := 1
var _saved_action := ["Attack", "Attack"]
var stat := {"str": 20, "dex": 25, "vit": 20, "ene": 15}   # Amazon base
var hp := 50.0
var hp_max := 50.0
var mana := 15.0
var mana_max := 15.0
var exp_table: Array = []


func _ready() -> void:
	var gd: Dictionary = get_node("/root/SpriteDB").gamedata()
	exp_table = gd.get("experience", [])
	if xp == 0 and level > 1 and level <= exp_table.size():
		xp = int(str(exp_table[level - 1]))
	# charms count from the inventory, so its changes re-aggregate too
	inventory_changed.connect(_recalc)
	_recalc()
	hp = hp_max
	mana = mana_max


func grant_starter_kit() -> void:
	## Fresh character: level-appropriate gear (all equippable at base
	## stats), arrows in the off-hand, a stocked belt, walking money.
	var gen := get_node("/root/ItemGen")
	for pair in [["weap", "sbw"], ["tors", "hla"], ["head", "cap"],
			["glov", "lgl"], ["boot", "lbt"], ["belt", "vbl"]]:
		var inst: Dictionary = {}
		for attempt in range(6):
			inst = gen.maybe_magic(str(pair[1]), level)
			if not inst.is_empty() and int(inst.get("reqlvl", 0)) <= level:
				break
			inst = {}
		equipped[str(pair[0])] = {"code": pair[1], "inst": inst}
	equipped["shie"] = {"code": "aqv", "inst": {}}
	# a small charm of learning: +33% experience while it is carried
	inv_try_add("cm1", {"code": "cm1", "quality": "magic",
			"name": "Small Charm of Learning", "base_name": "Small Charm",
			"color": ItemGen.COLOR_MAGIC.to_html(), "reqlvl": 1,
			"props": [{"code": "addxp", "param": "", "min": "80", "max": "80", "val": 80}]})
	# and a plain javelin, so the javelin tree can be tried from the start
	inv_try_add("jav", {})
	belt = [{"code": "hp2", "count": 3}, {"code": "mp2", "count": 2}, {}, {}]
	gold = 250
	_recalc()
	hp = hp_max
	mana = mana_max
	equipment_changed.emit()
	inventory_changed.emit()


func _recalc() -> void:
	# D2 amazon: life 50 @lvl1, +2/lvl, +3 life/vit; equipment mods included
	_aggregate_mods()
	hp_max = 50.0 + 2.0 * (level - 1) + 3.0 * (float(stat.vit) - 20.0) \
			+ float(mods.get("hp", 0)) + float(mods.get("vit", 0)) * 3.0
	hp_max *= 1.0 + float(mods.get("hp%", 0)) / 100.0
	mana_max = 15.0 + 1.5 * (level - 1) + 1.5 * (float(stat.ene) - 15.0) \
			+ float(mods.get("mana", 0)) + float(mods.get("ene", 0)) * 1.5
	mana_max *= 1.0 + float(mods.get("mana%", 0)) / 100.0
	hp = minf(hp, hp_max)
	mana = minf(mana, mana_max)


signal equipment_changed

const SLOTS := ["head", "tors", "weap", "shie", "glov", "boot", "belt",
		"ring1", "ring2", "amul"]
var equipped := {}             # slot -> {code, inst}
var mods := {}                 # aggregated equipment modifiers
var stat_points := 0

# Equipment property codes that add straight into a mods key. Everything
# the game applies is listed in APPLIED_PROPS below; the tooltip dims any
# line whose code is not there, so no item promises what combat ignores.
const MOD_MAP := {
	"str": "str", "dex": "dex", "vit": "vit", "enr": "ene",
	"hp": "hp", "mana": "mana", "ac": "ac", "ac%": "ac%",
	"dmg%": "dmg%", "dmg-min": "dmg-min", "dmg-max": "dmg-max",
	"att": "ar", "att%": "ar%", "all-stats": "all-stats",
	"res-fire": "res-fire", "res-cold": "res-cold",
	"res-ltng": "res-ltng", "res-pois": "res-pois", "res-all": "res-all",
	"fire-min": "fire-min", "fire-max": "fire-max",
	"cold-min": "cold-min", "cold-max": "cold-max",
	"ltng-min": "ltng-min", "ltng-max": "ltng-max",
	"pois-min": "pois-min", "pois-max": "pois-max",
	"mag%": "mag%", "gold%": "gold%",
	# tier A: leech, on-kill, regeneration, stamina
	"lifesteal": "lifesteal", "manasteal": "manasteal",
	"heal-kill": "heal-kill", "mana-kill": "mana-kill", "demon-heal": "demon-heal",
	"regen": "regen", "regen-mana": "regen-mana", "regen-stam": "regen-stam",
	"stam": "stam", "stamdrain": "stamdrain", "hp%": "hp%", "mana%": "mana%",
	# defence
	"red-dmg": "red-dmg", "red-mag": "red-mag", "red-dmg%": "red-dmg%",
	"ac-miss": "ac-miss", "ac-hth": "ac-hth",
	"res-fire-max": "res-fire-max", "res-cold-max": "res-cold-max",
	"res-ltng-max": "res-ltng-max", "res-pois-max": "res-pois-max",
	"res-all-max": "res-all-max", "res-pois-len": "res-pois-len",
	"abs-fire": "abs-fire", "abs-cold": "abs-cold", "abs-ltng": "abs-ltng",
	"abs-fire%": "abs-fire%", "abs-cold%": "abs-cold%", "abs-ltng%": "abs-ltng%",
	"dmg-to-mana": "dmg-to-mana",
	# offence
	"crush": "crush", "deadly": "deadly", "openwounds": "openwounds",
	"pierce": "pierce", "dmg-undead": "dmg-undead", "dmg-demon": "dmg-demon",
	"att-undead": "ar-undead", "att-demon": "ar-demon",
	"cold-len": "cold-len", "pois-len": "pois-len",
	# speeds, requirements, light, find
	"swing1": "ias", "swing2": "ias", "swing3": "ias",
	"move1": "frw", "move2": "frw", "move3": "frw",
	"ease": "ease", "light": "light", "addxp": "addxp",
	# blocking: chance, and the two faster-block-rate codes
	"block": "block", "block2": "fbr", "block3": "fbr",
	# on-hit states and reflected damage
	"slow": "slow", "freeze": "freeze", "knock": "knock",
	"half-freeze": "half-freeze", "nofreeze": "nofreeze",
	"thorns": "thorns", "light-thorns": "light-thorns",
	# elemental mastery and pierce, cast rate, hit recovery, prevent heal
	"extra-fire": "extra-fire", "extra-cold": "extra-cold",
	"extra-ltng": "extra-ltng", "extra-pois": "extra-pois",
	"pierce-fire": "pierce-fire", "pierce-cold": "pierce-cold",
	"pierce-ltng": "pierce-ltng", "pierce-pois": "pierce-pois",
	"cast1": "fcr", "cast2": "fcr", "cast3": "fcr",
	"balance1": "fhr", "balance2": "fhr", "balance3": "fhr",
	"noheal": "noheal",
	"Light": "light",             # a mis-cased code in the unique tables
	# skills
	"allskills": "allskills", "ama": "ama", "fireskill": "fireskill",
	"magicarrow": "magicarrow", "explosivearrow": "explosivearrow",
}
# "Adds X-Y <element> damage": the table's min and max are the two ends of the
# damage, not a range to roll one value from
const RANGE_PROPS := {
	"dmg-fire": ["fire-min", "fire-max"], "dmg-cold": ["cold-min", "cold-max"],
	"dmg-ltng": ["ltng-min", "ltng-max"], "dmg-mag": ["mag-min", "mag-max"],
	"dmg-norm": ["dmg-norm-min", "dmg-norm-max"], "dmg-pois": ["pois-min", "pois-max"],
}
# "+N per character level" props: the table's param is N*8
const PER_LEVEL := {
	"hp/lvl": "hp", "mana/lvl": "mana", "ac/lvl": "ac", "att/lvl": "ar",
	"att%/lvl": "ar%", "dmg/lvl": "dmg-max", "dmg%/lvl": "dmg%",
	"vit/lvl": "vit", "str/lvl": "str", "dex/lvl": "dex", "stam/lvl": "stam",
	"regen-stam/lvl": "regen-stam", "abs-fire/lvl": "abs-fire",
	"abs-cold/lvl": "abs-cold", "res-ltng/lvl": "res-ltng",
	"att-und/lvl": "ar-undead", "dmg-und/lvl": "dmg-undead",
	"att-dem/lvl": "ar-demon", "dmg-dem/lvl": "dmg-demon",
	"deadly/lvl": "deadly", "thorns/lvl": "thorns", "mag%/lvl": "mag%",
	"gold%/lvl": "gold%",
}
# D2 skill tab ids -> the Amazon's pages (others belong to other classes)
const AMAZON_TABS := {0: 1, 1: 2, 2: 3}
var _applied_cache := {}


func applies(code: String) -> bool:
	## Does the game act on this property code? (tooltips dim the rest)
	if _applied_cache.is_empty():
		for k in MOD_MAP:
			_applied_cache[k] = true
		for k in RANGE_PROPS:
			_applied_cache[k] = true
		for k in PER_LEVEL:
			_applied_cache[k] = true
		for k in ["dmg", "dmg-elem", "skill", "oskill", "skilltab",
				"*hp", "*mana", "*vit", "*enr", "ethereal"]:
			_applied_cache[k] = true
	return _applied_cache.has(code)


func gear_elemental() -> float:
	## Rolled elemental damage from equipment, summed across elements.
	var total := 0.0
	for el in ["fire", "cold", "ltng", "pois"]:
		var mn := float(mods.get(el + "-min", 0))
		var mx := maxf(mn, float(mods.get(el + "-max", 0)))
		if mx > 0.0:
			total += randf_range(mn, mx)
	return total


func resist(etype: String) -> float:
	var key: String = {"fire": "res-fire", "cold": "res-cold", "ltng": "res-ltng",
			"lightning": "res-ltng", "pois": "res-pois",
			"poison": "res-pois"}.get(etype, "")
	if key == "":
		return 0.0
	# D2 caps at 75, raised by the "+N to Maximum <element> Resist" lines to 95
	var cap := 75.0 + float(mods.get(key + "-max", 0)) + float(mods.get("res-all-max", 0))
	return minf(minf(95.0, cap), float(mods.get(key, 0)) + float(mods.get("res-all", 0)))


var _setbonus := {}            # items/sets bonus tables (setbonus.json)
var _setmap := {}              # set item name -> set name (setitems.json)


func _load_setdata() -> void:
	if not _setbonus.is_empty():
		return
	var f := FileAccess.open(Paths.asset("items/setbonus.json"), FileAccess.READ)
	if f != null:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			_setbonus = d
	if _setbonus.is_empty():
		_setbonus = {"items": {}, "sets": {}}
	var f2 := FileAccess.open(Paths.asset("items/setitems.json"), FileAccess.READ)
	if f2 != null:
		var arr: Variant = JSON.parse_string(f2.get_as_text())
		if arr is Array:
			for it in arr:
				_setmap[str(it.get("name", ""))] = str(it.get("set", ""))


func set_worn_counts() -> Dictionary:
	## set name -> number of its pieces currently equipped
	_load_setdata()
	var counts := {}
	for slot in equipped:
		var inst: Dictionary = equipped[slot].get("inst", {})
		if str(inst.get("quality", "")) != "set":
			continue
		var sname := str(_setmap.get(str(inst.get("name", "")), ""))
		if sname != "":
			counts[sname] = int(counts.get(sname, 0)) + 1
	return counts


func _add_mod(key: String, amount: float) -> void:
	mods[key] = float(mods.get(key, 0.0)) + amount


func _apply_prop(p: Dictionary) -> void:
	var code := str(p.get("code", ""))
	if code.begins_with("*"):
		code = code.substr(1)        # hidden duplicate of the plain property
	var val := float(p.get("val", str(p.get("min", "0")).to_int()))
	var vmax := float(p.get("val_max", val))
	var param := str(p.get("param", ""))
	if RANGE_PROPS.has(code):
		var keys: Array = RANGE_PROPS[code]
		if code == "dmg-pois":
			# poison: min/max are damage per frame * 256 over param frames
			var frames := maxf(1.0, float(param.to_int()))
			_add_mod("pois-min", val * frames / 256.0)
			_add_mod("pois-max", vmax * frames / 256.0)
			_add_mod("pois-len", frames / 25.0)
		else:
			_add_mod(keys[0], val)
			_add_mod(keys[1], vmax)
			if code == "dmg-cold":
				_add_mod("cold-len", float(param.to_int()) / 25.0)
		return
	if code == "dmg-elem":
		for el in ["fire", "ltng", "cold"]:
			_add_mod(el + "-min", val)
			_add_mod(el + "-max", vmax)
		_add_mod("cold-len", float(param.to_int()) / 25.0)
		return
	if code == "dmg":
		_add_mod("dmg-min", val)
		_add_mod("dmg-max", val)
		return
	if PER_LEVEL.has(code):
		_add_mod(PER_LEVEL[code], float(param.to_int()) / 8.0 * float(level))
		return
	match code:
		"skill":
			var nm := _skill_by_param(param)
			if nm != "":
				skill_bonus[nm] = int(skill_bonus.get(nm, 0)) + int(val)
			return
		"oskill":
			var nm := _skill_by_param(param)
			if nm != "":
				oskills[nm] = maxi(int(oskills.get(nm, 0)), int(val))
			return
		"skilltab":
			var page: int = int(AMAZON_TABS.get(param.to_int(), -1))
			if page > 0:
				tab_bonus[page] = int(tab_bonus.get(page, 0)) + int(val)
			return
		"cold-len", "pois-len":
			_add_mod(code, val / 25.0)
			return
	var key = MOD_MAP.get(code)
	if key == null:
		return
	_add_mod(key, val)


func _skill_by_param(param: String) -> String:
	## Skill properties name their skill by id or by name in the tables.
	var gd: Dictionary = get_node("/root/SpriteDB").gamedata()
	var names: Dictionary = gd.get("skill_names", {})
	if names.has(param):
		return str(names[param])
	if gd.get("skills", {}).has(param):
		return param
	for n in gd.get("skills", {}):
		if str(n).to_lower() == param.to_lower():
			return str(n)
	return ""


var skill_bonus := {}          # item +N to a specific skill
var tab_bonus := {}            # item +N to an Amazon skill page
var oskills := {}              # item-granted skills (level), no points needed


func _charm_instances() -> Array:
	## Charms work from the inventory: every charm-type entry's instance.
	var out := []
	var gen := get_node("/root/ItemGen")
	var db := get_node("/root/ItemDB")
	for it in inv_items:
		var inst: Dictionary = it.get("inst", {})
		if inst.is_empty():
			continue
		var chain: Dictionary = gen.type_chain(
				str(db.item(str(it.get("code", ""))).get("type", "")))
		if chain.has("char"):
			out.append(inst)
	return out


func _aggregate_mods() -> void:
	mods = {}
	skill_bonus = {}
	tab_bonus = {}
	oskills = {}
	eth_weapon = false
	var sources := []
	for slot in equipped:
		sources.append(equipped[slot].get("inst", {}))
	sources.append_array(_charm_instances())
	var weapon_inst = equipped.get("weap", {}).get("inst", null)
	for inst in sources:
		var flat := []
		for p in inst.get("props", []):
			if p.has("affix"):
				flat.append_array(p.get("props", []))
			else:
				flat.append(p)
		var eth := false
		var acp := 0.0
		for p in flat:
			_apply_prop(p)
			match str(p.get("code", "")):
				"ethereal": eth = true
				"ac%": acp += float(p.get("val", str(p.get("min", "0")).to_int()))
		# the piece's own defence: its rolled base, enhanced by its own "+N%
		# Enhanced Defense" (which is why ac% is not applied globally), and
		# half again for an ethereal item, which is the trade for its wear
		var base_ac := float(inst.get("base_ac", 0))
		if base_ac > 0.0:
			_add_mod("ac", base_ac * (1.0 + acp / 100.0) * (1.5 if eth else 1.0))
		if eth and weapon_inst != null and is_same(inst, weapon_inst):
			eth_weapon = true
	# D2 set bonuses: per-item aprops unlock at 2..5 pieces worn; set-wide
	# partial bonuses stack per threshold; full bonus with the whole set
	var counts := set_worn_counts()
	if counts.is_empty():
		return
	for slot in equipped:
		var inst: Dictionary = equipped[slot].get("inst", {})
		if str(inst.get("quality", "")) != "set":
			continue
		var worn := int(counts.get(
			str(_setmap.get(str(inst.get("name", "")), "")), 0))
		var aprops: Array = _setbonus.get("items", {}) \
				.get(str(inst.get("name", "")), [])
		for i in range(aprops.size()):
			if worn >= i + 2:
				for p in aprops[i]:
					_apply_prop(p)
	for sname in counts:
		var sdef: Dictionary = _setbonus.get("sets", {}).get(sname, {})
		var worn := int(counts[sname])
		var partial: Array = sdef.get("partial", [])
		for i in range(partial.size()):
			if worn >= i + 2:
				for p in partial[i]:
					_apply_prop(p)
		if worn >= 2 and worn >= int(sdef.get("count", 99)):
			for p in sdef.get("full", []):
				_apply_prop(p)


func total_stat(name: String) -> int:
	return int(stat.get(name, 0)) + int(mods.get(name, 0)) \
			+ int(mods.get("all-stats", 0))


func attack_rating() -> float:
	var ar := (float(total_stat("dex")) - 7.0) * 5.0 + (level - 1) * 5.0
	ar += float(mods.get("ar", 0))
	ar *= 1.0 + float(mods.get("ar%", 0)) / 100.0
	# Penetrate passive
	var pen := skill_level("Penetrate")
	if pen > 0:
		ar *= 1.0 + (0.30 + 0.10 * (pen - 1))
	return ar


# --- Amazon passives -------------------------------------------------------
func crit_chance() -> float:
	var l := skill_level("Critical Strike")
	return 0.0 if l <= 0 else minf(0.05 + 0.11 * pow(l, 0.5), 0.6)


func pierce_chance() -> float:
	var l := skill_level("Pierce")
	var c := 0.0 if l <= 0 else 0.15 + 0.08 * l
	return minf(c + float(mods.get("pierce", 0)) / 100.0, 0.85)


func shield_item() -> Dictionary:
	## The base item in the off-hand slot when it is a shield (a quiver is
	## not one), else {}.
	var s: Dictionary = equipped.get("shie", {})
	if s.is_empty():
		return {}
	var it: Dictionary = get_node("/root/ItemDB").item(str(s.get("code", "")))
	var chain: Dictionary = get_node("/root/ItemGen").type_chain(str(it.get("type", "")))
	return it if chain.has("shie") else {}


func block_chance() -> float:
	## D2: (shield block% + class block factor + item bonuses) * (dex - 15)
	## / (2 * level), capped at 75%. No shield, no block.
	var it := shield_item()
	if it.is_empty():
		return 0.0
	var gd: Dictionary = get_node("/root/SpriteDB").gamedata()
	var base := str(it.get("block", "0")).to_int() \
			+ str(gd.get("charstats", {}).get("BlockFactor", "0")).to_int() \
			+ int(mods.get("block", 0))
	var c := float(base) * (float(total_stat("dex")) - 15.0) / (2.0 * float(level))
	return clampf(c, 0.0, 75.0) / 100.0


func block_recovery() -> float:
	## Seconds the shield arm is busy after a block; faster block rate cuts it
	return 0.45 / (1.0 + minf(200.0, float(mods.get("fbr", 0))) / 100.0)


func attack_speed_factor() -> float:
	## Increased attack speed: D2 tops out around +75% effective
	return 1.0 + minf(75.0, float(mods.get("ias", 0))) / 100.0


func run_speed_factor() -> float:
	return 1.0 + float(mods.get("frw", 0)) / 100.0


func stamina_max() -> float:
	return 100.0 + float(mods.get("stam", 0))


func dodge_chance() -> float:      # vs melee
	var l := skill_level("Dodge")
	return 0.0 if l <= 0 else minf(0.10 + 0.06 * l, 0.56)


func avoid_chance() -> float:      # vs missiles
	var l := maxi(skill_level("Avoid"), skill_level("Evade"))
	return 0.0 if l <= 0 else minf(0.12 + 0.06 * l, 0.65)


func player_defense() -> float:
	# "ac" already carries each piece's base with its own enhancement
	return float(total_stat("dex")) * 0.25 + float(mods.get("ac", 0))


var eth_weapon := false          # the wielded weapon is ethereal: +50% base


func skill_elem_mult(etype: String) -> float:
	## "+N% to Fire Skill Damage" and its kin: the skills' own elemental damage
	var key: String = {"fire": "extra-fire", "cold": "extra-cold",
			"ltng": "extra-ltng", "lightning": "extra-ltng",
			"pois": "extra-pois", "poison": "extra-pois"}.get(etype, "")
	if key == "":
		return 1.0
	return 1.0 + float(mods.get(key, 0)) / 100.0


func enemy_res_pierce(etype: String) -> float:
	## "-N% to Enemy Fire Resistance" and its kin
	var key: String = {"fire": "pierce-fire", "cold": "pierce-cold",
			"ltng": "pierce-ltng", "lightning": "pierce-ltng",
			"pois": "pierce-pois", "poison": "pierce-pois"}.get(etype, "")
	if key == "":
		return 0.0
	return float(mods.get(key, 0))


func cast_speed_factor() -> float:
	## "+N% Faster Cast Rate" quickens the spells the way attack speed
	## quickens the blows
	return 1.0 + minf(200.0, float(mods.get("fcr", 0))) / 100.0


func hit_recovery() -> float:
	## Seconds a solid blow (a twelfth of max life or more) staggers the
	## character: the Amazon's 11 frames, shortened by "+N% Faster Hit Recovery"
	return 0.44 / (1.0 + float(mods.get("fhr", 0)) / 100.0)


func prevents_heal() -> bool:
	## "Prevents Monster Heal"
	return float(mods.get("noheal", 0)) > 0.0


func weapon_class(code: String) -> String:
	## The D2 animation class an equipped weapon puts the Amazon in: one of
	## hth / bow / xbw / 1hs / 1ht / 2hs / 2ht / stf.
	##
	## weapons.txt names it outright, which is the only way a two-hander gets
	## its own stance instead of the one-handed one; the type walk is the
	## fallback for anything the table does not answer. Both the first-person
	## attack and the menu paperdoll read this, and they used to disagree.
	if code == "":
		return "hth"
	var it: Dictionary = get_node("/root/ItemDB").item(code)
	var named := str(it.get("2handedwclass" if str(it.get("2handed", "")) == "1"
			else "wclass", "")).to_lower()
	if named in ["hth", "bow", "xbw", "1hs", "1ht", "2hs", "2ht", "stf"]:
		return named
	var chain: Dictionary = get_node("/root/ItemGen").type_chain(
			str(it.get("type", "")))
	if chain.has("bow"):
		return "bow"
	if chain.has("xbow"):
		return "xbw"
	if chain.has("jave") or chain.has("spea"):
		return "1ht"
	if chain.has("staf") or chain.has("pole"):
		return "stf"
	if chain.has("weap"):
		return "1hs"
	return "hth"


func slot_for(code: String) -> String:
	var chain: Dictionary = get_node("/root/ItemGen").type_chain(
		str(get_node("/root/ItemDB").item(code).get("type", "")))
	if chain.has("helm") or chain.has("phlm"):
		return "head"
	if chain.has("tors"):
		return "tors"
	if chain.has("shie") or chain.has("ashd"):
		return "shie"
	if chain.has("glov"):
		return "glov"
	if chain.has("boot"):
		return "boot"
	if chain.has("belt"):
		return "belt"
	if chain.has("ring"):
		return "ring2" if not equipped.get("ring1", {}).is_empty() \
				and equipped.get("ring2", {}).is_empty() else "ring1"
	if chain.has("amul"):
		return "amul"
	if chain.has("weap"):
		return "weap"
	return ""


signal equip_refused(reason: String)


func equip_requirements(entry: Dictionary) -> Dictionary:
	## {lvl, str, dex}: base item requirements + the instance's reqlvl.
	var it: Dictionary = get_node("/root/ItemDB").item(str(entry.get("code", "")))
	var inst: Dictionary = entry.get("inst", {})
	# "Requirements -N%" on the item itself (D2 stores ease as a negative)
	var ease := 1.0
	for p in inst.get("props", []):
		var flat: Array = p.get("props", [p]) if p.has("affix") else [p]
		for q in flat:
			if str(q.get("code", "")) == "ease":
				ease += float(q.get("val", str(q.get("min", "0")).to_int())) / 100.0
	ease = clampf(ease, 0.0, 1.0)
	return {
		"lvl": maxi(int(inst.get("reqlvl", 0)), str(it.get("levelreq", "")).to_int()),
		"str": int(str(it.get("reqstr", "")).to_int() * ease),
		"dex": int(str(it.get("reqdex", "")).to_int() * ease),
	}


func can_equip(entry: Dictionary) -> String:
	## "" if equippable, else the reason it is not.
	var req := equip_requirements(entry)
	if level < int(req.lvl):
		return "I need to be level %d" % req.lvl
	if total_stat("str") < int(req.str):
		return "I need %d Strength" % req.str
	if total_stat("dex") < int(req.dex):
		return "I need %d Dexterity" % req.dex
	return ""


func equip_entry(entry: Dictionary) -> bool:
	var slot := slot_for(str(entry.get("code", "")))
	if slot == "":
		return false
	var reason := can_equip(entry)
	if reason != "":
		equip_refused.emit(reason)
		return false
	inv_items.erase(entry)
	var old: Dictionary = equipped.get(slot, {})
	equipped[slot] = {"code": entry.get("code", ""), "inst": entry.get("inst", {})}
	if not old.is_empty():
		inv_try_add(str(old.get("code", "")), old.get("inst", {}))
	_recalc()
	equipment_changed.emit()
	inventory_changed.emit()
	return true


func unequip(slot: String) -> void:
	var old: Dictionary = equipped.get(slot, {})
	if old.is_empty():
		return
	if inv_try_add(str(old.get("code", "")), old.get("inst", {})):
		equipped.erase(slot)
		_recalc()
		equipment_changed.emit()


func allocate_stat(name: String) -> bool:
	if stat_points <= 0 or not stat.has(name):
		return false
	stat[name] = int(stat[name]) + 1
	_recalc()
	stat_points -= 1
	hp_changed.emit()
	return true


# Player damage against D2's monster curve. Monster life now follows
# MonLvl.txt (7 at level 1, 35 at 10, 73 at 20), which a D2-table weapon
# already kills in two to four hits; a small boost keeps the FPS pace brisk.
const DMG_MULT := 1.5


func weapon_damage(thrown := false) -> Vector2:
	# equipped weapon base damage (2-hand columns cover bows), else bare 2-6;
	# a thrown javelin uses its throw columns rather than its stab
	var mn := 2.0
	var mx := 6.0
	var w: Dictionary = equipped.get("weap", {})
	if not w.is_empty():
		var it: Dictionary = get_node("/root/ItemDB").item(str(w.get("code", "")))
		var bmn := str(it.get("2handmindam", "")).to_int()
		var bmx := str(it.get("2handmaxdam", "")).to_int()
		if thrown and str(it.get("maxmisdam", "")).to_int() > 0:
			bmn = str(it.get("minmisdam", "")).to_int()
			bmx = str(it.get("maxmisdam", "")).to_int()
		elif bmx == 0:
			bmn = str(it.get("mindam", "")).to_int()
			bmx = str(it.get("maxdam", "")).to_int()
		if bmx > 0:
			mn = float(bmn)
			mx = float(bmx)
		if eth_weapon:
			mn *= 1.5
			mx *= 1.5
	var ed := float(mods.get("dmg%", 0)) + float(total_stat("dex"))
	mn = (mn * (1.0 + ed / 100.0) + float(mods.get("dmg-min", 0))
			+ float(mods.get("dmg-norm-min", 0))) * DMG_MULT
	mx = (mx * (1.0 + ed / 100.0) + float(mods.get("dmg-max", 0))
			+ float(mods.get("dmg-norm-max", 0))) * DMG_MULT
	return Vector2(mn, maxf(mn, mx))


func roll_player_hit(ranged: bool, ctype := "", thrown := false) -> Dictionary:
	## One blow's worth of numbers, D2 order: physical (critical strike, then
	## deadly strike doubles it; +% vs undead/demons), elemental per element
	## with cold length and poison duration, crushing blow, open wounds, and
	## the life/mana the physical part leeches.
	var wd := weapon_damage(thrown)
	var phys := randf_range(wd.x, wd.y)
	if randf() < crit_chance():
		phys *= 2.0
	elif randf() < float(mods.get("deadly", 0)) / 100.0:
		phys *= 2.0
	if ctype == "undead":
		phys *= 1.0 + float(mods.get("dmg-undead", 0)) / 100.0
	elif ctype == "demon":
		phys *= 1.0 + float(mods.get("dmg-demon", 0)) / 100.0
	var elem := {}
	for el in ["fire", "cold", "ltng", "mag"]:
		var lo := float(mods.get(el + "-min", 0))
		var hi := maxf(lo, float(mods.get(el + "-max", 0)))
		if hi > 0.0:
			elem[el] = randf_range(lo, hi) * DMG_MULT
	var pois_total := 0.0
	var pois_len := float(mods.get("pois-len", 0))
	if float(mods.get("pois-max", 0)) > 0.0:
		pois_total = randf_range(float(mods.get("pois-min", 0)),
				float(mods.get("pois-max", 0))) * DMG_MULT
		if pois_len <= 0.0:
			pois_len = 2.0
	return {
		"phys": phys, "elem": elem,
		"cold_len": float(mods.get("cold-len", 0)) if elem.has("cold") else 0.0,
		"pois_total": pois_total, "pois_len": pois_len,
		# D2: crushing blow takes a quarter of current life in melee, an eighth
		# from range; open wounds bleeds for eight seconds
		"crush": randf() < float(mods.get("crush", 0)) / 100.0,
		"crush_frac": 0.125 if ranged else 0.25,
		"openwounds": randf() < float(mods.get("openwounds", 0)) / 100.0,
		"ow_dps": (9.0 * level + 31.0) / 10.24 * DMG_MULT / 5.0,
		"lifesteal": phys * float(mods.get("lifesteal", 0)) / 100.0,
		"manasteal": phys * float(mods.get("manasteal", 0)) / 100.0,
		# "Slows Target by N%", "Freezes Target +N", "Knockback"
		"slow_pct": float(mods.get("slow", 0)),
		"freeze": 1.0 + 0.5 * float(mods.get("freeze", 0)) if float(mods.get("freeze", 0)) > 0.0 else 0.0,
		"knock": int(mods.get("knock", 0)) > 0,
		"noheal": prevents_heal(),
	}


func is_javelin() -> bool:
	## the equipped weapon is a javelin (the throw skills need one)
	var w: Dictionary = equipped.get("weap", {})
	if w.is_empty():
		return false
	var it: Dictionary = get_node("/root/ItemDB").item(str(w.get("code", "")))
	var chain: Dictionary = get_node("/root/ItemGen").type_chain(str(it.get("type", "")))
	return chain.has("jave") or chain.has("ajav")


func on_hit_dealt(h: Dictionary) -> void:
	if float(h.get("lifesteal", 0.0)) > 0.0:
		hp = minf(hp_max, hp + float(h["lifesteal"]))
		hp_changed.emit()
	if float(h.get("manasteal", 0.0)) > 0.0:
		mana = minf(mana_max, mana + float(h["manasteal"]))


func on_kill(ctype: String) -> void:
	## "+N life/mana after each kill", "+N life after each demon kill"
	var heal := float(mods.get("heal-kill", 0))
	if ctype == "demon":
		heal += float(mods.get("demon-heal", 0))
	if heal > 0.0:
		hp = minf(hp_max, hp + heal)
		hp_changed.emit()
	if float(mods.get("mana-kill", 0)) > 0.0:
		mana = minf(mana_max, mana + float(mods.get("mana-kill", 0)))


static func chance_to_hit(ar: float, defense: float, alvl: int, dlvl: int) -> float:
	var c: float = 2.0 * (ar / maxf(1.0, ar + defense)) \
			* (float(alvl) / maxf(1.0, float(alvl + dlvl)))
	return clampf(c, 0.05, 0.95)


func award_xp(amount: int) -> void:
	amount = int(amount * (1.0 + float(mods.get("addxp", 0)) / 100.0))
	xp += amount
	xp_changed.emit()
	while level < exp_table.size() and xp >= int(exp_table[level]):
		level += 1
		skill_points += 1
		stat_points += 5
		stat.str += 0   # stat points UI comes with the tree milestone
		_recalc()
		hp = hp_max
		mana = mana_max
		leveled_up.emit(level)
		get_node("/root/Sfx").event_ui("level_up")


func take_damage(dmg: float, etype := "phys", ranged := false) -> bool:
	## Incoming damage through the character's reductions: physical gets the
	## flat and percent damage reductions; elemental gets resistance, the flat
	## magic reduction, then flat and percent absorb. A share can return as
	## mana ("damage taken goes to mana").
	var raw := dmg
	if etype == "phys":
		dmg -= float(mods.get("red-dmg", 0))
		dmg *= 1.0 - minf(50.0, float(mods.get("red-dmg%", 0))) / 100.0
	else:
		dmg *= 1.0 - resist(etype) / 100.0
		dmg -= float(mods.get("red-mag", 0))
		var key: String = {"fire": "fire", "cold": "cold", "ltng": "ltng",
				"lightning": "ltng"}.get(etype, "")
		if key != "":
			dmg -= float(mods.get("abs-" + key, 0))
			dmg *= 1.0 - minf(40.0, float(mods.get("abs-" + key + "%", 0))) / 100.0
	dmg = maxf(0.0, dmg)
	var to_mana := float(mods.get("dmg-to-mana", 0))
	if to_mana > 0.0:
		mana = minf(mana_max, mana + raw * to_mana / 100.0)
	hp = max(0.0, hp - dmg)
	hp_changed.emit()
	return hp <= 0.0


func respawn() -> void:
	hp = hp_max
	mana = mana_max
	hp_changed.emit()


# ---------------------------------------------------------------------------
# Inventory: D2-style grid, items occupy invwidth x invheight cells
# ---------------------------------------------------------------------------
const INV_W := 10
const INV_H := 4

signal inventory_changed

var inv_items: Array = []      # {code, x, y, w, h}
var gold := 0


func inv_fits(x: int, y: int, w: int, h: int, ignore = null) -> bool:
	if x < 0 or y < 0 or x + w > INV_W or y + h > INV_H:
		return false
	for it in inv_items:
		if it == ignore:
			continue
		if x < it.x + it.w and it.x < x + w and y < it.y + it.h and it.y < y + h:
			return false
	return true


func inv_try_add(code: String, inst := {}) -> bool:
	var def: Dictionary = get_node("/root/ItemDB").item(code)
	var w := maxi(1, int(str(def.get("invwidth", "1"))))
	var h := maxi(1, int(str(def.get("invheight", "1"))))
	for y in range(INV_H):
		for x in range(INV_W):
			if inv_fits(x, y, w, h):
				var entry := {"code": code, "x": x, "y": y, "w": w, "h": h}
				if not inst.is_empty():
					entry["inst"] = inst
				inv_items.append(entry)
				inventory_changed.emit()
				return true
	return false


func inv_move(entry: Dictionary, x: int, y: int) -> bool:
	if not inv_fits(x, y, entry.w, entry.h, entry):
		return false
	entry.x = x
	entry.y = y
	inventory_changed.emit()
	return true


func add_gold(amount: int) -> void:
	gold += amount
	inventory_changed.emit()


# ---------------------------------------------------------------------------
# Belt & potions
# ---------------------------------------------------------------------------
const POTION_HEAL := {"hp1": 30, "hp2": 60, "hp3": 100, "hp4": 180, "hp5": 320}
const POTION_MANA := {"mp1": 20, "mp2": 40, "mp3": 80, "mp4": 150, "mp5": 250}

var belt: Array = [{}, {}, {}, {}]     # {code, count} per slot
var stash_items: Array = []            # same entry shape as inv_items


func is_potion(code: String) -> bool:
	return POTION_HEAL.has(code) or POTION_MANA.has(code) \
			or code in ["rvs", "rvl"]


func belt_add(code: String) -> bool:
	for slot in belt:
		if str(slot.get("code", "")) == code:
			slot["count"] = int(slot.get("count", 0)) + 1
			inventory_changed.emit()
			return true
	for i in range(belt.size()):
		if belt[i].is_empty() or int(belt[i].get("count", 0)) <= 0:
			belt[i] = {"code": code, "count": 1}
			inventory_changed.emit()
			return true
	return false


func drink(i: int) -> void:
	if i < 0 or i >= belt.size() or belt[i].is_empty():
		return
	var code := str(belt[i].get("code", ""))
	if int(belt[i].get("count", 0)) <= 0:
		return
	if POTION_HEAL.has(code):
		hp = minf(hp_max, hp + float(POTION_HEAL[code]))
	elif POTION_MANA.has(code):
		mana = minf(mana_max, mana + float(POTION_MANA[code]))
	elif code == "rvs":
		hp = minf(hp_max, hp + hp_max * 0.35)
		mana = minf(mana_max, mana + mana_max * 0.35)
	elif code == "rvl":
		hp = hp_max
		mana = mana_max
	else:
		return
	belt[i]["count"] = int(belt[i]["count"]) - 1
	if belt[i]["count"] <= 0:
		belt[i] = {}
	get_node("/root/Sfx").event_ui("potion_drink")
	hp_changed.emit()
	inventory_changed.emit()


# ---------------------------------------------------------------------------
# Skills
# ---------------------------------------------------------------------------
signal skills_changed

var skills := {}               # skill name -> points allocated
var hotkeys := {}              # "F1".."F5" -> skill name (D2-style binds)


var poison_dps := 0.0
var poison_t := 0.0


func poison(dps: float, duration: float) -> void:
	## Apply a poison DoT (caller pre-applies resistance).
	poison_dps = maxf(poison_dps, dps)
	poison_t = maxf(poison_t, duration)


func is_poisoned() -> bool:
	return poison_t > 0.0


func _process(dt: float) -> void:
	# D2-style slow mana regeneration, sped up by "+N% Regenerate Mana";
	# "Replenish Life +N" restores N*25/256 life a second
	mana = minf(mana_max, mana + mana_max * dt / 30.0
			* (1.0 + float(mods.get("regen-mana", 0)) / 100.0))
	var regen := float(mods.get("regen", 0))
	if regen > 0.0 and hp > 0.0 and hp < hp_max:
		hp = minf(hp_max, hp + regen * 25.0 / 256.0 * dt)
		hp_changed.emit()
	if poison_t > 0.0:
		poison_t -= dt
		# poison never quite kills in D2: stop at a sliver of life
		hp = maxf(1.0, hp - poison_dps * dt)
		hp_changed.emit()
		if poison_t <= 0.0:
			poison_dps = 0.0


func skill_row(n: String) -> Dictionary:
	return get_node("/root/SpriteDB").gamedata().get("skills", {}).get(n, {})


func skill_level(n: String) -> int:
	## Points spent plus item bonuses (+all, +Amazon, +tab, +skill, +fire
	## skills), which only apply to a skill with at least one point — except
	## skills an item grants outright (oskill, "fires magic arrows").
	var base := int(skills.get(n, 0))
	var granted := int(oskills.get(n, 0))
	if n == "Magic Arrow":
		granted = maxi(granted, int(mods.get("magicarrow", 0)))
	elif n == "Exploding Arrow":
		granted = maxi(granted, int(mods.get("explosivearrow", 0)))
	if base <= 0 and granted <= 0:
		return 0
	var bonus := int(mods.get("allskills", 0)) + int(mods.get("ama", 0)) \
			+ int(skill_bonus.get(n, 0))
	var sd: Dictionary = get_node("/root/SpriteDB").gamedata() \
			.get("skilldesc", {}).get(n.to_lower(), {})
	bonus += int(tab_bonus.get(str(sd.get("page", "0")).to_int(), 0))
	if str(skill_row(n).get("EType", "")).strip_edges() == "fire":
		bonus += int(mods.get("fireskill", 0))
	return maxi(base, granted) + bonus


func mana_cost(n: String) -> float:
	if n in ["Attack", "Throw"]:
		return 0.0
	return float(str(skill_row(n).get("mana", "0")).to_int()) / 8.0


func can_allocate(n: String) -> bool:
	if skill_points <= 0 or skill_level(n) >= 20:
		return false
	var r := skill_row(n)
	if r.is_empty():
		return false
	if level < int(str(r.get("reqlevel", "1")).to_int()):
		return false
	for k in ["reqskill1", "reqskill2", "reqskill3"]:
		var req := str(r.get(k, "")).strip_edges()
		if req != "" and skill_level(req) <= 0:
			return false
	return true


func allocate(n: String) -> bool:
	if not can_allocate(n):
		return false
	skills[n] = skill_level(n) + 1
	skill_points -= 1
	skills_changed.emit()
	return true


# ---------------------------------------------------------------------------
# Characters / save / load
# ---------------------------------------------------------------------------
const SAVE_PATH := "user://amazon_deadmines_save.json"   # legacy/test slot
const CHAR_DIR := "user://characters"


func _save_path() -> String:
	if character == "":
		return SAVE_PATH
	return CHAR_DIR + "/%s.json" % character


static func slugify(disp: String) -> String:
	var out := ""
	for ch in disp.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			out += ch
		elif ch == " " or ch == "-" or ch == "_":
			out += "-"
	return out.substr(0, 24)


func reset_state() -> void:
	## Fresh-character defaults: D2's level-1 start.
	level = 1
	skill_points = 0
	stat_points = 0
	stat = {"str": 20, "dex": 25, "vit": 20, "ene": 15}
	skills = {}
	hotkeys = {}
	equipped = {}
	inv_items = []
	gold = 0
	belt = [{}, {}, {}, {}]
	stash_items = []
	dungeons_done = []
	current_dungeon = "ragefire-chasm"
	_saved_action = ["Attack", "Attack"]
	xp = int(str(exp_table[level - 1])) if level <= exp_table.size() else 0
	poison_dps = 0.0
	poison_t = 0.0
	_recalc()
	hp = hp_max
	mana = mana_max


func list_characters() -> Array:
	## [{slug, name, level, dungeon}] for the roster UI.
	var out := []
	var dir := DirAccess.open(CHAR_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var fh := FileAccess.open(CHAR_DIR + "/" + f, FileAccess.READ)
		if fh == null:
			continue
		var d: Variant = JSON.parse_string(fh.get_as_text())
		if d is Dictionary:
			out.append({"slug": f.trim_suffix(".json"),
					"name": str(d.get("name", f.trim_suffix(".json"))),
					"level": int(d.get("level", 1)),
					"dungeon": str(d.get("current_dungeon", "deadmines"))})
	return out


func create_character(disp: String) -> String:
	## Returns the new slug, or "" when the name is taken/invalid.
	var slug := slugify(disp)
	if slug == "":
		return ""
	DirAccess.make_dir_recursive_absolute(CHAR_DIR)
	if FileAccess.file_exists(CHAR_DIR + "/%s.json" % slug):
		return ""
	character = slug
	char_name = disp.strip_edges()
	reset_state()
	grant_starter_kit()
	save_game(null)
	session_loaded = true
	return slug


func select_character(slug: String) -> bool:
	character = slug
	if load_game(null):
		session_loaded = true
		return true
	return false


func delete_character(slug: String) -> void:
	DirAccess.remove_absolute(CHAR_DIR + "/%s.json" % slug)
	if character == slug:
		character = ""
		session_loaded = false


func migrate_legacy_save() -> void:
	## The pre-roster single save becomes the first character slot. The
	## project rename also moved user://, so the old "Amazon Deadmines"
	## app-data directory is checked as a fallback (copied, not moved).
	if not list_characters().is_empty():
		return
	var old_dir := OS.get_user_data_dir().get_base_dir() \
			.path_join("Amazon Deadmines")
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		f = FileAccess.open(old_dir.path_join("amazon_deadmines_save.json"),
				FileAccess.READ)
	if f == null:
		return
	var d: Variant = JSON.parse_string(f.get_as_text())
	if not (d is Dictionary):
		return
	d["name"] = "Amazon"
	DirAccess.make_dir_recursive_absolute(CHAR_DIR)
	var out := FileAccess.open(CHAR_DIR + "/amazon.json", FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify(d))
		out.close()
		if FileAccess.file_exists(SAVE_PATH):
			DirAccess.remove_absolute(SAVE_PATH)
	# volume settings ride along once too
	if not FileAccess.file_exists("user://settings.json"):
		var sf := FileAccess.open(old_dir.path_join("settings.json"),
				FileAccess.READ)
		if sf != null:
			var so := FileAccess.open("user://settings.json", FileAccess.WRITE)
			if so != null:
				so.store_string(sf.get_as_text())


func enter_dungeon(id: String) -> void:
	## Selecting a different dungeon drops the saved position.
	if current_dungeon != id:
		current_dungeon = id
	save_game(null)


func complete_dungeon() -> bool:
	## Final boss down: record it. Returns true the first time.
	if dungeons_done.has(current_dungeon):
		return false
	dungeons_done.append(current_dungeon)
	return true


# Bumped whenever the save layout changes in a way load_game cannot absorb by
# defaults alone; _migrate_save brings older files up one step at a time.
const SAVE_VERSION := 2

# 1 -> 2: Scarlet Monastery became its four wings
const SM_WINGS := ["scarlet-monastery-graveyard", "scarlet-monastery-library",
		"scarlet-monastery-armory", "scarlet-monastery-cathedral"]


func _migrate_save(d: Dictionary) -> Dictionary:
	## Files written before the field existed are version 0 — the level-1
	## start era and earlier; those characters keep the level they reached.
	var v := int(d.get("version", 0))
	if v > SAVE_VERSION:
		printerr("save is version %d, newer than this build understands (%d)"
				% [v, SAVE_VERSION])
	if v < 1:
		# 0 -> 1: the field itself is the change; every value still loads
		# through its default
		pass
	if v < 2:
		# 1 -> 2: the one Scarlet Monastery entry is now four wings. A clear
		# of the whole counts for all four; a character standing in it
		# starts over at the Graveyard.
		var done: Array = d.get("dungeons_done", [])
		if done.has("scarlet-monastery"):
			done.erase("scarlet-monastery")
			for w in SM_WINGS:
				if not done.has(w):
					done.append(w)
			d["dungeons_done"] = done
		if str(d.get("current_dungeon", "")) == "scarlet-monastery":
			d["current_dungeon"] = SM_WINGS[0]
	d["version"] = SAVE_VERSION
	return d


func save_game(player) -> void:
	var d := {
		"version": SAVE_VERSION,
		"name": char_name,
		"level": level, "xp": xp, "skill_points": skill_points,
		"stat": stat, "skills": skills, "gold": gold,
		"inv": inv_items, "hp": hp, "mana": mana,
		"stat_points": stat_points, "equipped": equipped,
		"current_level": current_level, "waypoints": waypoints,
		"belt": belt, "stash": stash_items, "hotkeys": hotkeys,
		"dungeons_done": dungeons_done, "current_dungeon": current_dungeon,
	}
	# progression only, never position: a dungeon is always entered at
	# its start, so a save carries the character and not where they stood
	if player != null:
		d["action"] = player.action_skill
		_saved_action = player.action_skill
	else:
		d["action"] = _saved_action
	if character != "":
		DirAccess.make_dir_recursive_absolute(CHAR_DIR)
	var f := FileAccess.open(_save_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(d))
		f.close()


func load_game(player) -> bool:
	var f := FileAccess.open(_save_path(), FileAccess.READ)
	if f == null:
		return false
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	if d == null or d.is_empty():
		return false
	d = _migrate_save(d)
	level = int(d.get("level", 1))
	xp = int(d.get("xp", 0))
	skill_points = int(d.get("skill_points", 0))
	stat = d.get("stat", stat)
	skills = d.get("skills", {})
	gold = int(d.get("gold", 0))
	inv_items = d.get("inv", [])
	stat_points = int(d.get("stat_points", 0))
	equipped = d.get("equipped", {})
	_recalc()
	hp = float(d.get("hp", hp_max))
	mana = float(d.get("mana", mana_max))
	belt = d.get("belt", [{}, {}, {}, {}])
	stash_items = d.get("stash", [])
	hotkeys = d.get("hotkeys", {})
	char_name = str(d.get("name", char_name))
	dungeons_done = d.get("dungeons_done", [])
	current_dungeon = str(d.get("current_dungeon", "deadmines"))
	current_level = int(d.get("current_level", 1))
	waypoints = d.get("waypoints", [1])
	if not waypoints.has(1):
		waypoints.append(1)
	saved_level = current_level
	# a damage-over-time effect must not survive a load or a switch
	poison_dps = 0.0
	poison_t = 0.0
	_saved_action = d.get("action", ["Attack", "Attack"])
	if player != null:
		var act: Array = d.get("action", ["Attack", "Attack"])
		player.action_skill = [str(act[0]), str(act[1])]
	inventory_changed.emit()
	skills_changed.emit()
	equipment_changed.emit()
	return true
