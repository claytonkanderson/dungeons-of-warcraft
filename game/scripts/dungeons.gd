extends Node
## Autoloaded as Dungeons: the vanilla dungeon ladder, relevelled to D2's
## 1-60 pacing (the four built dungeons carry a character 1 -> 20), plus
## unlock/progression helpers. Per-character state lives in GameState
## (dungeons_done / current_dungeon); assets decide what is "built".

const LIST := [
	{"id": "ragefire-chasm", "name": "Ragefire Chasm", "levels": "1-5"},
	{"id": "wailing-caverns", "name": "Wailing Caverns", "levels": "5-10"},
	{"id": "deadmines", "name": "The Deadmines", "levels": "10-15"},
	{"id": "shadowfang-keep", "name": "Shadowfang Keep", "levels": "15-20"},
	{"id": "blackfathom-deeps", "name": "Blackfathom Deeps", "levels": "20-23"},
	{"id": "stockade", "name": "The Stockade", "levels": "23-26"},
	{"id": "gnomeregan", "name": "Gnomeregan", "levels": "26-31"},
	{"id": "razorfen-kraul", "name": "Razorfen Kraul", "levels": "31-34"},
	{"id": "scarlet-monastery", "name": "Scarlet Monastery", "levels": "34-40"},
	{"id": "razorfen-downs", "name": "Razorfen Downs", "levels": "40-47"},
	{"id": "uldaman", "name": "Uldaman", "levels": "47-50"},
	{"id": "zul-farrak", "name": "Zul'Farrak", "levels": "50-53"},
	{"id": "maraudon", "name": "Maraudon", "levels": "53-56"},
	{"id": "sunken-temple", "name": "The Temple of Atal'Hakkar", "levels": "56-60"},
	{"id": "blackrock-depths", "name": "Blackrock Depths", "levels": "60-63"},
	{"id": "lower-blackrock-spire", "name": "Lower Blackrock Spire", "levels": "63-66"},
	{"id": "dire-maul", "name": "Dire Maul", "levels": "66-69"},
	{"id": "scholomance", "name": "Scholomance", "levels": "69-72"},
	{"id": "stratholme", "name": "Stratholme", "levels": "72-75"},
	{"id": "upper-blackrock-spire", "name": "Upper Blackrock Spire", "levels": "75-78"},
]


func _assets_dir() -> String:
	return Paths.root()


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
