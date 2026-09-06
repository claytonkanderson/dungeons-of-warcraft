extends Node
## Autoloaded as ItemDB: item definitions, D2 treasure classes (which class a
## monster of a given level and kind drops from, and the roll through it),
## cached flippy/inventory textures.

var ASSETS: String = Paths.root()

# D2 shrinks a class's NoDrop as more players are in the game. Drops here
# are rolled as if this many were present: dungeons are a fraction of a D2
# act's monster count, so single-player NoDrop would leave floors bare.
const DROP_PLAYERS := 3
# Potions come up far more often in D2's classes than a first-person run
# wants to pick up; only one in this many potion drops actually lands.
const POTION_KEEP_ONE_IN := 3
# Bosses are the payoff of a fast looter: the class is rolled again until at
# least this much gear has come out (bounded), so a dungeon boss is a pile
# and the final boss a heap, whichever act class they happen to use.
const MIN_GEAR := {"boss": 3, "final": 8}
const MAX_BOSS_ROLLS := 6
# Overall drop volume: each thing that would have dropped is kept with this
# probability, after every roll, so the quality mix is untouched.
const DROP_KEEP := 0.8
# The design targets, as expected counts per kill on top of the class roll
# (which keeps supplying the potions, gold and magic gear): a boss leaves
# 2-3 sets or uniques and 2 rares, a final boss a little more, and any other
# kill turns up a set or unique about one time in ten. A fractional count
# is its whole part plus one more with the fraction's probability.
const REWARDS := {
	"boss": {"special": 2.5, "rare": 2.0},
	"final": {"special": 3.0, "rare": 2.0},
	"champion": {"special": 0.1},
	"normal": {"special": 0.1},
}
# Boss classes carry no gold row; a boss leaves one pile, scaled like the
# richest class leaf (gld,mul=1280).
const BOSS_GOLD_MUL := 5.0

var items := {}
var treasure := {}
var _inv_tex := {}


func _ready() -> void:
	items = _load_json("items/items.json")
	treasure = _load_json("items/treasure.json")


func _load_json(rel: String) -> Dictionary:
	var f := FileAccess.open(ProjectSettings.globalize_path(
		ASSETS.path_join(rel)), FileAccess.READ)
	if f == null:
		push_error("missing " + rel + " - run pipeline/d2/export_items.py")
		return {}
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	return d


func item(code: String) -> Dictionary:
	return items.get(code, {})


func inv_texture(code: String) -> Texture2D:
	var it := item(code)
	var file := str(it.get("invfile", ""))
	if file == "":
		file = "inv" + code
	file = file.to_lower()
	if _inv_tex.has(file):
		return _inv_tex[file]
	var img := Image.load_from_file(ProjectSettings.globalize_path(
		ASSETS.path_join("items/inv/%s.png" % file)))
	var tex: Texture2D = ImageTexture.create_from_image(img) if img != null else null
	_inv_tex[file] = tex
	return tex


# ---------------------------------------------------------------------------
# Which treasure class: D2 files its monsters' classes by act and by kind
# (melee / caster / missile / champion / unique / chest), in A/B/C tiers by
# level within the act. WoW creatures carry none of that, so the act comes
# from the monster level (normal-difficulty act level bands) and the tier
# from the classes' own level column.
# ---------------------------------------------------------------------------
const ACT_BOSS := {1: "Andariel", 2: "Duriel", 3: "Mephisto", 4: "Diablo", 5: "Baal"}


static func act_of(mlvl: int) -> int:
	if mlvl <= 12:
		return 1
	if mlvl <= 20:
		return 2
	if mlvl <= 26:
		return 3
	if mlvl <= 32:
		return 4
	return 5


func tc_for(mlvl: int, kind: String, archetype := "melee") -> String:
	## kind: normal | champion | boss | final | chest
	var act := act_of(mlvl)
	if kind == "final":
		var b: String = ACT_BOSS.get(act, "Andariel")
		if treasure.has(b):
			return b
	var family := "H2H"
	match kind:
		"boss": family = "Unique"
		"champion": family = "Champ"
		"chest": family = "Chest"
		_:
			if archetype == "caster":
				family = "Cast"
			elif archetype == "missile":
				family = "Miss"
	# highest tier whose level the monster has reached; B as the fallback
	var best := ""
	var best_lvl := -1
	for tier in ["A", "B", "C"]:
		var name := "Act %d %s %s" % [act, family, tier]
		var e: Dictionary = treasure.get(name, {})
		if e.is_empty():
			continue
		var lv := str(e.get("level", "0")).to_int()
		if lv <= mlvl and lv > best_lvl:
			best = name
			best_lvl = lv
	if best == "":
		for tier in ["B", "A", "C"]:
			var name := "Act %d %s %s" % [act, family, tier]
			if treasure.has(name):
				return name
	return best


