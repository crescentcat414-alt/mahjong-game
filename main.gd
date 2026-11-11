extends Control
## Phase 3-4b: playable 4-player table.
## Seat 0 (bottom) is the master; seats 1-3 are CPU (game.gd policies).
## The flow is driven by game.gd's state machine: a timer advances CPU
## turns, and game.awaiting describes the human decision on offer.

const TILE_DIR := "res://assets/tiles/"
const TILE_FILES := {
	"man1": "Man1.png", "man2": "Man2.png", "man3": "Man3.png",
	"man4": "Man4.png", "man5": "Man5.png", "man5r": "Man5-Dora.png",
	"man6": "Man6.png", "man7": "Man7.png", "man8": "Man8.png", "man9": "Man9.png",
	"pin1": "Pin1.png", "pin2": "Pin2.png", "pin3": "Pin3.png",
	"pin4": "Pin4.png", "pin5": "Pin5.png", "pin5r": "Pin5-Dora.png",
	"pin6": "Pin6.png", "pin7": "Pin7.png", "pin8": "Pin8.png", "pin9": "Pin9.png",
	"sou1": "Sou1.png", "sou2": "Sou2.png", "sou3": "Sou3.png",
	"sou4": "Sou4.png", "sou5": "Sou5.png", "sou5r": "Sou5-Dora.png",
	"sou6": "Sou6.png", "sou7": "Sou7.png", "sou8": "Sou8.png", "sou9": "Sou9.png",
	"ton": "Ton.png", "nan": "Nan.png", "shaa": "Shaa.png", "pei": "Pei.png",
	"haku": "Haku.png", "hatsu": "Hatsu.png", "chun": "Chun.png",
	"back": "Back.png",
}
const WIND_NAMES := ["東", "南", "西", "北"]
const YAKU_JA := {
	"riichi": "リーチ", "double_riichi": "ダブルリーチ", "ippatsu": "一発",
	"menzen_tsumo": "門前ツモ", "haitei": "海底撈月", "houtei": "河底撈魚",
	"rinshan": "嶺上開花", "chankan": "槍槓", "pinfu": "平和", "tanyao": "断ヤオ九",
	"chiitoitsu": "七対子", "chanta": "混全帯ヤオ九", "junchan": "純全帯ヤオ九",
	"honroutou": "混老頭", "ikkitsuukan": "一気通貫", "sanshoku_doujun": "三色同順",
	"sanshoku_doukou": "三色同刻", "toitoi": "対々和", "sanankou": "三暗刻", "sankantsu": "三槓子",
	"honitsu": "混一色", "chinitsu": "清一色", "iipeikou": "一盃口",
	"ryanpeikou": "二盃口", "yakuhai": "役牌", "shousangen": "小三元",
	"suuankou": "四暗刻", "kokushi": "国士無双", "daisangen": "大三元",
	"shousuushi": "小四喜", "daisuushi": "大四喜", "tsuuiisou": "字一色",
	"chinroutou": "清老頭", "ryuuiisou": "緑一色", "chuuren": "九蓮宝燈",
	"suukantsu": "四槓子", "dora": "ドラ", "ura_dora": "裏ドラ", "aka_dora": "赤ドラ",
}
const Game := preload("res://game.gd")
const Rules := preload("res://rules.gd")
const Chars := preload("res://characters.gd")
const ROSTER_PATH := "user://characters.json"
const PALETTE := ["#e86a92", "#e8a33d", "#5b8dd9", "#5aa469",
	"#8a6fd6", "#4fb3b0", "#d95b5b", "#888888"]
const TILE_JA := {"ton": "東", "nan": "南", "shaa": "西", "pei": "北", "haku": "白", "hatsu": "發", "chun": "中"}
const SUIT_JA := {"man": "萬", "pin": "筒", "sou": "索"}
const ABORT_JA := {
	"abortive:kyushu": "九種九牌で流局", "abortive:suufon": "四風連打で流局",
	"abortive:suuriichi": "四家立直で流局", "abortive:suukantsu": "四槓散了で流局",
	"abortive:sanchahou": "三家和で流局",
}

var game
var textures: Dictionary = {}
var riichi_mode := false
var auto_tsumogiri := true  # after riichi, discard the drawn tile automatically
var no_calls := false        # auto-pass pon/chi/kan offers (ron still stops)
var label_index := 0  # 0..3 within the current wind (東1局..東4局, then 南)

