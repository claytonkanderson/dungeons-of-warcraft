extends Node
## Loads pipeline spritesheets (PNG + sidecar JSON) from the assets directory
## and caches them. Autoloaded as SpriteDB.

var ASSETS: String = Paths.root()

var _cache := {}


class Sheet:
	var texture: Texture2D
	var cell: Vector2i
	var origin: Vector2i     # D2 unit origin (feet) within a cell
	var dirs: int
	var frames: int
	var fps: float
	var triggers: Array      # action-frame indices


func load_sheet(rel: String) -> Sheet:
	if _cache.has(rel):
		return _cache[rel]
	var png := ASSETS.path_join(rel + ".png")
	var meta_path := ASSETS.path_join(rel + ".json")
	var img := Image.load_from_file(ProjectSettings.globalize_path(png))
	if img == null:
		push_error("missing sheet: " + png)
		return null
	var f := FileAccess.open(ProjectSettings.globalize_path(meta_path), FileAccess.READ)
	if f == null:
		push_error("missing meta: " + meta_path)
		return null
	var meta: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()

	var s := Sheet.new()
	s.texture = ImageTexture.create_from_image(img)
	s.cell = Vector2i(int(meta["cell"][0]), int(meta["cell"][1]))
	s.origin = Vector2i(int(meta["origin"][0]), int(meta["origin"][1]))
	s.dirs = int(meta["dirs"])
	s.frames = int(meta["frames"])
	s.fps = float(meta.get("fps", 25.0))
	s.triggers = meta.get("triggers", [])
	_cache[rel] = s
	return s


func gamedata() -> Dictionary:
	if _cache.has("::gamedata"):
		return _cache["::gamedata"]
	var f := FileAccess.open(
		ProjectSettings.globalize_path(ASSETS.path_join("gamedata.json")),
		FileAccess.READ)
	if f == null:
		push_error("missing gamedata.json - run the pipeline")
		return {}
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	_cache["::gamedata"] = d
	return d
