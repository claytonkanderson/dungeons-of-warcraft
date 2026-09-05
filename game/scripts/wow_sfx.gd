extends Node
## Autoloaded as WowSfx: WoW creature voices + melee impact foley extracted
## by pipeline/build_audio.py into assets/wow/audio (wowsfx.json). The D2
## effects stay with the Sfx autoload — this is the Warcraft layer.
## Silently does nothing when the audio pass hasn't been run.

var DIR: String = Paths.asset("wow/audio")

var manifest: Dictionary = {}
var _cache: Dictionary = {}
var loads := 0
var _last: Dictionary = {}     # throttle: first-variant name -> last frame


func _ready() -> void:
	var f := FileAccess.open(DIR + "/wowsfx.json", FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		manifest = parsed


func _stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var path := ProjectSettings.globalize_path(DIR + "/" + name)
	var s: AudioStream = null
	if FileAccess.file_exists(path):
		if name.ends_with(".ogg"):
			s = AudioStreamOggVorbis.load_from_file(path)
		elif name.ends_with(".wav"):
			s = AudioStreamWAV.load_from_file(path)
	_cache[name] = s
	loads += 1
	return s


func _play_at(names: Array, pos: Vector3, vol_db := -4.0,
		gap_frames := 6) -> void:
	if names.is_empty():
		return
	var key := str(names[0])
	var frame := Engine.get_process_frames()
	if frame - int(_last.get(key, -1000)) < gap_frames:
		return
	_last[key] = frame
	var stream := _stream(str(names[randi() % names.size()]))
	if stream == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = vol_db
	p.pitch_scale = randf_range(0.95, 1.06)
	p.unit_size = 6.0
	p.max_distance = 60.0
	p.bus = "SFX"
	var host: Node = get_tree().current_scene
	if host == null:
		host = self
	host.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


func voice(group: String, field: String, pos: Vector3, chance := 1.0) -> void:
	if group == "" or (chance < 1.0 and randf() > chance):
		return
	var g: Dictionary = manifest.get("voices", {}).get(group, {})
	var names: Array = g.get(field, [])
	# the player-race NPC sets (orc, tauren, night elf, ...) ship attack,
	# wound and death but no aggro line — an attack bark serves as one
	if names.is_empty() and field == "aggro":
		names = g.get("attack", [])
	_play_at(names, pos)


func impact(kind: String, pos: Vector3, chance := 1.0) -> void:
	if chance < 1.0 and randf() > chance:
		return
	_play_at(manifest.get("impacts", {}).get(kind, []), pos, -6.0)
