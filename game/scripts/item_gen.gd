extends Node
## Autoloaded as ItemGen: turns a dropped base item into an instance the way
## Diablo II does — quality by the ItemRatio formula, uniques and sets picked
## from the base's own candidates by rarity, affixes by level, type, group
## and frequency, every property rolled inside its table range.
##
## An instance: {code, quality, name, base_name, props, color, ilvl, reqlvl}
##
## The one deliberate departure from D2 is RARITY_BOOST: the chance values
## for unique, set and rare are divided by it, so those qualities come up
## more often than in D2 while item stats stay exactly D2's.

var ASSETS: String = Paths.root()

# A fast looter, not a D2 ladder grind: the chance of each quality is
# multiplied over D2's own ItemRatio result. (D2's own numbers are 1.)
const QUALITY_BOOST := {"unique": 20.0, "set": 15.0, "rare": 5.0}
# magic find diminishes for the better qualities (D2's 250/500/600 rule)
const MF_DIMINISH := {"unique": 250.0, "set": 500.0, "rare": 600.0}
const QUALITY_RANK := {"": 0, "normal": 0, "magic": 1, "rare": 2, "set": 3, "unique": 4}
# item types D2 treats as class-specific for the ItemRatio row choice
const CLASS_TYPES := ["abow", "aspe", "ajav", "orb", "head", "phlm", "pelt",
		"ashd", "h2h", "h2h2"]

var uniques: Array = []
var setitems: Array = []
var affixes := {}
var rarenames := {}
var itemtypes := {}
var itemratio: Array = []
var _loaded := false
var _equip_pool: Array = []

@onready var db := get_node("/root/ItemDB")

const COLOR_UNIQUE := Color(0.78, 0.62, 0.29)
const COLOR_SET := Color(0.10, 0.85, 0.10)
const COLOR_RARE := Color(1.0, 1.0, 0.45)
const COLOR_MAGIC := Color(0.41, 0.41, 1.0)


func _load_json(rel: String, fallback):
	var f := FileAccess.open(ProjectSettings.globalize_path(
		ASSETS.path_join(rel)), FileAccess.READ)
	if f == null:
		return fallback
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d != null else fallback


func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	uniques = _load_json("items/uniques.json", [])
	setitems = _load_json("items/setitems.json", [])
	affixes = _load_json("items/affixes.json", {})
	rarenames = _load_json("items/rarenames.json", {})
	itemtypes = _load_json("items/itemtypes.json", {})
	itemratio = _load_json("items/itemratio.json", [])
	# keep only uniques/sets whose base item exists; the quest uniques
	# (Horadric Staff, Khalim's pieces, the Hell Forge Hammer, the Viper
	# amulet, Staff of Kings) and the unfinished Darkfear have no level and
	# never drop
	uniques = uniques.filter(func(u): return u.get("enabled", true) \
			and db.items.has(str(u.get("code", ""))) \
			and str(u.get("lvl", "")).to_int() > 0)
	setitems = setitems.filter(func(s): return db.items.has(str(s.get("code", ""))))
	print("ItemGen: %d uniques, %d set items, %d/%d affixes, %d ratio rows" % [
		uniques.size(), setitems.size(),
		affixes.get("prefixes", []).size(), affixes.get("suffixes", []).size(),
		itemratio.size()])


func type_chain(code: String) -> Dictionary:
	## All type codes an item belongs to, walking the Equiv hierarchy.
	## Loads on demand: equipping and the paperdoll reach this without ever
	## having rolled an item, and an empty itemtypes silently collapses every
	## chain to its own code — which makes weapons unequippable.
	_ensure_loaded()
	var out := {}
	var stack := [code]
	while not stack.is_empty():
		var c: String = stack.pop_back()
		if c == "" or out.has(c):
			continue
		out[c] = true
		var t: Dictionary = itemtypes.get(c, {})
		stack.append(str(t.get("equiv1", "")))
		stack.append(str(t.get("equiv2", "")))
	return out


func _equippable(chain: Dictionary) -> bool:
	return chain.has("weap") or chain.has("armo") or chain.has("ring") \
			or chain.has("amul")


# ---------------------------------------------------------------------------
# Entry points
# ---------------------------------------------------------------------------
func roll_item(code: String, ilvl: int, bonus := {}, min_quality := "") -> Dictionary:
	## A dropped base -> instance, or {} when it stays a plain (normal) item.
	## ilvl: the monster level (D2's item level for drops). bonus: the
	## treasure class's per-quality magic-find bonus. min_quality: the floor
	## D2 gives champion and unique monsters' drops.
	_ensure_loaded()
	var it: Dictionary = db.item(code)
	if it.is_empty():
		return {}
	var chain := type_chain(str(it.get("type", "")))
	if not _equippable(chain):
		return {}
	var qlvl := str(it.get("level", "1")).to_int()
	var quality := _roll_quality(qlvl, ilvl, chain, bonus)
	if int(QUALITY_RANK.get(min_quality, 0)) > int(QUALITY_RANK.get(quality, 0)):
		quality = min_quality
	match quality:
		"unique":
			var u := _make_unique(code, ilvl)
			return u if not u.is_empty() else _make_rare(code, ilvl, chain)
		"set":
			var s := _make_set(code, ilvl)
			return s if not s.is_empty() else _make_magic(code, ilvl, chain)
		"rare":
			return _make_rare(code, ilvl, chain)
		"magic":
			return _make_magic(code, ilvl, chain)
	return {}


