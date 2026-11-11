extends RefCounted
## Character data for the mahjong game (Phase 5-revised: characters
## before abilities). A character is pure presentation data -- name,
## theme colour, and an optional icon image path. Abilities are a
## separate system (a loadout id may be attached later; not used yet).
##
## Roster persistence is a JSON file (user://characters.json in the
## running game). Loading sanitises entries and falls back to the
## built-in sample roster when the file is missing or unusable.

const MAX_NAME := 12

## Built-in samples: the player plus sample NPCs for the CPU seats.
## All editable/deletable in the roster editor.
static func default_roster() -> Array:
	return [
		{"id": "wing", "name": "ウィング", "color": "#e86a92", "icon": ""},
		{"id": "sample_akari", "name": "あかり", "color": "#e8a33d", "icon": ""},
		{"id": "sample_yuki", "name": "ユキ", "color": "#5b8dd9", "icon": ""},
		{"id": "sample_ren", "name": "レン", "color": "#5aa469", "icon": ""},
		{"id": "sample_sora", "name": "ソラ", "color": "#8a6fd6", "icon": ""},
		{"id": "sample_mio", "name": "ミオ", "color": "#4fb3b0", "icon": ""},
	]


static func sanitize(raw: Variant) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = raw
	var name := str(d.get("name", "")).strip_edges()
	if name.is_empty():
		return {}
	if name.length() > MAX_NAME:
		name = name.left(MAX_NAME)
	var color := str(d.get("color", "#888888"))
	if not color.begins_with("#") or color.length() != 7:
		color = "#888888"
	var id := str(d.get("id", ""))
	if id.is_empty():
		id = "char_" + str(abs(name.hash()) % 1000000)
	return {"id": id, "name": name, "color": color, "icon": str(d.get("icon", ""))}


static func sanitize_roster(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	var seen := {}
	for item in raw:
		var c := sanitize(item)
		if c.is_empty() or seen.has(c["id"]):
			continue
		seen[c["id"]] = true
		out.append(c)
	return out


static func save_roster(path: String, roster: Array) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"characters": roster}))
	return true


static func load_roster(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return default_roster()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return default_roster()
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return default_roster()
	var roster := sanitize_roster(parsed.get("characters", []))
	return roster if not roster.is_empty() else default_roster()


## Pick 3 distinct CPU characters from the roster, excluding the
## player's own pick; cycles deterministically from `start`.
static func cpu_picks(roster: Array, player_id: String, start: int) -> Array:
	var pool: Array = []
	for c in roster:
		if c["id"] != player_id:
			pool.append(c)
	var picks: Array = []
	if pool.is_empty():
		return picks
	var i := start % pool.size()
	while picks.size() < mini(3, pool.size()):
		picks.append(pool[i % pool.size()])
		i += 1
	return picks
