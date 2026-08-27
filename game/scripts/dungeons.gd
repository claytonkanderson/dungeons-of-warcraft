extends Node
## Autoloaded as Dungeons: the vanilla (1-60) dungeon ladder plus
## unlock/progression helpers. Per-character state lives in GameState
## (dungeons_done / current_dungeon); assets decide what is "built".

const LIST := [
	{"id": "ragefire-chasm", "name": "Ragefire Chasm", "levels": "13-18"},
	{"id": "wailing-caverns", "name": "Wailing Caverns", "levels": "15-25"},
	{"id": "deadmines", "name": "The Deadmines", "levels": "17-26"},
	{"id": "shadowfang-keep", "name": "Shadowfang Keep", "levels": "22-30"},
	{"id": "blackfathom-deeps", "name": "Blackfathom Deeps", "levels": "24-32"},
	{"id": "stockade", "name": "The Stockade", "levels": "24-32"},
	{"id": "gnomeregan", "name": "Gnomeregan", "levels": "29-38"},
	{"id": "razorfen-kraul", "name": "Razorfen Kraul", "levels": "30-40"},
	{"id": "scarlet-monastery", "name": "Scarlet Monastery", "levels": "34-45"},
	{"id": "razorfen-downs", "name": "Razorfen Downs", "levels": "40-50"},
	{"id": "uldaman", "name": "Uldaman", "levels": "42-52"},
	{"id": "zul-farrak", "name": "Zul'Farrak", "levels": "44-54"},
	{"id": "maraudon", "name": "Maraudon", "levels": "46-55"},
	{"id": "sunken-temple", "name": "The Temple of Atal'Hakkar", "levels": "50-60"},
	{"id": "blackrock-depths", "name": "Blackrock Depths", "levels": "52-60"},
	{"id": "lower-blackrock-spire", "name": "Lower Blackrock Spire", "levels": "55-60"},
	{"id": "dire-maul", "name": "Dire Maul", "levels": "56-60"},
	{"id": "scholomance", "name": "Scholomance", "levels": "58-60"},
	{"id": "stratholme", "name": "Stratholme", "levels": "58-60"},
	{"id": "upper-blackrock-spire", "name": "Upper Blackrock Spire", "levels": "58-60"},
]


func _assets_dir() -> String:
	var proj := ProjectSettings.globalize_path("res://")
	if proj.ends_with("/"):
		proj = proj.substr(0, proj.length() - 1)
	return proj.get_base_dir().path_join("assets")


func built(id: String) -> bool:
	return FileAccess.file_exists(
		_assets_dir().path_join("wow/%s/placements.json" % id))


func entry(id: String) -> Dictionary:
	for d in LIST:
		if str(d.id) == id:
			return d
	return {}


func display_name(id: String) -> String:
	return str(entry(id).get("name", id))


func status(id: String, done: Array) -> String:
	## "complete" | "available" | "unbuilt" | "locked"
	var unlocked := true
	for d in LIST:
		var did := str(d.id)
		if did == id:
			if done.has(did):
				return "complete"
			if not unlocked:
				return "locked"
			return "available" if built(did) else "unbuilt"
		# progression flows past dungeons that are done — or not built yet
		unlocked = unlocked and (done.has(did) or not built(did))
	return "locked"


func next_playable(done: Array) -> String:
	## First built, unlocked, uncompleted dungeon — the "Continue" target.
	## Falls back to the last built one (replayable) when all are done.
	var fallback := ""
	for d in LIST:
		var did := str(d.id)
		if not built(did):
			continue
		fallback = did
		if status(did, done) == "available":
			return did
	return fallback