func maybe_magic(code: String, ilvl: int) -> Dictionary:
	## Starter kit and plain treasure-class bases: the same roll, no floor.
	return roll_item(code, ilvl)


func _equip_base(ilvl: int) -> String:
	## A random equippable base the level allows ("" when none).
	_ensure_loaded()
	if _equip_pool.is_empty():
		for c in db.items:
			var it: Dictionary = db.items[c]
			if str(it.get("invfile", "")) == "" and str(it.get("flippyfile", "")) == "":
				continue
			if _equippable(type_chain(str(it.get("type", "")))):
				_equip_pool.append(c)
	var pool := _equip_pool.filter(func(c):
		return str(db.item(str(c)).get("level", "1")).to_int() <= ilvl)
	if pool.is_empty():
		pool = _equip_pool
	if pool.is_empty():
		return ""
	return str(pool[randi() % pool.size()])


func roll_drop(ilvl: int) -> Dictionary:
	## A guaranteed magic-or-better piece of gear the level allows (test
	## fixtures and the odd scripted reward).
	var code := _equip_base(ilvl)
	return roll_item(code, ilvl, {}, "magic") if code != "" else {}


func roll_rare(ilvl: int) -> Dictionary:
	## A guaranteed rare on a base the level allows.
	var code := _equip_base(ilvl)
	return roll_item(code, ilvl, {}, "rare") if code != "" else {}


# A guaranteed set or unique is drawn from those within this many levels
# below the monster, so a level-40 boss hands out level-30s gear rather
# than Act 1 leftovers; the whole list is the fallback.
const SPECIAL_WINDOW := 12


var _special_pools := {}   # ilvl -> the candidates roll_special draws from


func roll_special(ilvl: int) -> Dictionary:
	## A guaranteed set item or unique the level allows: one entry drawn
	## uniformly from both lists, so the mix follows how many of each exist.
	_ensure_loaded()
	if not _special_pools.has(ilvl):
		var cands := []
		for u in uniques:
			cands.append([u, "unique"])
		for st in setitems:
			cands.append([st, "set"])
		var ok := cands.filter(func(c):
			return str(c[0].get("lvl", "1")).to_int() <= ilvl)
		var near := ok.filter(func(c):
			return str(c[0].get("lvl", "1")).to_int() > ilvl - SPECIAL_WINDOW)
		_special_pools[ilvl] = near if not near.is_empty() else ok
	var allowed: Array = _special_pools[ilvl]
	if allowed.is_empty():
		return roll_rare(ilvl)
	var pick: Array = allowed[randi() % allowed.size()]
	var code := str(pick[0].get("code", ""))
	var inst := _make_unique(code, ilvl) if pick[1] == "unique" else _make_set(code, ilvl)
	return inst if not inst.is_empty() else roll_rare(ilvl)


# ---------------------------------------------------------------------------
# Quality: D2's ItemRatio.txt formula
#   chance = (Ratio - (ilvl - qlvl) / Divisor) * 128, floored at Min,
#   then * 100 / (100 + MF) with MF diminished per quality, floored again;
#   the quality is rolled when rnd(chance) < 128.
# ---------------------------------------------------------------------------
func _ratio_row(chain: Dictionary) -> Dictionary:
	var cls := false
	for t in CLASS_TYPES:
		if chain.has(t):
			cls = true
			break
	var best := {}
	for r in itemratio:
		if str(r.get("Uber", "0")) != "0":
			continue
		if (str(r.get("Class Specific", "0")) == "1") != cls:
			continue
		# expansion rows (Version 1) over classic ones
		if best.is_empty() or str(r.get("Version", "0")) == "1":
			best = r
	return best


