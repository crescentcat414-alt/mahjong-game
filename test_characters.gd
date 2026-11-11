extends SceneTree
## Character data tests: sanitize, save/load round-trip, CPU picks.
## Run: godot --headless --path <project> --script test_characters.gd

const Chars := preload("res://characters.gd")

var failures := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("ok: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _init() -> void:
	var roster: Array = Chars.default_roster()
	check(roster.size() == 6, "default roster has 6 characters")
	check(roster[0]["name"] == "ウィング", "first sample is Wing")

	# sanitize drops nameless entries, truncates long names, fixes colour
	var cleaned: Array = Chars.sanitize_roster([
		{"id": "a", "name": "  テスト  ", "color": "#123456", "icon": ""},
		{"id": "b", "name": "", "color": "#123456"},
		{"id": "a", "name": "重複", "color": "red"},
		{"name": "とてもとても長い名前のキャラクターです"},
		"not a dict",
	])
	check(cleaned.size() == 2, "sanitize keeps 2 valid entries (got %d)" % cleaned.size())
	check(cleaned[0]["name"] == "テスト", "names are trimmed")
	check(cleaned[1]["name"].length() == Chars.MAX_NAME, "long names truncated to %d" % Chars.MAX_NAME)
	check(cleaned[1]["color"] == "#888888", "bad colour replaced by default")

	# save/load round trip through a temp file
	var path := "user://test_characters.json"
	roster.append(Chars.sanitize({"name": "新規キャラ", "color": "#00aa55"}))
	check(Chars.save_roster(path, roster), "save_roster succeeds")
	var loaded: Array = Chars.load_roster(path)
	check(loaded.size() == roster.size(), "round trip keeps %d entries" % roster.size())
	check(loaded[loaded.size() - 1]["name"] == "新規キャラ", "round trip keeps the new character")

	# missing file falls back to defaults
	var missing: Array = Chars.load_roster("user://no_such_file_xyz.json")
	check(missing.size() == 6, "missing file falls back to the default roster")

	# CPU picks are distinct and exclude the player's character
	var picks: Array = Chars.cpu_picks(loaded, "wing", 0)
	check(picks.size() == 3, "3 CPU picks")
	var ids := {}
	for p in picks:
		ids[p["id"]] = true
	check(ids.size() == 3 and not ids.has("wing"), "picks are distinct and exclude the player")

	if failures == 0:
		print("ALL TESTS PASSED (characters)")
	else:
		print("FAILURES: ", failures)
	quit()
