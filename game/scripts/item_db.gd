extends Node
## Autoloaded as ItemDB: item definitions, treasure-class drop rolls,
## cached flippy/inventory textures.

var ASSETS: String = Paths.root()

var items := {}
var treasure := {}
var _inv_tex := {}


func _ready() -> void:
	items = _load_json("items/items.json")
	treasure = _load_json("items/treasure.json")


func _load_json(rel: String) -> Dictionary:
	var f := FileAccess.open(ProjectSettings.globalize_path(
		ASSETS.path_join(rel)), FileAccess.READ)
	if f == null:
		push_error("missing " + rel + " - run pipeline/d2/export_items.py")
		return {}
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	return d


func item(code: String) -> Dictionary:
	return items.get(code, {})


func inv_texture(code: String) -> Texture2D:
	var it := item(code)
	var file := str(it.get("invfile", ""))
	if file == "":
		file = "inv" + code
	file = file.to_lower()
	if _inv_tex.has(file):
		return _inv_tex[file]
	var img := Image.load_from_file(ProjectSettings.globalize_path(
		ASSETS.path_join("items/inv/%s.png" % file)))
	var tex: Texture2D = ImageTexture.create_from_image(img) if img != null else null
	_inv_tex[file] = tex
	return tex


## Roll a treasure class -> Array of {"code": String, "gold": int (0 if item)}.
func roll(tc: String, depth := 0) -> Array:
	var out: Array = []
	if depth > 8 or tc == "":
		return out
	var entry: Dictionary = treasure.get(tc, {})
	if entry.is_empty():
		# leaf: an item code, possibly "gld,mul=1280"
		var parts := tc.split(",")
		var code := parts[0]
		if code == "gld":
			var mult := 1.0
			for p in parts:
				if p.begins_with("mul="):
					mult = float(p.substr(4)) / 256.0
			out.append({"code": "gold", "gold": maxi(1, int(randf_range(1, 24) * mult))})
		elif items.has(code):
			out.append({"code": code, "gold": 0})
		return out
	var picks := 1
	var praw := str(entry.get("picks", "1"))
	if praw != "":
		picks = absi(int(praw))
	var nodrop := 0
	var ndraw := str(entry.get("nodrop", ""))
	if ndraw != "":
		nodrop = int(ndraw)
	var rows: Array = entry.get("items", [])
	var total := nodrop
	for r in rows:
		total += int(r[1])
	if total <= 0:
		return out
	for i in range(picks):
		var pick := randi() % total
		if pick < nodrop:
			continue
		pick -= nodrop
		for r in rows:
			pick -= int(r[1])
			if pick < 0:
				out.append_array(roll(str(r[0]), depth + 1))
				break
	return out