func _roll_quality(qlvl: int, ilvl: int, chain: Dictionary, bonus: Dictionary) -> String:
	var row := _ratio_row(chain)
	if row.is_empty():
		return "normal"
	var gs := get_node("/root/GameState")
	var player_mf := float(gs.mods.get("mag%", 0))
	for q in [["unique", "Unique"], ["set", "Set"], ["rare", "Rare"], ["magic", "Magic"]]:
		var key: String = q[1]
		var ratio := str(row.get(key, "0")).to_int()
		var divisor := maxi(1, str(row.get(key + "Divisor", "1")).to_int())
		var floor_v := str(row.get(key + "Min", "0")).to_int()
		var chance := (ratio - (ilvl - qlvl) / divisor) * 128
		chance = maxi(chance, floor_v)
		var mf := player_mf + float(bonus.get(q[0], 0))
		if mf > 0.0 and MF_DIMINISH.has(q[0]):
			var d: float = MF_DIMINISH[q[0]]
			mf = mf * d / (mf + d)
		chance = int(chance * 100.0 / (100.0 + mf))
		chance = maxi(chance, floor_v)
		chance = int(chance / float(QUALITY_BOOST.get(q[0], 1.0)))
		if randi() % maxi(1, chance) < 128:
			return q[0]
	return "normal"


# ---------------------------------------------------------------------------
# Uniques and sets: the base's own candidates, rarity-weighted, qlvl <= ilvl
# ---------------------------------------------------------------------------
func _weighted(pool: Array) -> Dictionary:
	var total := 0
	for e in pool:
		total += maxi(1, str(e.get("rarity", "1")).to_int())
	var pick := randi() % maxi(1, total)
	for e in pool:
		pick -= maxi(1, str(e.get("rarity", "1")).to_int())
		if pick < 0:
			return e
	return pool[0] if not pool.is_empty() else {}


func _make_unique(code: String, ilvl: int) -> Dictionary:
	var pool := uniques.filter(func(u):
		return str(u.get("code", "")) == code and str(u.get("lvl", "1")).to_int() <= ilvl)
	if pool.is_empty():
		return {}
	var u := _weighted(pool)
	return _finish({"code": code, "quality": "unique",
			"name": str(u.get("name", code)),
			"base_name": str(db.item(code).get("name", code)),
			"props": _roll_vals(u.get("props", [])),
			"color": COLOR_UNIQUE.to_html(), "ilvl": ilvl},
			str(u.get("lvlreq", "1")).to_int())


func _make_set(code: String, ilvl: int) -> Dictionary:
	var pool := setitems.filter(func(s):
		return str(s.get("code", "")) == code and str(s.get("lvl", "1")).to_int() <= ilvl)
	if pool.is_empty():
		return {}
	var s := _weighted(pool)
	return _finish({"code": code, "quality": "set",
			"name": str(s.get("name", code)),
			"base_name": str(db.item(code).get("name", code)),
			"props": _roll_vals(s.get("props", [])),
			"color": COLOR_SET.to_html(), "ilvl": ilvl},
			str(s.get("lvlreq", "1")).to_int())


# ---------------------------------------------------------------------------
# Affixes: spawnable, level <= ilvl <= maxlevel, type allowed, not excluded,
# class-specific only for the Amazon, one per group, frequency-weighted
# ---------------------------------------------------------------------------
func _affix_ok(a: Dictionary, chain: Dictionary, ilvl: int, rare: bool,
		used_groups: Dictionary) -> bool:
	if rare and not a.get("rare", false):
		return false
	if str(a.get("frequency", "0")).to_int() <= 0:
		return false
	if str(a.get("lvl", "1")).to_int() > ilvl:
		return false
	var mx := str(a.get("maxlevel", ""))
	if mx != "" and mx.to_int() < ilvl:
		return false
	if str(a.get("classspecific", "")) == "1" and str(a.get("class", "")) != "ama":
		return false
	var grp := str(a.get("group", ""))
	if grp != "" and used_groups.has(grp):
		return false
	for e in a.get("etypes", []):
		if chain.has(str(e)):
			return false
	var ity: Array = a.get("itypes", [])
	if ity.is_empty():
		return true
	for i in ity:
		if chain.has(str(i)):
			return true
	return false


func _pick_affix(pool: Array, chain: Dictionary, ilvl: int, rare: bool,
		used_groups: Dictionary) -> Dictionary:
	var eligible := pool.filter(func(a): return _affix_ok(a, chain, ilvl, rare, used_groups))
	if eligible.is_empty():
		return {}
	var total := 0
	for a in eligible:
		total += str(a.get("frequency", "1")).to_int()
	var pick := randi() % maxi(1, total)
	for a in eligible:
		pick -= str(a.get("frequency", "1")).to_int()
		if pick < 0:
			var grp := str(a.get("group", ""))
			if grp != "":
				used_groups[grp] = true
			return a
	return eligible[0]


func _affix_entry(a: Dictionary) -> Dictionary:
	return {"affix": str(a.get("name", "")), "props": a.get("props", []),
			"lvl": str(a.get("lvl", "1")).to_int(),
			"levelreq": str(a.get("levelreq", "0")).to_int()}


