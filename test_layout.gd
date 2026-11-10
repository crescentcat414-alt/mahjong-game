extends SceneTree
## Layout regression test: with rivers piled high (24 discards each) and a
## full hand, the hand row and the action buttons must stay inside the
## window -- the bug the master found by playtest (hand pushed off screen).
## Run: godot --headless --path <project> --script test_layout.gd

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
	var g = scene.game
	# pile up maximum-length rivers on every seat
	var pile: Array = []
	for i in 24:
		pile.append(g._tile_name(i % 34))
	for seat in 4:
		g.players[seat]["discards"] = pile.duplicate()
	scene._refresh()
	await process_frame
	await process_frame
	var win_size := Vector2(1280, 760)
	var hand_rect: Rect2 = scene.hand_box.get_global_rect()
	var action_rect: Rect2 = scene.action_box.get_global_rect()
	var status_rect: Rect2 = scene.status_label.get_global_rect()
	var ok := true
	if hand_rect.end.y > win_size.y or hand_rect.position.y < 0:
		print("FAIL hand row outside window: ", hand_rect)
		ok = false
	if action_rect.end.y > win_size.y:
		print("FAIL action row outside window: ", action_rect)
		ok = false
	if status_rect.end.y > win_size.y:
		print("FAIL status outside window: ", status_rect)
		ok = false
	# river frames must not exceed their fixed heights either
	var river_rect: Rect2 = scene.human_river.get_global_rect()
	if river_rect.size.y > 106:
		print("FAIL human river frame grew: ", river_rect)
		ok = false
	if ok:
		print("ALL TESTS PASSED (layout stays on screen, hand bottom=", hand_rect.end.y, ")")
	quit()
