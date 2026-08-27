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
func prop_line(code: String, val: int, param := "") -> String:
	_ensure()
	# property-level specials that bypass ItemStatCost
	match code:
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
	var gd: Dictionary = get_node("/root/SpriteDB").gamedata()
	return str(gd.get("skill_names", {}).get(str(param), "a spell"))


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
		var line := prop_line(code, val, str(p.get("param", "")))
		if line != "" and not seen.has(line):
			seen[line] = true
			out.append(line)
	return out