func _make_magic(code: String, ilvl: int, chain: Dictionary) -> Dictionary:
	var groups := {}
	var pre := {}
	var suf := {}
	if randf() < 0.5:
		pre = _pick_affix(affixes.get("prefixes", []), chain, ilvl, false, groups)
	if pre.is_empty() or randf() < 0.5:
		suf = _pick_affix(affixes.get("suffixes", []), chain, ilvl, false, groups)
	if pre.is_empty() and suf.is_empty():
		return {}
	var base_name := str(db.item(code).get("name", code))
	var name := base_name
	var props := []
	var req := 0
	if not pre.is_empty():
		name = "%s %s" % [pre.get("name", ""), name]
		props.append(_affix_entry(pre))
		req = maxi(req, str(pre.get("levelreq", "0")).to_int())
	if not suf.is_empty():
		name = "%s %s" % [name, suf.get("name", "")]
		props.append(_affix_entry(suf))
		req = maxi(req, str(suf.get("levelreq", "0")).to_int())
	return _finish({"code": code, "quality": "magic", "name": name,
			"base_name": base_name, "props": _roll_vals(props),
			"color": COLOR_MAGIC.to_html(), "ilvl": ilvl}, req)


func _make_rare(code: String, ilvl: int, chain: Dictionary) -> Dictionary:
	# D2 rares: one to three prefixes and one to three suffixes, three at least
	var np := 1 + randi() % 3
	var ns := 1 + randi() % 3
	while np + ns < 3:
		if randf() < 0.5:
			np += 1
		else:
			ns += 1
	var groups := {}
	var props := []
	var req := 0
	for k in range(np):
		var a := _pick_affix(affixes.get("prefixes", []), chain, ilvl, true, groups)
		if a.is_empty():
			break
		props.append(_affix_entry(a))
		req = maxi(req, str(a.get("levelreq", "0")).to_int())
	for k in range(ns):
		var a := _pick_affix(affixes.get("suffixes", []), chain, ilvl, true, groups)
		if a.is_empty():
			break
		props.append(_affix_entry(a))
		req = maxi(req, str(a.get("levelreq", "0")).to_int())
	if props.is_empty():
		return _make_magic(code, ilvl, chain)
	var pn: Array = rarenames.get("prefixes", ["Storm"])
	var sn: Array = rarenames.get("suffixes", ["Brand"])
	var name := "%s %s" % [pn[randi() % pn.size()], sn[randi() % sn.size()]]
	return _finish({"code": code, "quality": "rare", "name": name,
			"base_name": str(db.item(code).get("name", code)),
			"props": _roll_vals(props), "color": COLOR_RARE.to_html(), "ilvl": ilvl},
			req)


# ---------------------------------------------------------------------------
# Shared
# ---------------------------------------------------------------------------
func _roll_vals(plist: Array) -> Array:
	## Roll concrete values from each prop's min-max range (D2 rolls at drop).
	var out := []
	for p in plist:
		if p.has("affix"):
			var e: Dictionary = p.duplicate()
			e["props"] = _roll_vals(p.get("props", []))
			out.append(e)
			continue
		var q: Dictionary = p.duplicate()
		var mn := int(str(q.get("min", "0")).to_int())
		var mx := int(str(q.get("max", "0")).to_int())
		if mx < mn:
			mx = mn
		if GameState.RANGE_PROPS.has(str(q.get("code", ""))):
			# "Adds X-Y damage": min and max are the two ends, both kept
			q["val"] = mn
			q["val_max"] = mx
		else:
			q["val"] = randi_range(mn, mx) if mx > mn else mn
		out.append(q)
	return out


func _finish(inst: Dictionary, reqlvl: int) -> Dictionary:
	## Shared finalization: rolled base defense + required level.
	var it: Dictionary = db.item(str(inst.get("code", "")))
	var mnac := str(it.get("minac", "")).to_int()
	var mxac := str(it.get("maxac", "")).to_int()
	if mxac > 0:
		inst["base_ac"] = randi_range(mnac, maxi(mnac, mxac))
	inst["reqlvl"] = maxi(reqlvl, str(it.get("levelreq", "")).to_int())
	return inst


static func prop_lines(inst: Dictionary) -> Array:
	var lines := []
	for p in inst.get("props", []):
		if p.has("affix"):
			var parts := []
			for q in p.get("props", []):
				parts.append(_one_prop(q))
			lines.append("%s (%s)" % [p["affix"], ", ".join(parts)])
		else:
			lines.append(_one_prop(p))
	return lines


static func _one_prop(p: Dictionary) -> String:
	var c := str(p.get("code", ""))
	var mn := str(p.get("min", ""))
	var mx := str(p.get("max", ""))
	var pa := str(p.get("param", ""))
	var s := c
	if mn != "" or mx != "":
		s += " %s-%s" % [mn, mx]
	if pa != "":
		s += " [%s]" % pa
	return s
