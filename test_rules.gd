extends SceneTree
## Headless test runner for rules.gd (Phase 3-1).
## Run: godot --headless --path <project> --script test_rules.gd
## Prints one line per case and a final ALL TESTS PASSED / FAILURES: n line.

var Rules: GDScript
var failures := 0
var total := 0


func _init() -> void:
	Rules = load("res://rules.gd")
	_run()
	if failures == 0:
		print("ALL TESTS PASSED (", total, " cases)")
	else:
		print("FAILURES: ", failures, " of ", total)
	quit()


func _check(name: String, got, want) -> void:
	total += 1
	if str(got) == str(want):
		print("PASS ", name)
	else:
		failures += 1
		print("FAIL ", name, " got=", got, " want=", want)


func _counts(tiles: Array) -> Array:
	return Rules.counts_from_tiles(tiles)


func _run() -> void:
	# --- tile index conversion ---
	_check("idx man1", Rules.tile_index("man1"), 0)
	_check("idx man5r", Rules.tile_index("man5r"), 4)
	_check("idx pin1", Rules.tile_index("pin1"), 9)
	_check("idx sou9", Rules.tile_index("sou9"), 26)
	_check("idx ton", Rules.tile_index("ton"), 27)
	_check("idx chun", Rules.tile_index("chun"), 33)

	# --- standard win: 234m 567m 234p 567p + 88s ---
	var win_std := ["man2", "man3", "man4", "man5", "man6", "man7",
		"pin2", "pin3", "pin4", "pin5", "pin6", "pin7", "sou8", "sou8"]
	_check("win_std is_winning", Rules.is_winning(_counts(win_std)), true)
	_check("win_std shanten", Rules.shanten(_counts(win_std)), -1)

	# same hand with a red five instead of a normal five still wins
	var win_red := win_std.duplicate()
	win_red[3] = "man5r"
	_check("win_red5 is_winning", Rules.is_winning(_counts(win_red)), true)

	# 13-tile tenpai of the same hand (one sou8 removed) waits only on sou8
	var ten_std := win_std.duplicate()
	ten_std.remove_at(13)
	_check("ten_std shanten", Rules.shanten(_counts(ten_std)), 0)
	_check("ten_std waits", Rules.winning_tiles(_counts(ten_std)), [25])

	# broken pair -> not a win
	var not_win := win_std.duplicate()
	not_win[13] = "sou9"
	_check("not_win is_winning", Rules.is_winning(_counts(not_win)), false)

	# --- ryanmen (two-sided) wait: 34m waits on 2m and 5m ---
	var ryan := ["man3", "man4", "pin5", "pin6", "pin7",
		"sou2", "sou3", "sou4", "sou6", "sou7", "sou8", "pin2", "pin2"]
	_check("ryanmen shanten", Rules.shanten(_counts(ryan)), 0)
	_check("ryanmen waits", Rules.winning_tiles(_counts(ryan)), [1, 4])

	# --- penchan (edge) wait: 12m waits only on 3m ---
	var pen := ["man1", "man2", "pin2", "pin3", "pin4",
		"pin6", "pin7", "pin8", "sou3", "sou4", "sou5", "hatsu", "hatsu"]
	_check("penchan shanten", Rules.shanten(_counts(pen)), 0)
	_check("penchan waits", Rules.winning_tiles(_counts(pen)), [2])

	# --- tanki (pair) wait: 4 sets + single chun ---
	var tanki := ["man2", "man3", "man4", "man5", "man6", "man7",
		"pin2", "pin3", "pin4", "pin5", "pin6", "pin7", "chun"]
	_check("tanki shanten", Rules.shanten(_counts(tanki)), 0)
	_check("tanki waits", Rules.winning_tiles(_counts(tanki)), [33])

	# --- seven pairs ---
	var chiitoi_win := ["man1", "man1", "pin2", "pin2", "sou3", "sou3",
		"ton", "ton", "haku", "haku", "man9", "man9", "sou9", "sou9"]
	_check("chiitoi is_winning", Rules.is_winning(_counts(chiitoi_win)), true)
	var chiitoi_ten := chiitoi_win.duplicate()
	chiitoi_ten.remove_at(13)
	_check("chiitoi tenpai shanten", Rules.shanten(_counts(chiitoi_ten)), 0)
	_check("chiitoi tenpai waits", Rules.winning_tiles(_counts(chiitoi_ten)), [26])

	# --- thirteen orphans ---
	var kokushi_ten := ["man1", "man9", "pin1", "pin9", "sou1", "sou9",
		"ton", "nan", "shaa", "pei", "haku", "hatsu", "chun"]
	_check("kokushi 13wait shanten", Rules.shanten(_counts(kokushi_ten)), 0)
	_check("kokushi 13wait waits", Rules.winning_tiles(_counts(kokushi_ten)),
		[0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33])
	var kokushi_win := kokushi_ten.duplicate()
	kokushi_win.append("ton")
	_check("kokushi is_winning", Rules.is_winning(_counts(kokushi_win)), true)

	# --- shanten counting ---
	var sh1 := ["man1", "man2", "man3", "pin4", "pin5", "pin6",
		"sou7", "sou8", "sou9", "ton", "ton", "haku", "hatsu"]
	_check("1-shanten hand", Rules.shanten(_counts(sh1)), 1)
	# drawing haku or hatsu (making a second pair) brings it to tenpai
	var eff1: Array = Rules.effective_tiles(_counts(sh1))
	_check("1-shanten ukeire has haku", eff1.has(31), true)
	_check("1-shanten ukeire has hatsu", eff1.has(32), true)

	var sh2 := ["man1", "man2", "man3", "pin4", "pin5", "pin7",
		"sou7", "sou8", "sou9", "ton", "ton", "haku", "shaa"]
	_check("2-shanten hand", Rules.shanten(_counts(sh2)), 2)

	# a hand with four identical tiles still decomposes (1111 -> triplet + 1)
	var four_same := ["man1", "man1", "man1", "man1", "man2", "man3",
		"pin5", "pin6", "pin7", "sou2", "sou3", "sou4", "haku", "haku"]
	_check("four-of-a-kind is_winning", Rules.is_winning(_counts(four_same)), true)