var info_label: Label
var status_label: Label
var center_label: Label
var dora_box: HBoxContainer
var action_box: HBoxContainer
var result_panel: PanelContainer
var result_label: Label
var riichi_guide_panel: PanelContainer
var riichi_guide_label: Label
var timer: Timer

# character system (Phase 5-revised): roster, per-seat picks, select UI
var roster: Array = []
var match_chars: Array = []
var seat_chips: Array = []
var human_chip: Panel
var select_panel: PanelContainer
var select_cards: HBoxContainer
var editor_panel: PanelContainer
var editor_rows: VBoxContainer
var editor_data: Array = []
var select_open := false

# per-seat UI refs, indexed by seat
var seat_info: Array = []
var seat_rivers: Array = []
var seat_melds: Array = []
var seat_backs: Array = []
var hand_box: HBoxContainer
var human_meld_box: HBoxContainer
var human_river: GridContainer


func _ready() -> void:
	for key in TILE_FILES:
		textures[key] = load(TILE_DIR + TILE_FILES[key])
	game = Game.new()
	game.human_seat = 0
	roster = Chars.load_roster(ROSTER_PATH)
	_build_ui()
	_build_select_ui()
	_new_match()
	timer = Timer.new()
	timer.wait_time = 0.55
	timer.timeout.connect(_on_tick)
	add_child(timer)
	timer.start()


## Place a control at an absolute position on the table (Phase 6 layout:
## no layout containers between regions, so nothing can ever drift).
func _place(ctrl: Control, x: float, y: float, w: float, h: float) -> Control:
	ctrl.position = Vector2(x, y)
	ctrl.size = Vector2(w, h)
	add_child(ctrl)
	return ctrl


func _build_ui() -> void:
	# Majsoul-style layout: a center panel with the round info, the four
	# rivers around it facing the center, the human hand at the bottom.
	# --- top-right controls: options + restart ---
	var topbar := HBoxContainer.new()
	topbar.alignment = BoxContainer.ALIGNMENT_END
	topbar.add_theme_constant_override("separation", 10)
	_place(topbar, 690, 6, 582, 34)
	var diff := OptionButton.new()
	diff.add_item("CPU：弱い", 0)
	diff.add_item("CPU：普通", 1)
	diff.add_item("CPU：強い", 2)
	diff.selected = 1
	diff.item_selected.connect(func(idx: int): game.cpu_difficulty = idx)
	topbar.add_child(diff)
	var auto_cb := CheckBox.new()
	auto_cb.text = "リーチ後オートツモ切り"
	auto_cb.button_pressed = true
	auto_cb.toggled.connect(func(on: bool): auto_tsumogiri = on)
	topbar.add_child(auto_cb)
	var nc_cb := CheckBox.new()
	nc_cb.text = "鳴きなし"
	nc_cb.toggled.connect(func(on: bool): no_calls = on)
	topbar.add_child(nc_cb)
	var restart := Button.new()
	restart.text = "対局を最初から"
	restart.pressed.connect(_new_match)
	topbar.add_child(restart)

	# --- center panel: round info + wall + dora indicators ---
	var panel := PanelContainer.new()
	_place(panel, 470, 226, 340, 250)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 6)
	panel.add_child(pv)
	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 19)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(info_label)
	center_label = Label.new()
	center_label.add_theme_font_size_override("font_size", 17)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(center_label)
	var dora_title := Label.new()
	dora_title.text = "ドラ表示"
	dora_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(dora_title)
	dora_box = HBoxContainer.new()
	dora_box.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_child(dora_box)

	# --- CPU areas: top (seat 2), left (seat 3), right (seat 1) ---
	_build_cpu_area(2, Rect2(460, 42, 360, 24), Rect2(460, 6, 360, 34),
		Rect2(460, 68, 360, 46), Rect2(474, 122, 332, 76), 12)
	_build_cpu_area(3, Rect2(10, 238, 320, 24), Rect2(10, 266, 320, 34),
		Rect2(10, 304, 320, 46), Rect2(10, 362, 176, 168), 6)
	_build_cpu_area(1, Rect2(950, 238, 320, 24), Rect2(950, 266, 320, 34),
		Rect2(950, 304, 320, 46), Rect2(1094, 362, 176, 168), 6)

	# --- human area: river, actions, hand, melds, status ---
	human_river = GridContainer.new()
	human_river.columns = 12
	human_river.add_theme_constant_override("h_separation", 4)
	human_river.add_theme_constant_override("v_separation", 4)
	_place(human_river, 438, 498, 404, 94)
	action_box = HBoxContainer.new()
	action_box.alignment = BoxContainer.ALIGNMENT_END
	action_box.add_theme_constant_override("separation", 8)
	_place(action_box, 640, 600, 632, 38)
	hand_box = HBoxContainer.new()
	hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	hand_box.add_theme_constant_override("separation", 3)
	_place(hand_box, 150, 644, 880, 84)
	human_meld_box = HBoxContainer.new()
	human_meld_box.alignment = BoxContainer.ALIGNMENT_END
	human_meld_box.add_theme_constant_override("separation", 6)
	_place(human_meld_box, 1052, 650, 220, 72)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.clip_text = true
	_place(status_label, 12, 730, 700, 24)

	# character chips (coloured initial badges) beside each seat's info
	seat_chips = [null, _make_chip(1236, 200), _make_chip(424, 38), _make_chip(10, 200)]
	human_chip = _make_chip(12, 692)

	# result panel is an OVERLAY (centered), never part of the flow,
	# so showing it cannot shift the layout either
	result_panel = PanelContainer.new()
	result_panel.set_anchors_preset(Control.PRESET_CENTER)
	result_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	result_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	result_panel.custom_minimum_size = Vector2(560, 0)
	result_label = Label.new()
	result_label.add_theme_font_size_override("font_size", 17)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_panel.add_child(result_label)
	result_panel.visible = false
	add_child(result_panel)

	# riichi-declare guide: an overlay band above the hand, shown only
	# while the player picks the declaration discard. Like Majsoul, it
	# lists each candidate discard with its waits and remaining count.
	riichi_guide_panel = PanelContainer.new()
	riichi_guide_panel.anchor_left = 0.5
	riichi_guide_panel.anchor_right = 0.5
	riichi_guide_panel.anchor_top = 1.0
	riichi_guide_panel.anchor_bottom = 1.0
	riichi_guide_panel.offset_left = -370.0
	riichi_guide_panel.offset_right = 370.0
	riichi_guide_panel.offset_top = -268.0
	riichi_guide_panel.offset_bottom = -140.0
	riichi_guide_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	riichi_guide_label = Label.new()
	riichi_guide_label.add_theme_font_size_override("font_size", 15)
	riichi_guide_label.clip_text = true
	riichi_guide_panel.add_child(riichi_guide_label)
	riichi_guide_panel.visible = false
	add_child(riichi_guide_panel)


