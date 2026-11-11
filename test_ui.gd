extends SceneTree
## UI smoke test: instantiate the real table scene, drive the human seat
## through the UI's own handlers, and require the round to finish cleanly.
## Run: godot --headless --path <project> --script test_ui.gd

func _init() -> void:
	_run()


func _run() -> void:
	var packed: PackedScene = load("res://main.tscn")
	if packed == null or not packed.can_instantiate():
		print("FAIL main.tscn failed to load")
		quit()
		return
	var scene = packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene._pick_character("wing")
	await process_frame
	var g = scene.game
	# character system: the pick fills all four seats, seat 0 is Wing,
	# and the seat info shows character names instead of "CPU1" etc.
	if scene.match_chars.size() != 4 or scene.match_chars[0]["name"] != "ウィング":
		print("FAIL character pick did not fill the seats: ", scene.match_chars)
		quit()
		return
	scene._refresh()
	if not scene.seat_info[1].text.begins_with(str(scene.match_chars[1]["name"])):
		print("FAIL seat info does not show the character name: ", scene.seat_info[1].text)
		quit()
		return
	var guard := 0
	while g.result.is_empty() and guard < 6000:
		guard += 1
		scene._on_tick()
		if not g.awaiting.is_empty():
			match g.awaiting["kind"]:
				"post_draw":
					if g.awaiting["can_tsumo"]:
						g.human_act({"type": "tsumo"})
						scene._refresh()
					else:
						scene._on_tile_clicked(g.drawn_tile)
				"discard_only":
					scene._on_tile_clicked(g.players[0]["hand"][0])
				"claims_ron", "claims_call":
					g.human_act({"type": "pass"})
					scene._refresh()
		if guard % 500 == 0:
			await process_frame
	if g.result.is_empty():
		print("FAIL round did not finish")
	else:
		var sum := 0
		for v in g.result["scores"]:
			sum += v
		if sum + g.result["sticks"] * 1000 == 100000:
			print("ALL TESTS PASSED (UI round finished: ", g.result["reason"], ")")
		else:
			print("FAIL points not conserved: sum=", sum)
	quit()
