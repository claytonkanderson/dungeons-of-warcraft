extends Node
## Autoloaded as ItemGen: rolls unique / set / rare item instances.
## An instance: {code, quality, name, base_name, props: Array, color: Color}

var ASSETS: String = Paths.root()
# Drops are gated by REQUIRED level vs the player's CURRENT level: nothing
# rolls that the amazon cannot wear right now. The pool widens as she levels.

var uniques: Array = []
var setitems: Array = []
var affixes := {}
var rarenames := {}
var itemtypes := {}
var _loaded := false

@onready var db := get_node("/root/ItemDB")

const COLOR_UNIQUE := Color(0.78, 0.62, 0.29)
const COLOR_SET := Color(0.10, 0.85, 0.10)
const COLOR_RARE := Color(1.0, 1.0, 0.45)
const COLOR_MAGIC := Color(0.41, 0.41, 1.0)


## 45% chance to upgrade an equippable treasure-class drop to magic (blue).
func maybe_magic(code: String, mlvl: int) -> Dictionary:
	_ensure_loaded()
	var it: Dictionary = db.item(code)
	var chain := type_chain(str(it.get("type", "")))
	if not (chain.has("weap") or chain.has("armo") or chain.has("ring")
			or chain.has("amul")):
		return {}
	if randf() > 0.45:
		return {}
	var pre := {}
	var suf := {}
	if randf() < 0.6:
		pre = _pick_one_affix(affixes.get("prefixes", []), chain, _plvl())
	if pre.is_empty() or randf() < 0.6:
		suf = _pick_one_affix(affixes.get("suffixes", []), chain, _plvl())
	if pre.is_empty() and suf.is_empty():
		return {}
	var base_name := str(it.get("name", code))
	var name := base_name
	var props := []
	var maxlvl := 1
	if not pre.is_empty():
		name = "%s %s" % [pre.get("name", ""), name]
		props.append({"affix": pre.get("name", ""), "props": pre.get("props", []),
				"lvl": int(str(pre.get("lvl", "1")).to_int())})
		maxlvl = maxi(maxlvl, int(str(pre.get("lvl", "1")).to_int()))
	if not suf.is_empty():
		name = "%s %s" % [name, suf.get("name", "")]
		props.append({"affix": suf.get("name", ""), "props": suf.get("props", []),
				"lvl": int(str(suf.get("lvl", "1")).to_int())})
		maxlvl = maxi(maxlvl, int(str(suf.get("lvl", "1")).to_int()))
	return _finish({"code": code, "quality": "magic", "name": name,
			"base_name": base_name, "props": _roll_vals(props),
			"color": COLOR_MAGIC.to_html()}, maxlvl)


func _pick_one_affix(pool: Array, chain: Dictionary, max_lvl := 99) -> Dictionary:
	var eligible := pool.filter(func(a):
		if int(str(a.get("lvl", "1")).to_int()) > max_lvl:
			return false
		var ity: Array = a.get("itypes", [])
		var ety: Array = a.get("etypes", [])
		for e in ety:
			if chain.has(str(e)):
				return false
		if ity.is_empty():
			return true
		for i in ity:
			if chain.has(str(i)):
				return true
		return false)
	if eligible.is_empty():
		return {}
	return eligible[randi() % eligible.size()]


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
	# keep only uniques/sets whose base item exists
	uniques = uniques.filter(func(u): return u.get("enabled", true) \
			and db.items.has(str(u.get("code", ""))))
	setitems = setitems.filter(func(s): return db.items.has(str(s.get("code", ""))))
	print("ItemGen: %d uniques, %d set items, %d/%d affixes" % [
		uniques.size(), setitems.size(),
		affixes.get("prefixes", []).size(), affixes.get("suffixes", []).size()])


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


func roll_drop(mlvl: int) -> Dictionary:
	## Quality skewed generous: every roll is rare-or-better, with a heavy
	## unique/set share. Item data itself stays true to the D2 tables.
	_ensure_loaded()
	var r := randf()
	if r < 0.25 and not uniques.is_empty():
		return _roll_unique(mlvl)
	elif r < 0.45 and not setitems.is_empty():
		return _roll_set(mlvl)
	return _roll_rare(mlvl)


func _roll_vals(plist: Array) -> Array:
	## Roll concrete values from each prop's min-max range (D2 rolls at drop).
	var out := []
	for p in plist:
		if p.has("affix"):
			out.append({"affix": p["affix"], "props": _roll_vals(p.get("props", []))})
			continue
		var q: Dictionary = p.duplicate()
		var mn := int(str(q.get("min", "0")).to_int())
		var mx := int(str(q.get("max", "0")).to_int())
		if mx < mn:
			mx = mn
		q["val"] = randi_range(mn, mx) if mx > mn else mn
		out.append(q)
	return out


func _plvl() -> int:
	return int(get_node("/root/GameState").level)


