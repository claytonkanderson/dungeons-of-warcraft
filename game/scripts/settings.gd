extends Node
## Autoloaded as Settings (first, so the buses exist before anything plays):
## Music and SFX audio buses + volume options persisted to user://.

const PATH := "user://settings.json"

var master := 1.0
var music := 1.0
var effects := 1.0


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
			master = clampf(float(d.get("master", 1.0)), 0.0, 1.0)
			music = clampf(float(d.get("music", 1.0)), 0.0, 1.0)
			effects = clampf(float(d.get("effects", 1.0)), 0.0, 1.0)
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
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(
			{"master": master, "music": music, "effects": effects}))