func quality_bonus(tc: String, kind: String) -> Dictionary:
	## The class's per-quality magic-find bonus (act bosses carry ~1000).
	## Our bosses are D2 super uniques, whose class ("Act N Super B") is the
	## one that carries bonuses; the plain Unique class does not.
	var e: Dictionary = treasure.get(tc, {})
	var out := {}
	for q in ["unique", "set", "rare", "magic"]:
		out[q] = str(e.get(q, "")).to_int()
	if kind == "boss" and int(out.get("unique", 0)) == 0:
		var sup: Dictionary = treasure.get("Act %d Super B" % act_of(
				str(e.get("level", "5")).to_int()), {})
		for q in ["unique", "set", "rare", "magic"]:
			out[q] = str(sup.get(q, "")).to_int()
	return out


# ---------------------------------------------------------------------------
# The roll through a class: Picks entries (negative Picks = each row drops
# exactly Prob times), NoDrop shrunk for DROP_PLAYERS, gold scaled by level.
# -> Array of {"code": String, "gold": int (0 if item)}
# ---------------------------------------------------------------------------
func roll(tc: String, mlvl := 1, depth := 0) -> Array:
	var out: Array = []
	if depth > 8 or tc == "":
		return out
	var entry: Dictionary = treasure.get(tc, {})
	if entry.is_empty():
		entry = _auto_tc(tc)
	if entry.is_empty():
		# leaf: an item code, possibly "gld,mul=1280"
		var parts := tc.replace("\"", "").split(",")
		var code := parts[0]
		if code == "gld":
			var mult := 1.0
			for p in parts:
				if p.begins_with("mul="):
					mult = float(p.substr(4)) / 256.0
			out.append({"code": "gold",
					"gold": maxi(1, int(randi_range(1, 8 * mlvl + 8) * mult))})
		elif items.has(code):
			if _is_potion(code) and randi() % POTION_KEEP_ONE_IN != 0:
				return out
			out.append({"code": code, "gold": 0})
		return out
	var rows: Array = entry.get("items", [])
	var praw := str(entry.get("picks", "1"))
	var picks := int(praw) if praw != "" else 1
	if picks < 0:
		# each row drops exactly Prob times
		for r in rows:
			for k in range(int(r[1])):
				out.append_array(roll(str(r[0]), mlvl, depth + 1))
		return out
	var nodrop := 0
	var ndraw := str(entry.get("nodrop", ""))
	if ndraw != "":
		nodrop = int(ndraw)
	var sum := 0
	for r in rows:
		sum += int(r[1])
	if sum <= 0:
		return out
	if nodrop > 0 and DROP_PLAYERS > 1:
		# D2: the no-drop probability is raised to the power of the player
		# factor, then converted back into a weight against the item rows
		var p := float(nodrop) / float(nodrop + sum)
		var f := 1.0 + float(DROP_PLAYERS - 1) / 2.0
		var p2 := pow(p, f)
		nodrop = int(round(sum * p2 / maxf(0.001, 1.0 - p2)))
	var total := nodrop + sum
	for i in range(picks):
		var pick := randi() % total
		if pick < nodrop:
			continue
		pick -= nodrop
		for r in rows:
			pick -= int(r[1])
			if pick < 0:
				out.append_array(roll(str(r[0]), mlvl, depth + 1))
				break
	return out


