extends Node
## Autoloaded as Settings (first, so the buses exist before anything plays):
## Music and SFX audio buses + volume options persisted to user://.

const PATH := "user://settings.json"

# A fresh install starts well under full scale: the title theme at 0 dB
# on every bus was the first thing a new player heard
const DEF := {"master": 0.7, "music": 0.5, "effects": 0.85}
var master: float = DEF["master"]
var music: float = DEF["music"]
var effects: float = DEF["effects"]
# record each session to user://sessions (see replay.gd), read when a
# dungeon is entered. Off for players and not in any menu: run_game.bat
# passes --record, and "record_sessions": true in settings.json also works.
var record_sessions := false
var host_ip := ""             # the last co-op address joined, for the lobby field


func _ready() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var i := AudioServer.bus_count
			AudioServer.add_bus(i)
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, "Master")
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f != null:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			master = clampf(float(d.get("master", DEF["master"])), 0.0, 1.0)
			music = clampf(float(d.get("music", DEF["music"])), 0.0, 1.0)
			effects = clampf(float(d.get("effects", DEF["effects"])), 0.0, 1.0)
			record_sessions = bool(d.get("record_sessions", false))
			host_ip = str(d.get("host_ip", ""))
	_apply()


func _bus(bus_name: String, v: float) -> void:
	var i := 0 if bus_name == "Master" else AudioServer.get_bus_index(bus_name)
	if i < 0:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.001)))
	AudioServer.set_bus_mute(i, v <= 0.001)


func _apply() -> void:
	_bus("Master", master)
	_bus("Music", music)
	_bus("SFX", effects)


func set_volume(which: String, v: float) -> void:
	v = clampf(v, 0.0, 1.0)
	match which:
		"master": master = v
		"music": music = v
		"effects": effects = v
	_apply()
	_save()


func set_host_ip(ip: String) -> void:
	host_ip = ip
	_save()


func _save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"master": master, "music": music,
				"effects": effects, "record_sessions": record_sessions,
				"host_ip": host_ip}))
