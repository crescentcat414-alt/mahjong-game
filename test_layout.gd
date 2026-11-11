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
	# all three CPU seats must have real estate (the side areas once
	# collapsed to zero width inside the middle row)
	for seat in [1, 2, 3]:
		var r: Rect2 = scene.seat_rivers[seat].get_global_rect()
		if r.size.x < 150 or r.position.x < 0 or r.end.x > win_size.x:
			print("FAIL seat ", seat, " river rect: ", r)
			ok = false
		if r.intersects(hand_rect) or r.intersects(action_rect):
			print("FAIL seat ", seat, " river overlaps hand/actions: ", r)
			ok = false
	if river_rect.intersects(hand_rect):
		print("FAIL human river overlaps hand: ", river_rect)
		ok = false
	if ok:
		print("ALL TESTS PASSED (layout stays on screen, hand bottom=", hand_rect.end.y, ")")
	quit()
