extends SceneTree
## Headless tests for yaku.gd (Phase 3-2): yaku detection, fu, score table.
## Run: godot --headless --path <project> --script test_yaku.gd

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


func _ev(tiles: Array, melds: Array, win_tile: String, ctx: Dictionary) -> Dictionary:
	var c: Dictionary = {"is_tsumo": false, "seat_wind": 28, "round_wind": 27}
	for k in ctx:
		c[k] = ctx[k]
	return Yaku.evaluate(Rules.counts_from_tiles(tiles), melds, Rules.tile_index(win_tile), c)


func _names(r: Dictionary) -> Array:
	var out: Array = []
	for y in r.get("yaku", []):
		out.append(y["name"])
	return out


func _run() -> void:
	# ---------- score table ----------
	_check("score 1han30 ko ron", Yaku.score_points(1, 30, 0, false, false), {"ron": 1000})
	_check("score 1han30 dealer ron", Yaku.score_points(1, 30, 0, true, false), {"ron": 1500})
	_check("score 1han40 dealer ron", Yaku.score_points(1, 40, 0, true, false), {"ron": 2000})
	_check("score 2han40 ko tsumo", Yaku.score_points(2, 40, 0, false, true), {"dealer": 1300, "other": 700})
	_check("score 3han30 ko ron", Yaku.score_points(3, 30, 0, false, false), {"ron": 3900})
	_check("score 4han30 ko ron", Yaku.score_points(4, 30, 0, false, false), {"ron": 7700})
	_check("score 5han ko ron mangan", Yaku.score_points(5, 30, 0, false, false), {"ron": 8000})
	_check("score 6han ko ron haneman", Yaku.score_points(6, 30, 0, false, false), {"ron": 12000})
	_check("score 8han ko ron baiman", Yaku.score_points(8, 30, 0, false, false), {"ron": 16000})
	_check("score 11han ko ron sanbaiman", Yaku.score_points(11, 30, 0, false, false), {"ron": 24000})
	_check("score 13han ko ron yakuman", Yaku.score_points(13, 30, 0, false, false), {"ron": 32000})
	_check("score yakuman ko ron", Yaku.score_points(0, 0, 1, false, false), {"ron": 32000})
	_check("score yakuman dealer ron", Yaku.score_points(0, 0, 1, true, false), {"ron": 48000})
	_check("score chiitoi 2han25 ko ron", Yaku.score_points(2, 25, 0, false, false), {"ron": 1600})

	# ---------- A: pinfu ron (ko) 1 han 30 fu = 1000 ----------
	var a := ["man2", "man3", "man4", "man5", "man6", "man7",
		"pin2", "pin3", "pin4", "pin6", "pin7", "pin5", "sou9", "sou9"]
	var ra := _ev(a, [], "pin5", {})
	_check("A pinfu valid", ra.get("valid"), true)
	_check("A pinfu yaku", _names(ra), ["pinfu"])
	_check("A pinfu han/fu", [ra.get("han"), ra.get("fu")], [1, 30])
	_check("A pinfu ron", ra["score"], {"ron": 1000})

	# ---------- B: pinfu tsumo = pinfu + menzen tsumo, 20 fu, 400/700 ----------
	var rb := _ev(a, [], "pin5", {"is_tsumo": true})
	_check("B pinfu tsumo han/fu", [rb.get("han"), rb.get("fu")], [2, 20])
	_check("B pinfu tsumo score", rb["score"], {"dealer": 700, "other": 400})

	# ---------- C: tanyao closed ron with a triplet, 1 han 40 fu = 1300 ----------
	var c := ["man2", "man3", "man4", "man5", "man5", "man5",
		"pin3", "pin4", "pin5", "sou6", "sou7", "sou8", "sou3", "sou3"]
	var rc := _ev(c, [], "man2", {})
	_check("C tanyao yaku", _names(rc).has("tanyao"), true)
	_check("C tanyao han/fu", [rc.get("han"), rc.get("fu")], [1, 40])
	_check("C tanyao ron", rc["score"], {"ron": 1300})

	# ---------- D: chiitoi ron, 2 han 25 fu = 1600 ----------
	var d := ["man1", "man1", "pin2", "pin2", "sou3", "sou3",
		"ton", "ton", "haku", "haku", "man9", "man9", "sou9", "sou9"]
	var rd := _ev(d, [], "sou9", {})
	_check("D chiitoi yaku", _names(rd), ["chiitoitsu"])
	_check("D chiitoi han/fu", [rd.get("han"), rd.get("fu")], [2, 25])
	_check("D chiitoi ron", rd["score"], {"ron": 1600})

	# ---------- E: open yakuhai pon, 1 han 30 fu = 1000 ----------
	var e := ["man2", "man3", "man4", "pin3", "pin4", "pin5",
		"sou6", "sou7", "sou8", "sou2", "sou2"]
	var re := _ev(e, [{"kind": "pon", "tile": 31}], "sou2", {})
	_check("E yakuhai yaku", _names(re), ["yakuhai"])
	_check("E yakuhai han/fu", [re.get("han"), re.get("fu")], [1, 30])
	_check("E yakuhai ron", re["score"], {"ron": 1000})

	# ---------- F: honitsu closed ron, 3 han 50 fu = 6400 ----------
	var f := ["sou2", "sou3", "sou4", "sou5", "sou6", "sou7",
		"sou9", "sou9", "sou9", "ton", "ton", "ton", "haku", "haku"]
	var rf := _ev(f, [], "sou9", {})
	# ton triplet is the round wind here, so yakuhai stacks: honitsu 3 + yakuhai 1
	_check("F honitsu present", _names(rf).has("honitsu"), true)
	_check("F honitsu han/fu", [rf.get("han"), rf.get("fu")], [4, 50])
	_check("F honitsu ron mangan", rf["score"], {"ron": 8000})

	# ---------- G: sanshoku doujun + tanyao, 3 han 30 fu = 3900 ----------
	var g := ["man2", "man3", "man4", "pin2", "pin3", "pin4",
		"sou2", "sou3", "sou4", "pin7", "pin8", "pin9", "sou5", "sou5"]
	var rg := _ev(g, [], "pin9", {})
	_check("G sanshoku present", _names(rg).has("sanshoku_doujun"), true)
	_check("G han", rg.get("han"), 3)
	_check("G ron", rg["score"], {"ron": 3900})

	# ---------- H: ikki tsuukan, 2 han 30 fu = 2000 ----------
	var h := ["pin1", "pin2", "pin3", "pin4", "pin5", "pin6", "pin7", "pin8", "pin9",
		"man3", "man4", "man5", "haku", "haku"]
	var rh := _ev(h, [], "man5", {})
	_check("H ikki yaku", _names(rh), ["ikkitsuukan"])
	# dragon pair adds 2 fu: 2 han 40 fu = 2600
	_check("H ikki ron", rh["score"], {"ron": 2600})

	# ---------- I: toitoi + sanankou (ron), 4 han -> mangan 8000 ----------
	var i := ["man3", "man3", "man3", "pin5", "pin5", "pin5",
		"sou7", "sou7", "sou7", "ton", "ton", "ton", "haku", "haku"]
	var ri := _ev(i, [], "ton", {})
	_check("I toitoi+sanankou", [_names(ri).has("toitoi"), _names(ri).has("sanankou")], [true, true])
	# ton triplet is the round wind: +1 yakuhai han = 5 han, still mangan
	_check("I han", ri.get("han"), 5)
	_check("I ron mangan", ri["score"], {"ron": 8000})

	# ---------- J: suuankou by tsumo = yakuman ----------
	var rj := _ev(i, [], "ton", {"is_tsumo": true})
	_check("J suuankou yakuman", rj.get("yakuman"), 1)
	_check("J suuankou tsumo score", rj["score"], {"dealer": 16000, "other": 8000})

	# ---------- K: suuankou tanki = double yakuman, ron 64000 ----------
	var k := ["man3", "man3", "man3", "pin5", "pin5", "pin5",
		"sou7", "sou7", "sou7", "ton", "ton", "ton", "haku", "haku"]
	# tanki: 4 triplets + single haku, win on haku -> rebuild: trips use 12, pair haku
	var rk := _ev(k, [], "haku", {})
	_check("K suuankou tanki yakuman", rk.get("yakuman"), 2)
	_check("K suuankou tanki ron", rk["score"], {"ron": 64000})

	# ---------- L: kokushi 13-wait = double yakuman ----------
	var l := ["man1", "man9", "pin1", "pin9", "sou1", "sou9",
		"ton", "nan", "shaa", "pei", "haku", "hatsu", "chun", "ton"]
	var rl := _ev(l, [], "ton", {})
	_check("L kokushi yakuman", rl.get("yakuman"), 2)
	_check("L kokushi ron", rl["score"], {"ron": 64000})

	# ---------- M: daisangen = yakuman ----------
	var m := ["haku", "haku", "haku", "hatsu", "hatsu", "hatsu",
		"chun", "chun", "chun", "man2", "man3", "man4", "pin5", "pin5"]
	var rm := _ev(m, [], "man4", {})
	_check("M daisangen yakuman", rm.get("yakuman"), 1)
	_check("M daisangen ron", rm["score"], {"ron": 32000})

	# ---------- N: shousuushi, 2 han 60 fu = 3900 (double-wind pair = 4 fu) ----------
	var n := ["ton", "ton", "ton", "nan", "nan", "nan",
		"shaa", "shaa", "shaa", "sou3", "sou4", "sou5", "pei", "pei"]
	var rn := _ev(n, [], "sou5", {"seat_wind": 30, "round_wind": 30})
	_check("N shousuushi yaku", _names(rn).has("shousuushi"), true)
	# the three wind triplets are closed (ron on a sequence) = sanankou,
	# and sou+h honors = honitsu: 2 + 2 + 3 = 7 han haneman
	_check("N shousuushi han/fu", [rn.get("han"), rn.get("fu")], [7, 60])
	_check("N shousuushi ron haneman", rn["score"], {"ron": 12000})

	# ---------- O: daisuushi = double yakuman ----------
	var o := ["ton", "ton", "ton", "nan", "nan", "nan",
		"shaa", "shaa", "shaa", "pei", "pei", "pei", "haku", "haku"]
	var ro := _ev(o, [], "ton", {})
	_check("O daisuushi yakuman", ro.get("yakuman"), 2)

	# ---------- P: ryanpeikou beats chiitoi reading, 3 han 40 fu = 7700 ----------
	var p := ["man2", "man2", "man3", "man3", "man4", "man4",
		"pin6", "pin6", "pin7", "pin7", "pin8", "pin8", "sou9", "sou9"]
	var rp := _ev(p, [], "sou9", {})
	_check("P ryanpeikou yaku", _names(rp).has("ryanpeikou"), true)
	_check("P ryanpeikou han/fu", [rp.get("han"), rp.get("fu")], [3, 40])
	_check("P ryanpeikou ron", rp["score"], {"ron": 5200})

	# ---------- Q: iipeikou, 1 han 30 fu = 1000 ----------
	var q := ["man2", "man2", "man3", "man3", "man4", "man4",
		"pin2", "pin3", "pin4", "sou6", "sou7", "sou8", "ton", "ton"]
	var rq := _ev(q, [], "pin4", {})
	_check("Q iipeikou yaku", _names(rq).has("iipeikou"), true)
	# ton pair is the round wind: +2 fu -> 1 han 40 fu = 1300
	_check("Q iipeikou ron", rq["score"], {"ron": 1300})

	# ---------- R: honroutou + toitoi, 4 han 60 fu -> mangan ----------
	var r := ["man1", "man1", "man1", "man9", "man9", "man9",
		"pin1", "pin1", "pin1", "haku", "haku", "haku", "chun", "chun"]
	var rr := _ev(r, [], "haku", {})
	_check("R honroutou+toitoi", [_names(rr).has("honroutou"), _names(rr).has("toitoi")], [true, true])
	# sanankou (3 closed triplets) and yakuhai (haku) stack: 7 han haneman
	_check("R ron haneman", rr["score"], {"ron": 12000})

	# ---------- S: no yaku -> invalid ----------
	var s := ["man1", "man2", "man3", "pin2", "pin3", "pin4",
		"pin6", "pin7", "pin8", "sou3", "sou4", "sou5", "chun", "chun"]
	var rs := _ev(s, [], "man3", {})
	_check("S no yaku invalid", rs.get("valid", false), false)

	# ---------- T: menzen tsumo + tanyao, 2 han 30 fu, 500/1000 ----------
	var t := ["man2", "man3", "man4", "man5", "man6", "man7",
		"pin2", "pin3", "pin4", "pin5", "pin6", "pin7", "sou8", "sou8"]
	var rt := _ev(t, [], "sou8", {"is_tsumo": true})
	_check("T tsumo+tanyao", [_names(rt).has("menzen_tsumo"), _names(rt).has("tanyao")], [true, true])
	_check("T han/fu", [rt.get("han"), rt.get("fu")], [2, 30])
	_check("T tsumo score", rt["score"], {"dealer": 1000, "other": 500})

	# ---------- V: suukantsu = yakuman ----------
	var rv := _ev(["haku", "haku"],
		[{"kind": "kan_closed", "tile": 2}, {"kind": "kan_closed", "tile": 12},
		{"kind": "kan_closed", "tile": 23}, {"kind": "kan_closed", "tile": 27}],
		"haku", {"is_tsumo": true})
	# yakuman stack additively: suukantsu 1 + suuankou tanki 2 = 3
	_check("V suukantsu yakuman", rv.get("yakuman"), 3)
	_check("V suukantsu tsumo score", rv["score"], {"dealer": 48000, "other": 24000})
