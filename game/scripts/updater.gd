extends Node
const VersionInfo := preload("res://scripts/version.gd")   # by path: a new class_name is not in the class cache until the editor scans
const AssetInfo := preload("res://scripts/asset_versions.gd")
## Autoloaded as Updater: the shipped game keeps itself and its assets
## current on its own.
##
## On launch, at the menu: the newest GitHub release is looked up; a newer
## one is downloaded beside the executable, its two programs unpacked, and
## a small batch file swaps them in once this process has exited and starts
## the game again. Then the assets are compared with the stage versions
## this build expects (asset_versions.gd against _build/assets/
## build_manifest.json); when any stage is older or missing, setup.exe is
## started to redo those stages and start the game after, and this process
## exits. Offline, or in a checkout, nothing happens. A line on the menu
## says what is going on; nothing asks.

signal status_changed

const REPO := "claytonkanderson/dungeons-of-warcraft"
const API := "https://api.github.com/repos/" + REPO + "/releases/latest"
const UPDATE_DIR := "_update"
const SHIPPED := ["DungeonsOfWarcraft.exe", "setup.exe"]

var status := ""
var busy := false                # a download is in flight: stay on the menu
var _checked := false
var _http: HTTPRequest
var _dl: HTTPRequest
var _failed_tag := ""            # an update whose swap failed last time; not retried


func _say(s: String) -> void:
	status = s
	status_changed.emit()
	if s != "":
		print("update: " + s)


func packaged() -> bool:
	## the shipped executable, not a checkout run from the editor or Godot
	return not OS.has_feature("editor") \
			and OS.get_executable_path().get_file().to_lower() == "dungeonsofwarcraft.exe"


func exe_dir() -> String:
	return OS.get_executable_path().get_base_dir()


func start() -> void:
	## Called by the menu once it is up. Idempotent.
	if _checked:
		return
	_checked = true
	var st := get_node("/root/Settings")
	if str(st.last_version) != "" and str(st.last_version) != VersionInfo.VERSION:
		_say("Updated to %s" % VersionInfo.VERSION)
	st.set_last_version(VersionInfo.VERSION)
	if not packaged() or Cli.has("--no-update"):
		return
	if _apply_pending():
		return
	_failed_tag = _read_failed()
	_say("Checking for updates ...")
	_http = HTTPRequest.new()
	_http.timeout = 8.0
	add_child(_http)
	_http.request_completed.connect(_on_latest)
	var err := _http.request(API, ["User-Agent: DungeonsOfWarcraft/" + VersionInfo.VERSION,
			"Accept: application/vnd.github+json"])
	if err != OK:
		_say("")
		_check_assets()