func _req_of(entry: Dictionary) -> int:
	## Effective required level of a unique/set row: its own lvlreq or its
	## base item's, whichever is higher (mirrors _finish()).
	var base_req := str(db.item(str(entry.get("code", ""))) \
			.get("levelreq", "")).to_int()
	return maxi(str(entry.get("lvlreq", "1")).to_int(), base_req)


func _roll_unique(_mlvl: int) -> Dictionary:
	var plvl := _plvl()
	var pool := uniques.filter(func(u): return _req_of(u) <= plvl)
	if pool.is_empty():
		pool = uniques
	var u: Dictionary = pool[randi() % pool.size()]
	var code := str(u.get("code", ""))
	return _finish({"code": code, "quality": "unique",
			"name": str(u.get("name", code)),
			"base_name": str(db.item(code).get("name", code)),
			"props": _roll_vals(u.get("props", [])),
			"color": COLOR_UNIQUE.to_html()},
			str(u.get("lvlreq", "1")).to_int())


func _roll_set(_mlvl: int) -> Dictionary:
	var plvl := _plvl()
	var pool := setitems.filter(func(s): return _req_of(s) <= plvl)
	if pool.is_empty():
		pool = setitems
	var s: Dictionary = pool[randi() % pool.size()]
	var code := str(s.get("code", ""))
	return _finish({"code": code, "quality": "set",
			"name": str(s.get("name", code)),
			"base_name": str(db.item(code).get("name", code)),
			"props": _roll_vals(s.get("props", [])),
			"color": COLOR_SET.to_html()},
			str(s.get("lvlreq", "1")).to_int())


func _rare_base_pool() -> Array:
	var out := []
	for code in db.items:
		var it: Dictionary = db.items[code]
		var t := str(it.get("type", ""))
		if t == "" or str(it.get("invfile", "")) == "" and str(it.get("flippyfile", "")) == "":
			continue
		# equippable-ish: weapons, armor, rings/amulets
		var chain := type_chain(t)
		if chain.has("weap") or chain.has("armo") or chain.has("ring") \
				or chain.has("amul"):
			out.append(code)
	return out


var _rare_pool_cache: Array = []


func _roll_rare(mlvl: int) -> Dictionary:
	if _rare_pool_cache.is_empty():
		_rare_pool_cache = _rare_base_pool()
	if _rare_pool_cache.is_empty():
		# data missing: at least return a plain base item
		return {"code": "hax", "quality": "rare", "name": "Broken Axe",
				"base_name": "Hand Axe", "props": [], "color": COLOR_RARE.to_html()}
	var plvl := _plvl()
	var pool := _rare_pool_cache.filter(func(c):
		return str(db.item(str(c)).get("levelreq", "")).to_int() <= plvl)
	if pool.is_empty():
		pool = _rare_pool_cache
	var code: String = pool[randi() % pool.size()]
	var chain := type_chain(str(db.item(code).get("type", "")))
	var props := []
	var np := 1 + randi() % 3
	var ns := 1 + randi() % 3
	props.append_array(_pick_affixes(affixes.get("prefixes", []), chain, np, mlvl))
	props.append_array(_pick_affixes(affixes.get("suffixes", []), chain, ns, mlvl))
	var pn: Array = rarenames.get("prefixes", ["Storm"])
	var sn: Array = rarenames.get("suffixes", ["Brand"])
	var name := "%s %s" % [pn[randi() % pn.size()], sn[randi() % sn.size()]]
	# D2 rule: rare required level = 3/4 of the highest affix level
	var maxlvl := 0
	for a in props:
		maxlvl = maxi(maxlvl, int(a.get("lvl", 1)))
	return _finish({"code": code, "quality": "rare", "name": name,
			"base_name": str(db.item(code).get("name", code)),
			"props": _roll_vals(props), "color": COLOR_RARE.to_html()},
			maxlvl * 3 / 4)


func _pick_affixes(pool: Array, chain: Dictionary, count: int, _mlvl: int) -> Array:
	# rare required level is 3/4 of the highest affix level (see _roll_rare's
	# _finish call), so affixes up to plvl * 4/3 keep the item wearable now
	var max_affix: int = _plvl() * 4 / 3
	var eligible := pool.filter(func(a):
		if not a.get("rare", false):
			return false
		if int(str(a.get("lvl", "1")).to_int()) > max_affix:
			return false
		var ity: Array = a.get("itypes", [])
		var ety: Array = a.get("etypes", [])
		for e in ety:
			if chain.has(str(e)):
				return false
		if ity.is_empty():
			return true
		for i in ity:
			if chain.has(str(i)):
				return true
		return false)
	var out := []
	var used := {}
	for k in range(count):
		if eligible.is_empty():
			break
		for attempt in range(6):
			var a: Dictionary = eligible[randi() % eligible.size()]
			var nm := str(a.get("name", ""))
			if not used.has(nm):
				used[nm] = true
				out.append({"affix": nm, "props": a.get("props", []),
						"lvl": int(str(a.get("lvl", "1")).to_int())})
				break
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
