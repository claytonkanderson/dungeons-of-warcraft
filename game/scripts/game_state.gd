extends Node
## Autoloaded as GameState: player stats, XP/levels, D2 combat math.

signal leveled_up(level: int)
signal hp_changed
signal xp_changed

var character := ""           # active character slug ("" = legacy/test save)
var char_name := "Amazon"     # display name
var dungeons_done: Array = [] # completed dungeon ids (per character)
var current_dungeon := "deadmines"
var level := 14               # a seasoned start: points arrive unallocated
var xp := 0                   # seeded from the exp table in _ready
var skill_points := 14
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
	mana_max = 15.0 + 1.5 * (level - 1) + 1.5 * (float(stat.ene) - 15.0) \
			+ float(mods.get("mana", 0)) + float(mods.get("ene", 0)) * 1.5
	hp = minf(hp, hp_max)
	mana = minf(mana, mana_max)


signal equipment_changed

const SLOTS := ["head", "tors", "weap", "shie", "glov", "boot", "belt",
		"ring1", "ring2", "amul"]
var equipped := {}             # slot -> {code, inst}
var mods := {}                 # aggregated equipment modifiers
var stat_points := 70

# equipment property codes we aggregate
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
}


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
	return minf(75.0, float(mods.get(key, 0)) + float(mods.get("res-all", 0)))


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


func _apply_prop(p: Dictionary) -> void:
	var key = MOD_MAP.get(str(p.get("code", "")))
	if key == null:
		return
	mods[key] = int(mods.get(key, 0)) \
			+ int(p.get("val", str(p.get("min", "0")).to_int()))


func _aggregate_mods() -> void:
	mods = {}
	for slot in equipped:
		var inst: Dictionary = equipped[slot].get("inst", {})
		var flat := []
		for p in inst.get("props", []):
			if p.has("affix"):
				flat.append_array(p.get("props", []))
			else:
				flat.append(p)
		for p in flat:
			_apply_prop(p)
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
	return 0.0 if l <= 0 else minf(0.15 + 0.08 * l, 0.85)


func dodge_chance() -> float:      # vs melee
	var l := skill_level("Dodge")
	return 0.0 if l <= 0 else minf(0.10 + 0.06 * l, 0.56)


func avoid_chance() -> float:      # vs missiles
	var l := maxi(skill_level("Avoid"), skill_level("Evade"))
	return 0.0 if l <= 0 else minf(0.12 + 0.06 * l, 0.65)


func player_defense() -> float:
	return float(total_stat("dex")) * 0.25 \
			+ float(mods.get("ac", 0)) * (1.0 + float(mods.get("ac%", 0)) / 100.0)


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
	return {
		"lvl": maxi(int(inst.get("reqlvl", 0)), str(it.get("levelreq", "")).to_int()),
		"str": str(it.get("reqstr", "")).to_int(),
		"dex": str(it.get("reqdex", "")).to_int(),
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


const DMG_MULT := 5.0   # global player damage boost: ~2 hits per fallen


func weapon_damage() -> Vector2:
	# equipped weapon base damage (2-hand columns cover bows), else bare 2-6
	var mn := 2.0
	var mx := 6.0
	var w: Dictionary = equipped.get("weap", {})
	if not w.is_empty():
		var it: Dictionary = get_node("/root/ItemDB").item(str(w.get("code", "")))
		var bmn := str(it.get("2handmindam", "")).to_int()
		var bmx := str(it.get("2handmaxdam", "")).to_int()
		if bmx == 0:
			bmn = str(it.get("mindam", "")).to_int()
			bmx = str(it.get("maxdam", "")).to_int()
		if bmx > 0:
			mn = float(bmn)
			mx = float(bmx)
	var ed := float(mods.get("dmg%", 0)) + float(total_stat("dex"))
	mn = (mn * (1.0 + ed / 100.0) + float(mods.get("dmg-min", 0))) * DMG_MULT
	mx = (mx * (1.0 + ed / 100.0) + float(mods.get("dmg-max", 0))) * DMG_MULT
	return Vector2(mn, maxf(mn, mx))


static func chance_to_hit(ar: float, defense: float, alvl: int, dlvl: int) -> float:
	var c: float = 2.0 * (ar / maxf(1.0, ar + defense)) \
			* (float(alvl) / maxf(1.0, float(alvl + dlvl)))
	return clampf(c, 0.05, 0.95)


func award_xp(amount: int) -> void:
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


func take_damage(dmg: float) -> bool:
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
	# D2-style slow mana regeneration
	mana = minf(mana_max, mana + mana_max * dt / 30.0)
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
	return int(skills.get(n, 0))


func mana_cost(n: String) -> float:
	if n == "Attack":
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
	## Fresh-character defaults (the level-14 seasoned start).
	level = 14
	skill_points = 14
	stat_points = 70
	stat = {"str": 20, "dex": 25, "vit": 20, "ene": 15}
	skills = {}
	hotkeys = {}
	equipped = {}
	inv_items = []
	gold = 0
	belt = [{}, {}, {}, {}]
	stash_items = []
	dungeons_done = []
	current_dungeon = "deadmines"
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


func save_game(player) -> void:
	var d := {
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