## Build one CPU seat's absolutely-positioned area: info label, tile
## backs, melds and river, each in its own fixed rect (Phase 6 layout).
func _build_cpu_area(seat: int, info_r: Rect2, backs_r: Rect2,
		melds_r: Rect2, river_r: Rect2, cols: int) -> void:
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 15)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(info, info_r.position.x, info_r.position.y, info_r.size.x, info_r.size.y)
	var backs := HBoxContainer.new()
	backs.alignment = BoxContainer.ALIGNMENT_CENTER
	backs.add_theme_constant_override("separation", 2)
	_place(backs, backs_r.position.x, backs_r.position.y, backs_r.size.x, backs_r.size.y)
	var melds := HBoxContainer.new()
	melds.alignment = BoxContainer.ALIGNMENT_CENTER
	melds.add_theme_constant_override("separation", 6)
	_place(melds, melds_r.position.x, melds_r.position.y, melds_r.size.x, melds_r.size.y)
	var river := GridContainer.new()
	river.columns = cols
	river.add_theme_constant_override("h_separation", 4)
	river.add_theme_constant_override("v_separation", 4)
	_place(river, river_r.position.x, river_r.position.y, river_r.size.x, river_r.size.y)
	while seat_info.size() <= seat:
		seat_info.append(null)
		seat_rivers.append(null)
		seat_melds.append(null)
		seat_backs.append(null)
	seat_info[seat] = info
	seat_rivers[seat] = river
	seat_melds[seat] = melds
	seat_backs[seat] = backs


func _new_match() -> void:
	# (re)opens the character select; the match starts on a pick
	select_open = true
	editor_panel.visible = false
	_rebuild_select_cards()
	select_panel.visible = true


func _pick_character(char_id: String) -> void:
	var me: Dictionary = {}
	for ch in roster:
		if ch["id"] == char_id:
			me = ch
			break
	if me.is_empty() and not roster.is_empty():
		me = roster[0]
	match_chars = [me]
	for p in Chars.cpu_picks(roster, str(me.get("id", "")), randi()):
		match_chars.append(p)
	while match_chars.size() < 4:
		match_chars.append({"id": "cpu", "name": "CPU", "color": "#888888", "icon": ""})
	select_open = false
	select_panel.visible = false
	_apply_chips()
	_begin_match()


