extends Node
## Autoloaded as ItemText: exact D2 property display strings, built from
## Properties.txt stat mappings + ItemStatCost descfuncs (pre-resolved).

var ASSETS: String = Paths.root()

var props := {}       # property code -> [{stat, func}]
var statdesc := {}    # stat -> {pri, func, val, pos, neg, str2}
var _loaded := false


func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	for pair in [["items/props_display.json", "props"],
			["items/statdesc.json", "statdesc"]]:
		var f := FileAccess.open(ProjectSettings.globalize_path(
			ASSETS.path_join(pair[0])), FileAccess.READ)
		if f != null:
			set(pair[1], JSON.parse_string(f.get_as_text()))
			f.close()


## One display line for a rolled property {code, val, param...}; "" = hidden.
const TAB_NAMES := ["Bow and Crossbow", "Passive and Magic", "Javelin and Spear",
	"Fire", "Lightning", "Cold", "Curses", "Poison and Bone", "Necromancer Summoning",
	"Paladin Combat", "Offensive Aura", "Defensive Aura", "Barbarian Combat",
	"Masteries", "Warcries", "Druid Summoning", "Shape Shifting", "Elemental",
	"Traps", "Shadow Disciplines", "Martial Arts"]
const CLASS_NAMES := {"ama": "Amazon", "sor": "Sorceress", "nec": "Necromancer",
	"pal": "Paladin", "bar": "Barbarian", "dru": "Druid", "ass": "Assassin"}


func prop_line(code: String, val: int, param := "", val_max := -1) -> String:
	_ensure()
	if code == "Light":
		code = "light"     # a mis-cased code in the unique tables
	if val_max < 0:
		val_max = val
	# "+N (Based on Character Level)": the table's param is N*8 per level
	if GameState.PER_LEVEL.has(code):
		val = int(float(param.to_int()) / 8.0 * float(get_node("/root/GameState").level))
	# property-level specials that bypass ItemStatCost
	match code:
		"dmg-fire": return "Adds %d-%d Fire Damage" % [val, val_max]
		"dmg-cold": return "Adds %d-%d Cold Damage" % [val, val_max]
		"dmg-ltng": return "Adds %d-%d Lightning Damage" % [val, val_max]
		"dmg-mag": return "Adds %d-%d Magic Damage" % [val, val_max]
		"dmg-elem": return "Adds %d-%d Fire, Lightning and Cold Damage" % [val, val_max]
		"dmg-pois":
			var frames := maxi(1, param.to_int())
			return "+%d Poison Damage Over %d Seconds" % [
					int(round(val_max * frames / 256.0)), int(round(frames / 25.0))]
		"skill", "oskill":
			return "+%d to %s" % [val, _skill_name(param)]
		"skilltab":
			var t := param.to_int()
			var tn: String = TAB_NAMES[t] if t >= 0 and t < TAB_NAMES.size() else "Skill"
			return "+%d to %s Skills" % [val, tn]
		"ama", "sor", "nec", "pal", "bar", "dru", "ass":
			return "+%d to %s Skill Levels" % [val, CLASS_NAMES[code]]
		"ease": return "Requirements %d%%" % val
		"magicarrow": return "Fires Magic Arrows [Level %d]" % val
		"explosivearrow": return "Fires Explosive Arrows or Bolts [Level %d]" % val
		"dmg-min": return "+%d to Minimum Damage" % val
		"dmg-max": return "+%d to Maximum Damage" % val
		"dmg%": return "+%d%% Enhanced Damage" % val
		"dmg-norm": return "Damage +%d" % val
		"res-all": return "All Resistances +%d" % val
		"all-stats": return "+%d to All Attributes" % val
		"indestruct": return "Indestructible"
		"ethereal": return "Ethereal (Cannot Be Repaired)"
		"sock": return "Socketed (%d)" % val
	var plist: Array = props.get(code, [])
	if plist.is_empty():
		return "%s %+d" % [code, val]
	var lines := []
	for p in plist:
		var sd: Dictionary = statdesc.get(str(p.get("stat", "")), {})
		if sd.is_empty():
			continue
		var line := _format_stat(sd, val, param)
		if line != "" and not lines.has(line):
			lines.append(line)
	if lines.is_empty():
		return "%s %+d" % [code, val]
	return lines[0]      # grouped stats (res-all etc.) collapse to one line


