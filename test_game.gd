extends SceneTree
## Headless tests for game.gd (Phase 3-4a): legality, detectors, simulations.
## Run: godot --headless --path <project> --script test_game.gd

var Rules: GDScript
var Game: GDScript
var failures := 0
var total := 0


func _init() -> void:
	Rules = load("res://rules.gd")
	Game = load("res://game.gd")
	if not Game.can_instantiate():
		print("FAIL game.gd failed to load (parse error above)")
		quit()
		return
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


func _run() -> void:
	# --- meld-aware shanten (rules.gd) ---
	# 1 meld fixed; closed part = 3 sets + pair (10 tiles) is a win shape
	var closed_win: Array = Rules.counts_from_tiles(
		["man2", "man3", "man4", "pin5", "pin6", "pin7", "sou6", "sou7", "sou8", "haku"])
	# haku is single -> tenpai (tanki), not a win
	_check("melded tenpai shanten", Rules.shanten_for(closed_win, 1), 0)
	var closed_win2: Array = Rules.counts_from_tiles(
		["man2", "man3", "man4", "pin5", "pin6", "pin7", "sou6", "sou7", "sou8", "haku", "haku"])
	# 11 tiles cannot occur mid-hand, but the pair-completed shape must read as a win
	_check("melded win shape", Rules.is_winning_for(closed_win2, 1), true)

	# --- call legality ---
	var hc: Array = Rules.counts_from_tiles(
		["man2", "man4", "pin5", "pin5", "sou9", "sou9", "sou9", "ton", "haku", "haku"])
	_check("pon possible (pin5)", Game.legal_pon(hc, 13), true)
	_check("pon impossible (man2)", Game.legal_pon(hc, 1), false)
	_check("daiminkan (sou9)", Game.legal_daiminkan(hc, 26), true)
	_check("daiminkan no (pin5)", Game.legal_daiminkan(hc, 13), false)
	_check("chi options man3", Game.legal_chi(hc, 2), [1])
	_check("chi options honor", Game.legal_chi(hc, 27), [])

	# --- kyushu kinds ---
	_check("kyushu 9 kinds", Game.kyushu_kinds(
		["man1", "man9", "pin1", "pin9", "sou1", "sou9", "ton", "nan", "shaa", "man3", "man4", "pin5", "sou6"]), 9)
	_check("kyushu 8 kinds", Game.kyushu_kinds(
		["man1", "man9", "pin1", "pin9", "sou1", "sou9", "ton", "man3", "man4", "pin5", "sou6", "sou7", "haku"]), 8)

	# --- four winds detector ---
	var g = Game.new()
	g.players = []
	for s in 4:
		g.players.append({"hand": [], "melds": [], "discards": ["ton"], "riichi": false,
			"ippatsu": false, "furiten_temp": false, "furiten_riichi": false,
			"score": 25000, "first_turn": false})
	g.any_calls = false
	_check("four winds true", g._check_four_winds(), true)
	g.players[2]["discards"] = ["nan"]
	_check("four winds false", g._check_four_winds(), false)

	# --- full-round simulations: termination + score conservation ---
	var reasons := {}
	var bad := 0
	for seed in range(1, 13):
		var gg = Game.new()
		gg.start_round(seed)
		var res: Dictionary = gg.play_auto_round()
		var sum := 0
		for v in res["scores"]:
			sum += v
		if sum + res["sticks"] * 1000 != 100000:
			bad += 1
			print("  seed ", seed, " conservation broken: sum=", sum, " sticks=", res["sticks"], " reason=", res["reason"])
		if res["reason"] == "abortive:too_many_actions":
			bad += 1
			print("  seed ", seed, " did not terminate cleanly")
		reasons[res["reason"]] = reasons.get(res["reason"], 0) + 1
	_check("12 simulated rounds conserve points and terminate", bad, 0)
	print("  round end reasons: ", reasons)
