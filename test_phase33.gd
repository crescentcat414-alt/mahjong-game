extends SceneTree
## Headless tests for Phase 3-3: dora, riichi guards, furiten.
## Run: godot --headless --path <project> --script test_phase33.gd

var Rules: GDScript
var Yaku: GDScript
var failures := 0
var total := 0


func _init() -> void:
	Rules = load("res://rules.gd")
	Yaku = load("res://yaku.gd")
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


func _ev(tiles: Array, win_tile: String, ctx: Dictionary) -> Dictionary:
	var c: Dictionary = {"is_tsumo": false, "seat_wind": 28, "round_wind": 27}
	for k in ctx:
		c[k] = ctx[k]
	return Yaku.evaluate(Rules.counts_from_tiles(tiles), [], Rules.tile_index(win_tile), c)


func _names(r: Dictionary) -> Array:
	var out: Array = []
	for y in r.get("yaku", []):
		out.append(y["name"])
	return out


func _run() -> void:
	# --- next tile (dora indicator mapping) ---
	_check("next man9->man1", Rules.next_tile_index(8), 0)
	_check("next man1->man2", Rules.next_tile_index(0), 1)
	_check("next sou5->sou6", Rules.next_tile_index(22), 23)
	_check("next ton->nan", Rules.next_tile_index(27), 28)
	_check("next pei->ton", Rules.next_tile_index(30), 27)
	_check("next haku->hatsu", Rules.next_tile_index(31), 32)
	_check("next chun->haku", Rules.next_tile_index(33), 31)

	# --- count_dora ---
	var full1: Dictionary = {}
	var hand_d := ["sou3", "sou3", "sou3", "man2", "man2"]
	var counts_d: Array = Rules.counts_from_tiles(hand_d)
	_check("dora ind sou2 -> sou3 x3", Yaku.count_dora(counts_d, [19]), 3)
	_check("dora double indicator", Yaku.count_dora(counts_d, [0, 0]), 4)

	# --- evaluate with dora: pinfu ron + 1 dora = 2 han 30 fu = 2000 ---
	var a := ["man2", "man3", "man4", "man5", "man6", "man7",
		"pin2", "pin3", "pin4", "pin6", "pin7", "pin5", "sou9", "sou9"]
	var r1 := _ev(a, "pin5", {"dora_indicators": [3]})  # indicator man4 -> dora man5 (1 in hand)
	_check("dora han", r1.get("han"), 2)
	_check("dora counted", r1.get("dora"), 1)
	_check("dora ron", r1["score"], {"ron": 2000})

	# --- red five adds han: pinfu + dora1 + red1 = 3 han = 3900 ---
	var r2 := _ev(a, "pin5", {"dora_indicators": [3], "red_count": 1})
	_check("red han", r2.get("han"), 3)
	_check("red ron", r2["score"], {"ron": 3900})

	# --- ura dora only with riichi: riichi + pinfu + ura2 = 4 han = 7700 ---
	var r3 := _ev(a, "pin5", {"riichi": true, "ura_indicators": [25]})  # ura ind sou8 -> sou9 x2
	_check("ura han", r3.get("han"), 4)
	_check("ura names", [_names(r3).has("riichi"), _names(r3).has("ura_dora")], [true, true])
	_check("ura ron", r3["score"], {"ron": 7700})

	# --- ura ignored without riichi ---
	var r4 := _ev(a, "pin5", {"ura_indicators": [25]})
	_check("ura ignored han", r4.get("han"), 1)
	_check("ura ignored ron", r4["score"], {"ron": 1000})

	# --- ippatsu needs riichi ---
	var r5 := _ev(a, "pin5", {"ippatsu": true})
	_check("ippatsu without riichi han", r5.get("han"), 1)
	var r6 := _ev(a, "pin5", {"riichi": true, "ippatsu": true})
	_check("riichi+ippatsu+pinfu han", r6.get("han"), 3)
	_check("riichi+ippatsu ron", r6["score"], {"ron": 3900})

	# --- furiten ---
	var ten := ["man2", "man3", "man4", "man5", "man6", "man7",
		"pin2", "pin3", "pin4", "pin5", "pin6", "pin7", "sou8"]
	var ct: Array = Rules.counts_from_tiles(ten)  # waits only on sou8 (25)
	_check("furiten own discard", Rules.is_furiten(ct, [25]), true)
	_check("no furiten other tile", Rules.is_furiten(ct, [0, 13]), false)
	var ryan := ["man3", "man4", "pin5", "pin6", "pin7",
		"sou2", "sou3", "sou4", "sou6", "sou7", "sou8", "pin2", "pin2"]
	var cr: Array = Rules.counts_from_tiles(ryan)  # waits man2 (1) and man5 (4)
	_check("furiten one of two waits", Rules.is_furiten(cr, [4]), true)
	_check("no furiten unrelated", Rules.is_furiten(cr, [33]), false)

	# --- can_riichi ---
	_check("can riichi tenpai 25000", Rules.can_riichi(ct, 25000), true)
	_check("can riichi not tenpai", Rules.can_riichi(Rules.counts_from_tiles(
		["man1", "man2", "man3", "pin4", "pin5", "pin6",
		"sou7", "sou8", "sou9", "ton", "ton", "haku", "hatsu"]), 25000), false)
	_check("can riichi too poor", Rules.can_riichi(ct, 900), false)
