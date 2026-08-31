class_name Cli
extends RefCounted
## The options the game accepts after a bare `--`, in one table.
##
## Every parse site used to match its own prefixes and ignore everything else,
## so a mistyped option was indistinguishable from a working one — which is
## how a half-applied --dungeon= went unnoticed. Anything starting with `--`
## that is not listed here is now reported.

const FLAGS := {
	"--fresh": "ignore the save; start from the starter kit",
	"--combat-test": "run the scripted bow fight, then quit",
	"--ui-test": "capture the UI panels, then quit",
	"--fps-probe": "report frame timing, then quit",
	"--walk-test": "pace the Deadmines cove and report footing",
	"--dungeon=": "<id>       load this dungeon instead of the saved one",
	"--shots=": "<dir>        screenshot the spawn from four angles, then quit",
	"--at=": "<x,y,z>         override the spawn position",
	"--menu-shot=": "<file>   capture the main menu, then quit",
}

static var _warned := false


static func known(arg: String) -> bool:
	if FLAGS.has(arg):
		return true
	for k in FLAGS:
		var key := str(k)
		if key.ends_with("=") and arg.begins_with(key):
			return true
	return false


static func warn_unknown() -> void:
	## Called once per run, from whichever scene starts first.
	if _warned:
		return
	_warned = true
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if not s.begins_with("--") or known(s):
			continue
		printerr("unknown option '%s' — ignored." % s)
		for k in FLAGS:
			printerr("    %-14s %s" % [str(k), str(FLAGS[k])])


static func has(flag: String) -> bool:
	return OS.get_cmdline_user_args().has(flag)


static func value(prefix: String, fallback := "") -> String:
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with(prefix):
			return s.substr(prefix.length())
	return fallback


static func vec3(prefix: String, fallback: Vector3) -> Vector3:
	## `--at=x,y,z`. A short or non-numeric value is reported and ignored,
	## rather than reading off the end of the array or quietly parsing to the
	## world origin and teleporting the player under the map.
	var v := value(prefix)
	if v == "":
		return fallback
	var parts := v.split(",")
	if parts.size() != 3:
		printerr("%s%s needs three comma-separated numbers — ignored." % [prefix, v])
		return fallback
	for c in parts:
		if not str(c).strip_edges().is_valid_float():
			printerr("%s%s is not numeric — ignored." % [prefix, v])
			return fallback
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
