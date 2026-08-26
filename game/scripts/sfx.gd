extends Node
## Sfx: plays the D2 sounds exported by pipeline/export_sounds.py.
## Manifest (sounds.json) maps game events and MonSounds ids to wav variant
## lists; a random variant plays each time, like the Group Size rolls in D2.

const DIR := "res://../assets/sounds"

var meta: Dictionary = {}
var _cache: Dictionary = {}        # sound key -> AudioStreamWAV (or null)
var _last_frame: Dictionary = {}   # sound key -> last played frame (throttle)
var _plays := 0                    # debug: total sounds started


func _ready() -> void:
	var f := FileAccess.open(DIR + "/sounds.json", FileAccess.READ)
	if f == null:
		push_warning("Sfx: no sounds.json; run pipeline/export_sounds.py")
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		meta = parsed


func _stream(key: String) -> AudioStreamWAV:
	if _cache.has(key):
		return _cache[key]
	var path := DIR + "/" + key + ".wav"
	var s: AudioStreamWAV = null
	if FileAccess.file_exists(path):
		s = AudioStreamWAV.load_from_file(path)
	_cache[key] = s
	return s


func _volume_db(key: String) -> float:
	# Sounds.txt volume 0-255; -3dB headroom so stacked shots don't clip
	var vols: Dictionary = meta.get("volumes", {})
	var v := float(vols.get(key, 255))
	return linear_to_db(clampf(v / 255.0, 0.05, 1.0)) - 3.0


func _pick(keys: Array) -> String:
	if keys.is_empty():
		return ""
	return str(keys[randi() % keys.size()])


func play_at(key: String, pos: Vector3, min_gap_frames := 3) -> void:
	if key == "":
		return
	var frame := Engine.get_process_frames()
	if frame - int(_last_frame.get(key, -1000)) < min_gap_frames:
		return
	_last_frame[key] = frame
	var stream := _stream(key)
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = _volume_db(key)
	p.pitch_scale = randf_range(0.96, 1.05)
	p.unit_size = 6.0
	p.max_distance = 70.0
	var host: Node = get_tree().current_scene
	if host == null:
		host = self
	host.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
	_plays += 1
	if _plays <= 3 and OS.get_cmdline_user_args().size() > 0:
		print("sfx play #%d: %s" % [_plays, key])


func play_ui(key: String, min_gap_frames := 3) -> void:
	if key == "":
		return
	var frame := Engine.get_process_frames()
	if frame - int(_last_frame.get(key, -1000)) < min_gap_frames:
		return
	_last_frame[key] = frame
	var stream := _stream(key)
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = _volume_db(key)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func event(name: String, pos: Vector3, chance := 1.0) -> void:
	if chance < 1.0 and randf() > chance:
		return
	var evs: Dictionary = meta.get("events", {})
	var keys: Array = evs.get(name, [])
	play_at(_pick(keys), pos)


func event_ui(name: String) -> void:
	var evs: Dictionary = meta.get("events", {})
	var keys: Array = evs.get(name, [])
	play_ui(_pick(keys))


func monster(mon_id: String, field: String, pos: Vector3, chance := 1.0) -> void:
	if mon_id == "" or (chance < 1.0 and randf() > chance):
		return
	var mons: Dictionary = meta.get("monsters", {})
	var entry: Dictionary = mons.get(mon_id, {})
	var keys: Array = entry.get(field, [])
	play_at(_pick(keys), pos)
