extends SceneTree
## Auto-behaviour tests (master's requests 2026-11-10):
## A) riichi + auto-tsumogiri ON  -> drawn tile is discarded automatically
## B) riichi + tsumo available    -> auto does NOT fire (decision stops)
## C) no_calls ON + pon offer     -> auto-passed
## D) no_calls OFF + right-click  -> offer passed manually
## Run: godot --headless --path <project> --script test_auto.gd

var failures := 0


func check(cond: bool, label: String) -> void:
	if cond:
		print("ok: ", label)
	else:
		failures += 1
		print("FAIL: ", label)


func _init() -> void:
	_run()


func _fresh_scene() -> Control:
	var packed: PackedScene = load("res://main.tscn")
	var scene = packed.instantiate()
	root.add_child(scene)
	return scene


func _run() -> void:
	var scene = await _fresh_scene_ready()
	var g = scene.game

	# --- A: auto-tsumogiri discards after riichi ---
	scene.timer.stop()
	g.players[0]["riichi"] = true
	var drawn: String = g.players[0]["hand"][g.players[0]["hand"].size() - 1]
	g.drawn_tile = drawn
	g.awaiting = {"kind": "post_draw", "can_tsumo": false, "ankan": [], "kakan": [], "kyushu": false}
	var before: int = g.players[0]["discards"].size()
	scene._on_tick()
	check(g.players[0]["discards"].size() == before + 1
		and g.players[0]["discards"][before] == drawn,
		"A auto-tsumogiri discarded the drawn tile")

	# --- B: tsumo available -> auto does not fire ---
	g.awaiting = {"kind": "post_draw", "can_tsumo": true, "ankan": [], "kakan": [], "kyushu": false}
	scene._on_tick()
	check(not g.awaiting.is_empty() and g.awaiting["kind"] == "post_draw",
		"B auto stops when tsumo is available")
	g.awaiting = {}

	# --- C: no_calls auto-passes a pon offer ---
	scene.no_calls = true
	g.claim_from = 1
	g.claim_tile = "chun"
	g.claim_stage = "pon"
	g.awaiting = {"kind": "claims_call", "seat": 0, "tile": "chun", "from": 1,
		"can_pon": true, "can_daiminkan": false, "chi_options": []}
	scene._on_tick()
	check(g.awaiting.is_empty() or not g.awaiting.get("can_pon", false),
		"C no_calls auto-passed the pon offer")

	# --- D: right-click passes when no_calls is off ---
	scene.no_calls = false
	g.claim_from = 2
	g.claim_tile = "haku"
	g.claim_stage = "pon"
	g.awaiting = {"kind": "claims_call", "seat": 0, "tile": "haku", "from": 2,
		"can_pon": true, "can_daiminkan": false, "chi_options": []}
	scene._right_click_pass()
	check(g.awaiting.is_empty() or not g.awaiting.get("can_pon", false),
		"D right-click passed the pon offer")

	if failures == 0:
		print("ALL TESTS PASSED (auto behaviours)")
	else:
		print("FAILURES: ", failures)
	quit()


func _fresh_scene_ready() -> Control:
	var scene = _fresh_scene()
	await process_frame
	await process_frame
	return scene
