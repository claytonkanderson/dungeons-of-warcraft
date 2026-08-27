extends Node
## Autoloaded as Music: WoW zone music + ambience extracted by
## pipeline/build_audio.py into assets/wow/audio. D2 sound effects stay with
## the Sfx autoload; this node only handles the Warcraft soundscape.
## Silently does nothing when the audio pass hasn't been run yet.

var DIR: String = Paths.asset("wow/audio")

var manifest: Dictionary = {}
var _music: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _gap_t := 0.0


func _ready() -> void:
	var f := FileAccess.open(DIR + "/audio.json", FileAccess.READ)
	if f == null:
		set_process(false)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		set_process(false)
		return
	manifest = parsed
	_ambience = AudioStreamPlayer.new()
	_ambience.volume_db = float(manifest.get("ambience_db", -8.0))
	_ambience.bus = "Music"
	add_child(_ambience)
	_music = AudioStreamPlayer.new()
	_music.volume_db = float(manifest.get("music_db", -6.0))
	_music.bus = "Music"
	add_child(_music)
	_music.finished.connect(_on_music_done)
	_start_ambience()
	_gap_t = randf_range(2.0, 6.0)


func _load_stream(fname: String) -> AudioStream:
	var path := ProjectSettings.globalize_path(DIR + "/" + fname)
	if not FileAccess.file_exists(path):
		return null
	if fname.ends_with(".mp3"):
		return AudioStreamMP3.load_from_file(path)
	if fname.ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_file(path)
	if fname.ends_with(".wav"):
		return AudioStreamWAV.load_from_file(path)
	return null


func _start_ambience() -> void:
	var amb: Array = manifest.get("ambience", [])
	if amb.is_empty():
		return
	var stream := _load_stream(str(amb[randi() % amb.size()]))
	if stream == null:
		return
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_ambience.stream = stream
	_ambience.play()


func set_dungeon(id: String) -> void:
	## Swap the ambience loop for the dungeon's own, when one was extracted.
	if _ambience == null:
		return
	var byd: Dictionary = manifest.get("dungeon_ambience", {})
	var fname := str(byd.get(id, ""))
	if fname == "":
		return
	var stream := _load_stream(fname)
	if stream == null:
		return
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	_ambience.stream = stream
	_ambience.play()


func _on_music_done() -> void:
	var gap: Array = manifest.get("gap", [15, 45])
	_gap_t = randf_range(float(gap[0]), float(gap[1]))


func _process(dt: float) -> void:
	if _music == null or _music.playing:
		return
	_gap_t -= dt
	if _gap_t > 0.0:
		return
	var tracks: Array = manifest.get("music", [])
	if tracks.is_empty():
		set_process(false)
		return
	var stream := _load_stream(str(tracks[randi() % tracks.size()]))
	if stream == null:
		_gap_t = 10.0
		return
	_music.stream = stream
	_music.play()