func _on_latest(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		# offline, rate-limited, or no release yet: play this version
		_say("")
		_check_assets()
		return
	var d: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (d is Dictionary):
		_say("")
		_check_assets()
		return
	var tag := str(d.get("tag_name", "")).trim_prefix("v")
	var url := ""
	for a in d.get("assets", []):
		if str(a.get("name", "")).ends_with(".zip"):
			url = str(a.get("browser_download_url", ""))
			break
	if tag != "" and url != "" and VersionInfo.newer(tag, VersionInfo.VERSION):
		if tag == _failed_tag:
			_say("Update %s could not be installed last time; playing %s" % [tag, VersionInfo.VERSION])
			_check_assets()
			return
		_download(url, tag)
	else:
		_say("")
		_check_assets()


func _download(url: String, tag: String) -> void:
	busy = true
	_say("Updating to %s: downloading ..." % tag)
	var dir := exe_dir().path_join(UPDATE_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	_dl = HTTPRequest.new()
	_dl.timeout = 900.0
	_dl.download_file = dir.path_join("latest.zip")
	add_child(_dl)
	_dl.request_completed.connect(_on_zip.bind(tag))
	var err := _dl.request(url, ["User-Agent: DungeonsOfWarcraft/" + VersionInfo.VERSION])
	if err != OK:
		busy = false
		_say("Update download could not start; playing %s" % VersionInfo.VERSION)
		_check_assets()


func _on_zip(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray,
		tag: String) -> void:
	busy = false
	var dir := exe_dir().path_join(UPDATE_DIR)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_say("Update download failed; playing %s" % VersionInfo.VERSION)
		_check_assets()
		return
	var z := ZIPReader.new()
	if z.open(dir.path_join("latest.zip")) != OK:
		_say("The update could not be read; playing %s" % VersionInfo.VERSION)
		_check_assets()
		return
	for f in SHIPPED:
		var data: PackedByteArray = z.read_file("DungeonsOfWarcraft/" + f)
		if data.is_empty():
			z.close()
			_say("The update is missing %s; playing %s" % [f, VersionInfo.VERSION])
			_check_assets()
			return
		var out := FileAccess.open(dir.path_join(f), FileAccess.WRITE)
		if out == null:
			z.close()
			_say("Could not write the update; playing %s" % VersionInfo.VERSION)
			_check_assets()
			return
		out.store_buffer(data)
		out.close()
	z.close()
	var ready := FileAccess.open(dir.path_join("ready.json"), FileAccess.WRITE)
	if ready != null:
		ready.store_string(JSON.stringify({"version": tag}))
		ready.close()
	_apply(tag)


func _read_failed() -> String:
	## the tag of an update whose files could not be swapped in last time:
	## it is not tried again (a fresh download would only fail the same
	## way); the next release clears it
	var p := exe_dir().path_join(UPDATE_DIR).path_join("failed.txt")
	if not FileAccess.file_exists(p):
		return ""
	var f := FileAccess.open(p, FileAccess.READ)
	return f.get_as_text().strip_edges() if f != null else ""


func _apply_pending() -> bool:
	## a download finished on an earlier launch that never got applied
	var dir := exe_dir().path_join(UPDATE_DIR)
	if not FileAccess.file_exists(dir.path_join("ready.json")):
		return false
	for f in SHIPPED:
		if not FileAccess.file_exists(dir.path_join(f)):
			return false
	var f := FileAccess.open(dir.path_join("ready.json"), FileAccess.READ)
	var d: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	var tag := str(d.get("version", "?")) if d is Dictionary else "?"
	_apply(tag)
	return true


func _apply(tag: String) -> void:
	## The executable cannot replace itself while it runs: a batch file
	## waits for this process to end, moves the new files over, starts the
	## game again. Then this process leaves.
	var scene := get_tree().current_scene
	if scene == null or scene.name != "MainMenu":
		_say("Update to %s ready: it installs on the next launch" % tag)
		return
	var dir := exe_dir().path_join(UPDATE_DIR)
	var pid := OS.get_process_id()
	# Each move is retried for a minute: a file something still holds (the
	# antivirus scanning the fresh download, a reader) cannot be replaced
	# that instant. ping is the sleep, since the script has no console for
	# timeout. Only a swap of both files clears the download; a failure
	# leaves failed.txt so the next launch plays instead of trying again.
	var u := UPDATE_DIR
	var lines := [
		"@echo off",
		"setlocal enabledelayedexpansion",
		"cd /d \"%~dp0..\"",
		":w",
		"tasklist /FI \"PID eq %d\" 2>nul | find \"%d\" >nul" % [pid, pid],
		"if not errorlevel 1 (ping -n 2 127.0.0.1 >nul & goto w)",
		"set n=0",
		":m",
		"move /y \"%s\\DungeonsOfWarcraft.exe\" \"DungeonsOfWarcraft.exe\" >nul 2>&1" % u,
		"if errorlevel 1 (set /a n+=1 & if !n! lss 60 (ping -n 2 127.0.0.1 >nul & goto m) else goto fail)",
		"set n=0",
		":s",
		"move /y \"%s\\setup.exe\" \"setup.exe\" >nul 2>&1" % u,
		"if errorlevel 1 (set /a n+=1 & if !n! lss 60 (ping -n 2 127.0.0.1 >nul & goto s) else goto fail)",
		"del \"%s\\ready.json\" \"%s\\latest.zip\" \"%s\\failed.txt\" 2>nul" % [u, u, u],
		"goto run",
		":fail",
		"echo %s> \"%s\\failed.txt\"" % [tag, u],
		"del \"%s\\ready.json\" 2>nul" % u,
		":run",
		"start \"\" \"DungeonsOfWarcraft.exe\"",
	]
	var cmd := dir.path_join("apply.cmd")
	var f := FileAccess.open(cmd, FileAccess.WRITE)
	if f == null:
		_say("Could not write the updater; playing %s" % VersionInfo.VERSION)
		_check_assets()
		return
	f.store_string("\r\n".join(lines) + "\r\n")
	f.close()
	_say("Updating to %s: restarting ..." % tag)
	var id := OS.create_process("cmd.exe", ["/c", ProjectSettings.globalize_path(cmd)])
	if id <= 0:
		_say("Could not start the updater; playing %s" % VersionInfo.VERSION)
		_check_assets()
		return
	get_tree().quit()


func stale_stages() -> Array:
	## the asset stages this build wants at another version than the
	## assets beside the executable carry (all of them, with no assets)
	var built := {}
	var f := FileAccess.open(Paths.root().path_join("build_manifest.json"), FileAccess.READ)
	if f != null:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			built = d.get("stages", {})
	var out := []
	for k in AssetInfo.STAGES:
		if int(built.get(k, 0)) != int(AssetInfo.STAGES[k]):
			out.append(k)
	return out


func _check_assets() -> void:
	var stale := stale_stages()
	if stale.is_empty():
		return
	if Cli.has("--after-rebuild"):
		# setup just ran and these are still behind: do not go round again
		_say("Some assets could not be rebuilt (%s); see _build/setup.log" % ", ".join(stale))
		return
	var setup := exe_dir().path_join("setup.exe")
	if not FileAccess.file_exists(setup):
		_say("The assets are out of date for this version: run setup.exe")
		return
	_say("Updating the assets (%d of %d stages) ..." % [stale.size(), AssetInfo.STAGES.size()])
	var id := OS.create_process(setup, ["--rebuild-stale", "--then-play"])
	if id <= 0:
		_say("Could not start setup.exe: run it by hand")
		return
	get_tree().quit()
