extends SceneTree
## Smoke test: a "human" seat 0 driven by a trivial policy through
## advance()/human_act() must still terminate rounds with points conserved.
## Run: godot --headless --path <project> --script test_human.gd

var failures := 0
var total := 0


func _init() -> void:
	var Game: GDScript = load("res://game.gd")
	if not Game.can_instantiate():
		print("FAIL game.gd failed to load")
		quit()
		return
	var bad := 0
	for seed in range(1, 7):
		var g = Game.new()
		g.human_seat = 0
		g.start_round(seed)
		var guard := 0
		while g.result.is_empty() and guard < 20000:
			guard += 1
			g.advance()
			if not g.awaiting.is_empty():
				_human_policy(g)
		var sum := 0
		for v in g.result["scores"]:
			sum += v
		if sum + g.result["sticks"] * 1000 != 100000 or g.result.is_empty():
			bad += 1
			print("  seed ", seed, " bad end: ", g.result.get("reason", "none"), " sum=", sum)
		else:
			print("  seed ", seed, " ok: ", g.result["reason"])
	total += 1
	if bad == 0:
		print("ALL TESTS PASSED (", total, " cases)")
	else:
		failures += 1
		print("FAILURES: ", failures, " of ", total)
	quit()


func _human_policy(g) -> void:
	var a: Dictionary = g.awaiting
	match a["kind"]:
		"post_draw":
			if a["can_tsumo"]:
				g.human_act({"type": "tsumo"})
			elif not a["ankan"].is_empty():
				g.human_act({"type": "ankan", "tile": a["ankan"][0]})
			else:
				# tsumogiri the drawn tile
				g.human_act({"type": "discard", "tile": a["drawn"], "riichi": false})
		"discard_only":
			var hand: Array = g.players[0]["hand"]
			g.human_act({"type": "discard", "tile": hand[0]})
		"claims_ron":
			g.human_act({"type": "pass"})
		"claims_call":
			g.human_act({"type": "pass"})