func drops_for(mlvl: int, kind: String, archetype := "melee") -> Array:
	## Everything one kill leaves on the floor: the treasure class for this
	## level and kind rolled through (bosses repeatedly, see MIN_GEAR), each
	## base put through the quality roll with the class's magic-find bonus
	## and D2's magic floor for champions and bosses.
	## -> [{code, gold, inst}]; inst is {} for a plain item or gold
	var gen := get_node("/root/ItemGen")
	var tc := tc_for(mlvl, kind, archetype)
	var bonus := quality_bonus(tc, kind)
	var minq := "magic" if kind in ["boss", "final", "champion"] else ""
	var want := int(MIN_GEAR.get(kind, 0))
	var out: Array = []
	var gear := 0
	for attempt in range(MAX_BOSS_ROLLS):
		for res in roll(tc, mlvl):
			var d := {"code": str(res["code"]), "gold": int(res["gold"]), "inst": {}}
			if d["gold"] == 0:
				d["inst"] = gen.roll_item(d["code"], mlvl, bonus, minq)
				if gen._equippable(gen.type_chain(str(item(d["code"]).get("type", "")))):
					gear += 1
			out.append(d)
		if gear >= want:
			break
	out = out.filter(func(_d): return randf() < DROP_KEEP)
	# the guaranteed rewards, never thinned
	var rw: Dictionary = REWARDS.get(kind, {})
	for i in range(_count(float(rw.get("special", 0.0)))):
		var inst: Dictionary = gen.roll_special(mlvl)
		if not inst.is_empty():
			out.append({"code": str(inst["code"]), "gold": 0, "inst": inst})
	for i in range(_count(float(rw.get("rare", 0.0)))):
		var inst: Dictionary = gen.roll_rare(mlvl)
		if not inst.is_empty():
			out.append({"code": str(inst["code"]), "gold": 0, "inst": inst})
	if kind in ["boss", "final"] and not out.any(func(d): return int(d["gold"]) > 0):
		out.append({"code": "gold", "inst": {},
				"gold": maxi(1, int(randi_range(1, 8 * mlvl + 8) * BOSS_GOLD_MUL))})
	# one pile of gold at most: every gold row the classes rolled is summed
	# into it, so the floor is not littered with coins
	var total_gold := 0
	for d in out:
		total_gold += int(d["gold"])
	if total_gold > 0:
		out = out.filter(func(d): return int(d["gold"]) == 0)
		out.append({"code": "gold", "gold": total_gold, "inst": {}})
	return out


static func _count(expected: float) -> int:
	## An integer draw whose mean is `expected`.
	var whole := int(floor(expected))
	return whole + (1 if randf() < expected - whole else 0)


func _is_potion(code: String) -> bool:
	## healing, mana, rejuvenation, and the antidote/thawing/stamina flasks
	var chain: Dictionary = get_node("/root/ItemGen").type_chain(
			str(item(code).get("type", "")))
	return chain.has("poti") or chain.has("hpot") or chain.has("mpot") 			or chain.has("rpot") or chain.has("spot") or chain.has("apot") 			or chain.has("tpot")


# ---------------------------------------------------------------------------
# The classes D2 builds at run time rather than listing: weapN / armoN /
# meleN / bowN / mageN hold every base of that kind whose level is in the
# three-level bucket ending at N, weighted by the base's rarity column.
# ---------------------------------------------------------------------------
var _auto_cache := {}
const AUTO_KINDS := ["weap", "armo", "mele", "bow", "mage"]


func _auto_tc(name: String) -> Dictionary:
	if _auto_cache.has(name):
		return _auto_cache[name]
	var out := {}
	var re := RegEx.create_from_string("^(weap|armo|mele|bow|mage)([0-9]+)$")
	var m := re.search(name)
	if m != null:
		var kind := m.get_string(1)
		var top := m.get_string(2).to_int()
		var gen := get_node("/root/ItemGen")
		var rows := []
		for code in items:
			var it: Dictionary = items[code]
			var lvl := str(it.get("level", "")).to_int()
			var rarity := str(it.get("rarity", "")).to_int()
			if rarity <= 0 or lvl > top or lvl <= top - 3:
				continue
			var chain: Dictionary = gen.type_chain(str(it.get("type", "")))
			var ok := false
			match kind:
				"weap": ok = chain.has("weap")
				"armo": ok = chain.has("armo")
				"mele": ok = chain.has("weap") and not chain.has("miss") 						and not chain.has("thro") and not chain.has("mage")
				"bow": ok = chain.has("miss")
				"mage": ok = chain.has("mage") or chain.has("staf") 						or chain.has("wand") or chain.has("orb")
			if ok:
				rows.append([code, str(rarity)])
		if not rows.is_empty():
			out = {"picks": "1", "nodrop": "", "items": rows}
	_auto_cache[name] = out
	return out
