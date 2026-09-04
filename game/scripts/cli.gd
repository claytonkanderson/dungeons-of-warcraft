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
	"--stair-test": "climb the entrance stairs with/without the stepper, report",
	"--dungeon=": "<id>       load this dungeon instead of the saved one",
	"--shots=": "<dir>        screenshot the spawn from four angles, then quit",
	"--at=": "<x,y,z>         override the spawn position",
	"--menu-shot=": "<file>   capture the main menu, then quit",
	"--what-here": "diagnostic: list placements whose bounds enclose the spawn, quit",
	"--loot-test": "diagnostic: simulate drops per monster level and kind, quit",
	"--item-test": "diagnostic: equip known item properties, print what they do, quit",
	"--two-sided": "diagnostic: draw WMO faces from both sides",
	"--no-doodads": "diagnostic: skip the WMO doodad sets",
	"--no-props": "diagnostic: skip the ADT tile props",
	"--offscreen": "with --shots/--menu-shot: keep the window minimized and "
			+ "the mouse untouched (launch through capture.bat, which also "
			+ "creates the window unfocusable so nothing else loses focus)",
}

static var _warned := false


static func offscreen() -> bool:
	return has("--offscreen")


static func hide_window() -> void:
	## Offscreen capture. The window is minimized (and asked not to take
	## focus) so nothing appears over whatever else is on the desktop. A
	## minimized window is not driven by vsync, so capture sites draw frames
	## with RenderingServer.force_draw() instead of awaiting frame_post_draw.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)


static func toggle_fullscreen() -> void:
	## Borderless fullscreen <-> windowed. Borderless rather than exclusive:
	## instant alt-tab, no mode switch, and the desktop resolution is what
	## the canvas stretch scales to.
	var full := DisplayServer.window_get_mode() \
			in [DisplayServer.WINDOW_MODE_FULLSCREEN,
				DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full
			else DisplayServer.WINDOW_MODE_FULLSCREEN)


static func capture(viewport: Viewport, path: String) -> void:
	## One frame to disk. Offscreen: force a draw on a minimized window;
	## on screen: wait for two real frames so the scene has settled.
	if offscreen():
		RenderingServer.force_draw()
	else:
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(path)


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