func _skill_name(param: String) -> String:
	## skill properties name their skill by id or by name in the tables
	var gd: Dictionary = get_node("/root/SpriteDB").gamedata()
	var names: Dictionary = gd.get("skill_names", {})
	if names.has(str(param)):
		return str(names[str(param)])
	return param if param != "" else "a spell"


func stat_priority(code: String) -> int:
	_ensure()
	var plist: Array = props.get(code, [])
	if plist.is_empty():
		return 0
	var sd: Dictionary = statdesc.get(str(plist[0].get("stat", "")), {})
	return int(str(sd.get("pri", "0")).to_int())


func _format_stat(sd: Dictionary, val: int, _param: String) -> String:
	var fn := int(str(sd.get("func", "1")).to_int())
	var dval := int(str(sd.get("val", "1")).to_int())
	var s := str(sd.get("pos", "") if val >= 0 else sd.get("neg", ""))
	var s2 := str(sd.get("str2", ""))
	# printf-style templates (chance-to-cast, charges): fill sequentially
	if s.contains("%d") or s.contains("%s"):
		var had_pct := s.contains("%d%%")
		var filled := s.replace("%d%%", str(val) + "%")
		filled = filled.replace("%d", str(maxi(1, int(str(_param).to_int()))) if had_pct else str(val))
		filled = filled.replace("%s", _skill_name(_param))
		return filled.strip_edges()
	var body := ""
	match fn:
		1: body = "+%d %s" % [val, s]
		2: body = "%d%% %s" % [val, s]
		3: body = "%d %s" % [val, s]
		4: body = "+%d%% %s" % [val, s]
		5: body = "%d%% %s" % [val * 100 / 128, s]
		6: body = "+%d %s %s" % [val, s, s2]
		7: body = "%d%% %s %s" % [val, s, s2]
		8: body = "+%d%% %s %s" % [val, s, s2]
		9: body = "%d %s %s" % [val, s, s2]
		11: body = "Repairs 1 durability in %d seconds" % maxi(1, 100 / maxi(1, val))
		12: body = "+%d %s" % [val, s]
		19:
			if s.contains("%d"):
				body = s % val
			else:
				body = "%s %d" % [s, val]
		20: body = "%d%% %s" % [-val, s]
		21: body = "%d %s" % [-val, s]
		_:
			body = "+%d %s" % [val, s]
	if dval == 0:
		body = s
	elif dval == 2:
		# value trails the string: "Fire Resist +24%"
		match fn:
			2, 5, 7: body = "%s %d%%" % [s, val]
			4, 8: body = "%s +%d%%" % [s, val]
			_: body = "%s +%d" % [s, val]
	return body.strip_edges()


## All display lines for an instance, D2-sorted (priority desc).
func lines_for(inst: Dictionary) -> Array:
	var out := []
	for pair in lines_with_codes(inst):
		out.append(pair[0])
	return out


## [line, property code] pairs, so a caller can tell which lines the game
## actually applies (GameState.MOD_MAP) and which are display only so far.
func lines_with_codes(inst: Dictionary) -> Array:
	_ensure()
	var flat := []
	for p in inst.get("props", []):
		if p.has("affix"):
			for q in p.get("props", []):
				flat.append(q)
		else:
			flat.append(p)
	var out := []
	var seen := {}
	flat.sort_custom(func(a, b):
		return stat_priority(str(a.get("code", ""))) > stat_priority(str(b.get("code", ""))))
	for p in flat:
		var code := str(p.get("code", ""))
		if code == "":
			continue
		var val := int(p.get("val", int(str(p.get("min", "0")).to_int())))
		var line := prop_line(code, val, str(p.get("param", "")), int(p.get("val_max", -1)))
		if line != "" and not seen.has(line):
			seen[line] = true
			out.append([line, code])
	return out
