extends SceneTree
## CPU difficulty tests (2026-11-11):
## - all three levels play full rounds that terminate and conserve points
## - strong CPU folds against riichi: danger scoring (genbutsu/suji) and
##   the discard choice in a rigged position
## Run: godot --headless --path <project> --script test_difficulty.gd

const Game := preload("res://game.gd")
const Rules := preload("res://rules.gd")

var failures := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("ok: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _init() -> void:
	# --- sims at every difficulty ---
	for d in [0, 1, 2]:
		var bad := 0
		for s in range(1, 4):
			var g = Game.new()
			g.cpu_difficulty = d
			g.start_round(s * 100 + d)
			var res: Dictionary = g.play_auto_round()
			var sum := 0
			for v in res["scores"]:
				sum += v
			if sum + res["sticks"] * 1000 != 100000 or res["reason"] == "abortive:too_many_actions":
				bad += 1
				print("  difficulty ", d, " seed ", s, " problem: ", res["reason"], " sum=", sum)
		check(bad == 0, "difficulty %d: 3 rounds terminate and conserve points" % d)

	# --- rigged position for danger scoring ---
	var g2 = Game.new()
	g2.cpu_difficulty = 2
	g2.players = []
	for s in 4:
		g2.players.append({"hand": [], "melds": [], "discards": [], "riichi": false,
			"ippatsu": false, "furiten_temp": false, "furiten_riichi": false,
			"score": 25000, "first_turn": false})
	g2.players[2]["riichi"] = true
	g2.players[2]["discards"] = ["pin5"]
	g2.players[1]["hand"] = ["man1", "man9", "man5", "pin1", "pin9", "pin5",
		"sou1", "sou9", "sou5", "ton", "nan", "shaa", "hatsu", "chun"]
	check(g2._danger(1, Rules.tile_index("pin5")) == 0, "genbutsu is danger 0")
	check(g2._danger(1, Rules.tile_index("man5")) == 2, "unrelated tile is danger 2")
	var choice: Dictionary = g2._cpu_choose_discard(1)
	check(choice["tile"] == "pin5", "strong CPU folds to the genbutsu (chose %s)" % choice["tile"])

	# --- suji scoring ---
	g2.players[2]["discards"] = ["man4"]
	check(g2._danger(1, Rules.tile_index("man4")) == 0, "discarded tile itself is genbutsu")
	check(g2._danger(1, Rules.tile_index("man1")) == 1, "man1 is suji-safe vs a man4 discard")
	check(g2._danger(1, Rules.tile_index("man7")) == 1, "man7 is suji-safe vs a man4 discard")
	check(g2._danger(1, Rules.tile_index("man5")) == 2, "man5 is not covered by a man4 discard")

	if failures == 0:
		print("ALL TESTS PASSED (cpu difficulty)")
	else:
		print("FAILURES: ", failures)
	quit()