func _begin_match() -> void:
	game.scores = [25000, 25000, 25000, 25000]
	game.dealer = 0
	game.round_wind = 27
	game.honba = 0
	game.sticks = 0
	label_index = 0
	_start_round()


func _make_chip(x: float, y: float) -> Panel:
	var chip := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(8)
	sb.bg_color = Color("#888888")
	chip.add_theme_stylebox_override("panel", sb)
	var lab := Label.new()
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", 17)
	lab.set_anchors_preset(Control.PRESET_FULL_RECT)
	chip.add_child(lab)
	_place(chip, x, y, 34, 34)
	return chip


func _set_chip(chip: Panel, ch: Dictionary) -> void:
	if chip == null:
		return
	var sb := chip.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	sb.bg_color = Color(str(ch.get("color", "#888888")))
	chip.add_theme_stylebox_override("panel", sb)
	(chip.get_child(0) as Label).text = str(ch.get("name", "?")).left(1)


func _apply_chips() -> void:
	if match_chars.size() < 4:
		return
	_set_chip(human_chip, match_chars[0])
	for seat in [1, 2, 3]:
		_set_chip(seat_chips[seat], match_chars[seat])


func _build_select_ui() -> void:
	select_panel = PanelContainer.new()
	select_panel.set_anchors_preset(Control.PRESET_CENTER)
	select_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	select_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	select_panel.custom_minimum_size = Vector2(680, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	select_panel.add_child(v)
	var title := Label.new()
	title.text = "キャラクターを選んでね"
	title.add_theme_font_size_override("font_size", 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	select_cards = HBoxContainer.new()
	select_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	select_cards.add_theme_constant_override("separation", 10)
	v.add_child(select_cards)
	var edit_btn := Button.new()
	edit_btn.text = "キャラクターを編集する"
	edit_btn.pressed.connect(_open_editor)
	v.add_child(edit_btn)
	select_panel.visible = false
	add_child(select_panel)

	editor_panel = PanelContainer.new()
	editor_panel.set_anchors_preset(Control.PRESET_CENTER)
	editor_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	editor_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	editor_panel.custom_minimum_size = Vector2(560, 0)
	var ev := VBoxContainer.new()
	ev.add_theme_constant_override("separation", 8)
	editor_panel.add_child(ev)
	var et := Label.new()
	et.text = "キャラクター編集（名前とテーマカラー）"
	et.add_theme_font_size_override("font_size", 18)
	ev.add_child(et)
	editor_rows = VBoxContainer.new()
	editor_rows.add_theme_constant_override("separation", 6)
	ev.add_child(editor_rows)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	ev.add_child(btns)
	var add_btn := Button.new()
	add_btn.text = "＋追加"
	add_btn.pressed.connect(_editor_add)
	btns.add_child(add_btn)
	var save_btn := Button.new()
	save_btn.text = "保存して戻る"
	save_btn.pressed.connect(_editor_save)
	btns.add_child(save_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "キャンセル"
	cancel_btn.pressed.connect(_editor_cancel)
	btns.add_child(cancel_btn)
	editor_panel.visible = false
	add_child(editor_panel)


func _rebuild_select_cards() -> void:
	_clear(select_cards)
	for ch in roster:
		select_cards.add_child(_make_card(ch))


func _make_card(ch: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(104, 118)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.16, 0.16, 0.2)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(str(ch["color"]))
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(v)
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(52, 52)
	var csb := StyleBoxFlat.new()
	csb.set_corner_radius_all(26)
	csb.bg_color = Color(str(ch["color"]))
	chip.add_theme_stylebox_override("panel", csb)
	var ini := Label.new()
	ini.text = str(ch["name"]).left(1)
	ini.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ini.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ini.add_theme_font_size_override("font_size", 24)
	ini.set_anchors_preset(Control.PRESET_FULL_RECT)
	chip.add_child(ini)
	v.add_child(chip)
	var nm := Label.new()
	nm.text = str(ch["name"])
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nm)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_pick_character(str(ch["id"])))
	return card


func _open_editor() -> void:
	editor_data = roster.duplicate(true)
	_rebuild_editor_rows()
	select_panel.visible = false
	editor_panel.visible = true


func _rebuild_editor_rows() -> void:
	_clear(editor_rows)
	for i in editor_data.size():
		editor_rows.add_child(_make_editor_row(i))


func _make_editor_row(i: int) -> Control:
	var ch: Dictionary = editor_data[i]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_edit := LineEdit.new()
	name_edit.text = str(ch["name"])
	name_edit.custom_minimum_size = Vector2(200, 0)
	name_edit.max_length = 24
	row.add_child(name_edit)
	var color_opt := OptionButton.new()
	for c in PALETTE:
		color_opt.add_item(c)
	var cur: int = PALETTE.find(str(ch["color"]))
	color_opt.selected = cur if cur >= 0 else PALETTE.size() - 1
	row.add_child(color_opt)
	var del := Button.new()
	del.text = "削除"
	del.pressed.connect(func():
		_harvest_editor()
		editor_data.remove_at(i)
		_rebuild_editor_rows())
	row.add_child(del)
	row.set_meta("name_edit", name_edit)
	row.set_meta("color_opt", color_opt)
	return row


func _harvest_editor() -> void:
	for i in editor_rows.get_child_count():
		if i >= editor_data.size():
			break
		var row: Control = editor_rows.get_child(i)
		editor_data[i]["name"] = (row.get_meta("name_edit") as LineEdit).text
		editor_data[i]["color"] = PALETTE[(row.get_meta("color_opt") as OptionButton).selected]


func _editor_add() -> void:
	_harvest_editor()
	editor_data.append({"id": "char_" + str(Time.get_ticks_msec() % 100000000),
		"name": "新規キャラ", "color": PALETTE[editor_data.size() % PALETTE.size()],
		"icon": ""})
	_rebuild_editor_rows()


func _editor_save() -> void:
	_harvest_editor()
	var cleaned: Array = Chars.sanitize_roster(editor_data)
	if not cleaned.is_empty():
		roster = cleaned
		Chars.save_roster(ROSTER_PATH, roster)
	editor_panel.visible = false
	_new_match()


func _editor_cancel() -> void:
	editor_panel.visible = false
	_new_match()


func _start_round() -> void:
	riichi_mode = false
	result_panel.visible = false
	var seed_value := int(Time.get_ticks_msec() % 100000000)
	game.start_round(seed_value)
	game.advance()
	_refresh()


func _on_tick() -> void:
	if select_open:
		return
	if not game.result.is_empty():
		return
	if not game.awaiting.is_empty():
		_auto_actions()
		return
	game.advance()
	_refresh()


## Optional hands-free behaviours for the human seat:
## - no_calls: pon/chi/kan offers are passed automatically (ron offers are
##   a different awaiting kind and always stop for a decision).
## - auto_tsumogiri: after riichi, discard the drawn tile automatically,
##   but stop when a tsumo win or a kan decision is on the table.
func _auto_actions() -> void:
	var a: Dictionary = game.awaiting
	if a["kind"] == "claims_call" and no_calls:
		game.human_act({"type": "pass"})
		_refresh()
	elif a["kind"] == "post_draw" and auto_tsumogiri and game.players[0]["riichi"]:
		if not a["can_tsumo"] and a["ankan"].is_empty() and a["kakan"].is_empty():
			game.human_act({"type": "discard", "tile": game.drawn_tile, "riichi": false})
			_refresh()


## Right-click = pass a call/ron offer (or cancel riichi declaration mode).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_right_click_pass()


func _right_click_pass() -> void:
	if game == null:
		return
	if game.awaiting.is_empty():
		if riichi_mode:
			riichi_mode = false
			_refresh()
		return
	var kind: String = game.awaiting["kind"]
	if kind == "claims_call" or kind == "claims_ron":
		game.human_act({"type": "pass"})
		_refresh()


# ---------------- refresh ----------------

func _tile_rect(tile: String, size: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = textures[tile]
	r.custom_minimum_size = size
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	return r


func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _refresh() -> void:
	if game.players.is_empty():
		return
	# info / center
	var round_name: String = ("東" if game.round_wind == 27 else "南") + str(label_index + 1) + "局"
	info_label.text = "%s　%d本場　供託 %d本" % [round_name, game.honba, game.sticks]
	center_label.text = "山：残り %d 枚" % game.live.size()
	_clear(dora_box)
	for idx in game.dora_indicators():
		dora_box.add_child(_tile_rect(game._tile_name(idx), Vector2(36, 54)))
	# seats
	for seat in 4:
		var p: Dictionary = game.players[seat]
		var wind: String = WIND_NAMES[(seat - game.dealer + 4) % 4]
		var turn_mark := " ▶" if game.turn == seat and game.result.is_empty() else ""
		var riichi_mark := " リーチ" if p["riichi"] else ""
		if seat == 0:
			pass
		else:
			var disp: String = "CPU%d" % seat
			if match_chars.size() == 4:
				disp = str(match_chars[seat]["name"])
			seat_info[seat].text = "%s（%s家） %d点%s%s" % [disp, wind, p["score"], riichi_mark, turn_mark]
			_clear(seat_backs[seat])
			for i in p["hand"].size():
				seat_backs[seat].add_child(_tile_rect("back", Vector2(20, 30)))
			_refresh_river(seat_rivers[seat], p["discards"],
				Vector2(24, 36) if seat == 2 else Vector2(26, 39))
			_refresh_melds(seat_melds[seat], p["melds"])
	# human
	var hp: Dictionary = game.players[0]
	_refresh_river(human_river, hp["discards"], Vector2(30, 45))
	_refresh_melds(human_meld_box, hp["melds"])
	_refresh_hand(hp)
	_refresh_status(hp)
	_update_riichi_guide(hp)
	_refresh_actions()
	if not game.result.is_empty():
		_show_result()


func _refresh_river(grid: GridContainer, discards: Array, size: Vector2) -> void:
	_clear(grid)
	for t in discards:
		grid.add_child(_tile_rect(t, size))


func _refresh_melds(box: HBoxContainer, melds: Array) -> void:
	_clear(box)
	for m in melds:
		var one := HBoxContainer.new()
		one.add_theme_constant_override("separation", 1)
		for t in m["tiles"]:
			if m["kind"] == "kan_closed" and (t == m["tiles"][0] or t == m["tiles"][3]):
				one.add_child(_tile_rect("back", Vector2(24, 36)))
			else:
				one.add_child(_tile_rect(t, Vector2(24, 36)))
		box.add_child(one)


func _refresh_hand(hp: Dictionary) -> void:
	_clear(hand_box)
	var hand: Array = hp["hand"].duplicate()
	# during the human's post-draw phase show the drawn tile set apart
	var drawn := ""
	if not game.awaiting.is_empty() and game.awaiting.get("kind") == "post_draw":
		drawn = game.drawn_tile
		hand.erase(drawn)
	hand.sort_custom(func(a, b): return game._sort_key(a) < game._sort_key(b))
	for t in hand:
		_add_hand_tile(t, false)
	if drawn != "":
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(10, 0)
		hand_box.add_child(spacer)
		_add_hand_tile(drawn, true)


func _add_hand_tile(tile: String, is_drawn: bool) -> void:
	var r := _tile_rect(tile, Vector2(50, 75))
	if is_drawn:
		r.modulate = Color(1, 1, 0.85)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	r.gui_input.connect(_on_hand_gui_input.bind(tile))
	hand_box.add_child(r)


func _refresh_status(hp: Dictionary) -> void:
	var counts := Rules.counts_from_tiles(hp["hand"])
	var meld_n: int = hp["melds"].size()
	# hand here may hold 14 tiles right after a draw; shanten is for 13/10/..
	var tiles_n := counts_total(counts)
	var sh: int
	if tiles_n % 3 == 2:
		# just drew: report the best shanten over all discards
		sh = 99
		for i in 34:
			if counts[i] > 0:
				var c: Array = counts.duplicate()
				c[i] -= 1
				sh = mini(sh, Rules.shanten_for(c, meld_n))
	else:
		sh = Rules.shanten_for(counts, meld_n)
	var wind: String = WIND_NAMES[(0 - game.dealer + 4) % 4]
	var my_name := "あなた"
	if match_chars.size() == 4:
		my_name = str(match_chars[0]["name"])
	var txt := "%s（%s家） %d点" % [my_name, wind, hp["score"]]
	if hp["riichi"]:
		txt += "　リーチ中"
	elif sh == 0:
		var waits: Array = []
		if tiles_n % 3 == 1:
			waits = Rules.winning_tiles_for(counts, meld_n)
		var names: Array = []
		for w in waits:
			names.append(_tile_ja(game._tile_name(w)))
		txt += "　テンパイ！ 待ち：" + "・".join(names)
	elif sh > 0 and sh < 90:
		txt += "　%d向聴" % sh
	status_label.text = txt


## Show/hide the riichi-declare guide overlay and fill it with the
## candidate discards, their waits and the remaining tile counts.
func _update_riichi_guide(hp: Dictionary) -> void:
	var show: bool = riichi_mode and not hp["riichi"] and not game.awaiting.is_empty() \
		and game.awaiting["kind"] == "post_draw"
	riichi_guide_panel.visible = show
	if not show:
		return
	var counts := Rules.counts_from_tiles(hp["hand"])
	riichi_guide_label.text = "リーチ宣言：切る牌を選んでね\n" \
		+ _riichi_discard_guide(counts, hp["melds"].size())


func _riichi_discard_guide(counts: Array, meld_n: int) -> String:
	# visible tiles: every discard and meld on the table + dora indicators
	var visible: Array = []
	visible.resize(34)
	for i in 34:
		visible[i] = 0
	for s in 4:
		for t in game.players[s]["discards"]:
			visible[Rules.tile_index(t)] += 1
		for m in game.players[s]["melds"]:
			for t in m["tiles"]:
				visible[Rules.tile_index(t)] += 1
	for idx in game.dora_indicators():
		visible[idx] += 1
	var lines: Array = []
	for i in 34:
		if counts[i] == 0:
			continue
		var c: Array = counts.duplicate()
		c[i] -= 1
		if Rules.shanten_for(c, meld_n) != 0:
			continue
		var waits: Array = Rules.winning_tiles_for(c, meld_n)
		var names: Array = []
		var left := 0
		for w in waits:
			names.append(_tile_ja(game._tile_name(w)))
			left += maxi(0, 4 - c[w] - visible[w])
		lines.append("%s切り → 待ち %s（あと%d枚）" % [
			_tile_ja(game._tile_name(i)), "・".join(names), left])
	return "\n".join(lines)


func counts_total(counts: Array) -> int:
	var n := 0
	for v in counts:
		n += v
	return n


func _tile_ja(name: String) -> String:
	if TILE_JA.has(name):
		return TILE_JA[name]
	for s in SUIT_JA:
		if name.begins_with(s):
			return name.trim_prefix(s).trim_suffix("r") + SUIT_JA[s]
	return name


# ---------------- human actions ----------------

func _on_hand_gui_input(event: InputEvent, tile: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_right_click_pass()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_tile_clicked(tile)


func _can_act_on_hand() -> bool:
	if game.awaiting.is_empty():
		return false
	var kind: String = game.awaiting["kind"]
	return kind == "post_draw" or kind == "discard_only"


func _on_tile_clicked(tile: String) -> void:
	if not _can_act_on_hand():
		return
	var hp: Dictionary = game.players[0]
	if hp["riichi"]:
		# after riichi only the drawn tile may be discarded
		if tile != game.drawn_tile:
			return
		game.human_act({"type": "discard", "tile": tile, "riichi": false})
	elif riichi_mode:
		if _is_riichi_discard(tile):
			riichi_mode = false
			game.human_act({"type": "discard", "tile": tile, "riichi": true})
		else:
			status_label.text = "その牌だとテンパイしないよ。別の牌か、リーチをやめてね"
			return
	else:
		game.human_act({"type": "discard", "tile": tile, "riichi": false})
	_refresh()


func _is_riichi_discard(tile: String) -> bool:
	var hp: Dictionary = game.players[0]
	if hp["riichi"] or hp["score"] < 1000:
		return false
	for m in hp["melds"]:
		if m["kind"] != "kan_closed":
			return false
	var counts := Rules.counts_from_tiles(hp["hand"])
	counts[Rules.tile_index(tile)] -= 1
	return Rules.shanten_for(counts, hp["melds"].size()) == 0


func _can_declare_riichi() -> bool:
	var hp: Dictionary = game.players[0]
	if game.awaiting.is_empty() or game.awaiting["kind"] != "post_draw":
		return false
	for t in hp["hand"]:
		if _is_riichi_discard(t):
			return true
	return false


func _refresh_actions() -> void:
	_clear(action_box)
	if not game.result.is_empty():
		var next_btn := Button.new()
		next_btn.text = "次の局へ"
		next_btn.pressed.connect(_on_next_round)
		action_box.add_child(next_btn)
		return
	if game.awaiting.is_empty():
		return
	var a: Dictionary = game.awaiting
	match a["kind"]:
		"post_draw":
			if a["can_tsumo"]:
				_add_action("ツモ！", func(): game.human_act({"type": "tsumo"}))
			for t in a["ankan"]:
				_add_action("暗槓（%s）" % _tile_ja(game._tile_name(t)),
					func(): game.human_act({"type": "ankan", "tile": t}))
			for t in a["kakan"]:
				_add_action("加槓（%s）" % _tile_ja(game._tile_name(t)),
					func(): game.human_act({"type": "kakan", "tile": t}))
			if a["kyushu"]:
				_add_action("九種九牌（流局）", func(): game.human_act({"type": "kyushu"}))
			if _can_declare_riichi():
				var rb := Button.new()
				rb.text = "リーチする" if not riichi_mode else "リーチやめる"
				rb.pressed.connect(func():
					riichi_mode = not riichi_mode
					status_label.text = "リーチ宣言する牌をクリックしてね" if riichi_mode else ""
					_refresh_actions())
				action_box.add_child(rb)
		"claims_ron":
			_add_action("ロン！", func(): game.human_act({"type": "ron"}))
			_add_action("見送る", func(): game.human_act({"type": "pass"}))
		"claims_call":
			if a["can_pon"]:
				_add_action("ポン", func(): game.human_act({"type": "pon"}))
			if a["can_daiminkan"]:
				_add_action("大明槓", func(): game.human_act({"type": "daiminkan"}))
			for start in a["chi_options"]:
				_add_action("チー（%s）" % _seq_label(start),
					func(): game.human_act({"type": "chi", "start": start}))
			_add_action("見送る", func(): game.human_act({"type": "pass"}))


func _add_action(text: String, fn: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(func():
		fn.call()
		riichi_mode = false
		_refresh())
	action_box.add_child(b)


func _seq_label(start: int) -> String:
	return "%d%d%d" % [start % 9 + 1, start % 9 + 2, start % 9 + 3]


# ---------------- result ----------------

func _show_result() -> void:
	var r: Dictionary = game.result
	var lines: Array = []
	var reason: String = r["reason"]
	if reason == "tsumo" or reason == "ron" or reason == "double_ron":
		var winners: Array = [r["winner"]] if r.has("winner") else r["winners"]
		for w in winners:
			var who := "あなた" if w == 0 else "CPU%d" % w
			var ev: Dictionary = r.get("ev", {})
			if winners.size() > 1:
				ev = game.can_ron(w, Rules.tile_index(game.claim_tile), {}, game.claim_tile) if reason != "tsumo" else ev
			var yaku_txt: Array = []
			for y in ev.get("yaku", []):
				yaku_txt.append("%s %d" % [YAKU_JA.get(y["name"], y["name"]), y["han"]])
			var head := ""
			if ev.get("yakuman", 0) > 0:
				head = "役満" if ev["yakuman"] == 1 else "%d倍役満" % ev["yakuman"]
			else:
				head = "%d翻 %d符" % [ev.get("han", 0), ev.get("fu", 0)]
			lines.append("%s の%s！ %s（%s）" % [who, "ツモ" if reason == "tsumo" else "ロン", head, "、".join(yaku_txt)])
	elif reason == "ryuukyoku":
		var ten: Array = []
		for s in 4:
			if r["tenpai"][s]:
				ten.append("あなた" if s == 0 else "CPU%d" % s)
		lines.append("流局。テンパイ：%s" % ("・".join(ten) if not ten.is_empty() else "なし（全員ノーテン）"))
	elif reason.begins_with("abortive"):
		lines.append(ABORT_JA.get(reason, "途中流局"))
	var score_line: Array = []
	for s in 4:
		score_line.append("%s %d" % ["あなた" if s == 0 else "CPU%d" % s, game.scores[s]])
	lines.append("　".join(score_line))
	result_label.text = "\n".join(lines)
	result_panel.visible = true


func _on_next_round() -> void:
	var ns: Dictionary = game.next_round_state()
	var dealer_changed: bool = ns["dealer"] != game.dealer
	game.dealer = ns["dealer"]
	game.honba = ns["honba"]
	game.sticks = ns["sticks"]
	if dealer_changed:
		label_index += 1
		if label_index >= 4:
			label_index = 0
			if game.round_wind == 27:
				game.round_wind = 28
			else:
				_show_final_standings()
				return
	_start_round()


func _show_final_standings() -> void:
	var order: Array = [0, 1, 2, 3]
	order.sort_custom(func(a, b): return game.scores[a] > game.scores[b])
	var lines: Array = ["対局終了！最終順位"]
	for i in 4:
		var s: int = order[i]
		lines.append("%d位　%s　%d点" % [i + 1, "あなた" if s == 0 else "CPU%d" % s, game.scores[s]])
	result_label.text = "\n".join(lines)
	result_panel.visible = true
	_clear(action_box)
	var again := Button.new()
	again.text = "新しい対局"
	again.pressed.connect(_new_match)
	action_box.add_child(again)
