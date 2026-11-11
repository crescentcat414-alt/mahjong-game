# Phase 6: Majsoul-style table layout — implementation spec for Claude Code

## Task
Rewrite the table layout in `main.gd` to a Majsoul-style layout: a center
panel with the round info, and the four players' discards arranged around
it, each river between its player and the center. This replaces the
current stacked-rows layout.

## Hard constraints
- Modify ONLY `main.gd`. Do not touch game.gd, rules.gd, yaku.gd,
  project.godot, main.tscn, or any test file.
- Do not change any game logic, function signatures, or the calls into
  game.gd. Only UI construction (where controls are parented and their
  geometry) and the layout-related parts of `_refresh` may change.
- Keep ALL of these member variables with the same names and roles:
  game, timer, textures, riichi_mode, auto_tsumogiri, no_calls,
  info_label, center_label, dora_box, seat_info, seat_backs, seat_rivers,
  seat_melds (arrays by seat), human_river, human_meld_box, hand_box,
  status_label, action_box, result_panel, result_label,
  riichi_guide_panel, riichi_guide_label, label_index.
- seat_rivers[seat] and human_river MUST remain GridContainer instances
  (the layout test reads their rects). Hand tiles stay children of
  hand_box. Keep functions: _ready, _build_ui, _fixed_frame (may become
  unused for table regions), _new_match, _start_round, _on_tick,
  _auto_actions, _unhandled_input, _right_click_pass, _refresh,
  _refresh_river, _refresh_melds, _refresh_hand, _refresh_status,
  _update_riichi_guide, _riichi_discard_guide, counts_total, _tile_ja,
  _on_hand_gui_input, _on_tile_clicked, _refresh_actions, _add_action,
  _show_result, _tile_rect, _clear.
- GDScript: `:=` cannot infer types from Variant values (dictionary
  access, untyped array elements) — use explicit types there. A parse
  error in a headless test script makes the process hang forever, so if
  a test run hangs, check for parse errors first.

## Layout design (canvas 1280x760, absolute positioning)
Use plain Controls with explicit positions/sizes set in code (anchors +
offsets, or position/size). Do NOT use VBox/HBox containers for the
table regions — container minimum-size feedback loops caused the drift
bugs this layout replaces. Every region below must stay inside
1280x760 even when every river holds 24 discards.

- Center panel: PanelContainer at approx (470,255)-(810,485). Inside it
  (a VBox is fine INSIDE the panel): info_label (round/honba/sticks),
  center_label (wall remaining), a "ドラ表示" caption, dora_box.
- Human (seat 0, bottom):
  - hand_box: bottom center, y 648..728. Hand tiles 50x75 (drawn tile
    separated by a gap, as now).
  - human_river: GridContainer, columns=12, tile size 30x45, centered
    horizontally, y approx 520..620 (2 rows of discards).
  - human_meld_box: bottom-right corner, approx x 1000..1272,
    y 648..724.
  - status_label: bottom-left, approx x 12..480, y 696..728.
  - action_box: right side above the melds, approx x 800..1272,
    y 600..644, right-aligned.
- CPU2 (seat 2, top): seat_backs row centered at top (tiles 20x30,
  y 10..44); seat_info[2] centered at y 48..74; seat_melds[2] centered
  at y 78..114; seat_rivers[2]: GridContainer columns=12, tile 24x36,
  centered, y 150..250 (discards grow toward the center panel).
- CPU3 (seat 3, left block x 10..330, y 220..540, stacked top to
  bottom): seat_info[3], seat_backs[3] (a row of 20x30 backs),
  seat_melds[3], seat_rivers[3]: GridContainer columns=6, tile 26x39
  (up to 4 rows).
- CPU1 (seat 1, right block x 950..1270, y 220..540): same structure as
  seat 3, mirrored.
- Top bar: restart button + the two option checkboxes
  （リーチ後オートツモ切り / 鳴きなし） in the top-right corner,
  approx x 830..1272, y 8..42. Keep their existing behaviour/wiring.
- result_panel and riichi_guide_panel overlays: keep exactly as they
  are now.

## Verification (must do before finishing)
Run every test with the console Godot and make them all pass:
  E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe --headless --path . --script test_rules.gd
  ... same for test_yaku.gd, test_phase33.gd, test_game.gd,
  test_human.gd, test_ui.gd, test_layout.gd, test_auto.gd
Each must print "ALL TESTS PASSED". test_layout asserts the hand,
action box and status stay on screen with full rivers and that every
seat's river rect is at least 150px wide and on screen.
Do NOT commit anything with git. Leave the change in the working tree
and end with a short summary of what you changed and the test results.
