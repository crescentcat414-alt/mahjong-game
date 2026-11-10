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
	"chiitoi": "七対子", "chanta": "混全帯ヤオ九", "junchan": "純全帯ヤオ九",
	"honroutou": "混老頭", "ikkitsuukan": "一気通貫", "sanshoku_doujun": "三色同順",
	"sanshoku_doukou": "三色同刻", "toitoi": "対々和", "sanankou": "三暗刻",
	"honitsu": "混一色", "chinitsu": "清一色", "iipeikou": "一盃口",
	"ryanpeikou": "二盃口", "yakuhai": "役牌", "shousangen": "小三元",
	"suuankou": "四暗刻", "kokushi": "国士無双", "daisangen": "大三元",
	"shousuushi": "小四喜", "daisuushi": "大四喜", "tsuuiisou": "字一色",
	"chinroutou": "清老頭", "ryuuiisou": "緑一色", "chuuren": "九蓮宝燈",
	"suukantsu": "四槓子", "dora": "ドラ", "ura_dora": "裏ドラ", "aka_dora": "赤ドラ",
}
const Game := preload("res://game.gd")
const Rules := preload("res://rules.gd")
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
var label_index := 0  # 0..3 within the current wind (東1局..東4局, then 南)

var info_label: Label
var status_label: Label
var center_label: Label
var dora_box: HBoxContainer
var action_box: HBoxContainer
var result_panel: PanelContainer
var result_label: Label
var timer: Timer

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
	_build_ui()
	_new_match()
	timer = Timer.new()
	timer.wait_time = 0.55
	timer.timeout.connect(_on_tick)
	add_child(timer)
	timer.start()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	# top row: title/info + new match
	var top := HBoxContainer.new()
	vbox.add_child(top)
	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 18)
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info_label)
	var restart := Button.new()
	restart.text = "対局を最初から"
	restart.pressed.connect(_new_match)
	top.add_child(restart)

	# table area (expands); the hand stays pinned below it
	var table := VBoxContainer.new()
	table.add_theme_constant_override("separation", 4)
	table.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(table)

	# top CPU (seat 2)
	table.add_child(_build_cpu_area(2))
	# middle row: left CPU (seat 3), center, right CPU (seat 1)
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 8)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table.add_child(mid)
	mid.add_child(_build_cpu_area(3))
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(center)
	center_label = Label.new()
	center_label.add_theme_font_size_override("font_size", 17)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(center_label)
	var dora_title := Label.new()
	dora_title.text = "ドラ表示"
	dora_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(dora_title)
	dora_box = HBoxContainer.new()
	dora_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(dora_box)
	mid.add_child(_build_cpu_area(1))

	# human area: river, then melds+hand
	var human_title := Label.new()
	human_title.text = "あなた"
	vbox.add_child(human_title)
	human_river = GridContainer.new()
	human_river.columns = 12
	human_river.add_theme_constant_override("h_separation", 3)
	human_river.add_theme_constant_override("v_separation", 3)
	human_river.custom_minimum_size = Vector2(0, 100)
	human_river.clip_contents = true
	vbox.add_child(human_river)
	var hand_row := HBoxContainer.new()
	hand_row.add_theme_constant_override("separation", 10)
	vbox.add_child(hand_row)
	hand_box = HBoxContainer.new()
	hand_box.add_theme_constant_override("separation", 3)
	hand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_row.add_child(hand_box)
	human_meld_box = HBoxContainer.new()
	human_meld_box.add_theme_constant_override("separation", 6)
	hand_row.add_child(human_meld_box)

	# status + actions + result
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(status_label)
	action_box = HBoxContainer.new()
	action_box.add_theme_constant_override("separation", 8)
	vbox.add_child(action_box)
	result_panel = PanelContainer.new()
	result_label = Label.new()
	result_label.add_theme_font_size_override("font_size", 17)
	result_panel.add_child(result_label)
	result_panel.visible = false
	vbox.add_child(result_panel)


func _build_cpu_area(seat: int) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 15)
	box.add_child(info)
	var backs := HBoxContainer.new()
	backs.add_theme_constant_override("separation", 2)
	box.add_child(backs)
	var river := GridContainer.new()
	river.columns = 6
	river.add_theme_constant_override("h_separation", 3)
	river.add_theme_constant_override("v_separation", 3)
	river.custom_minimum_size = Vector2(0, 96)
	river.clip_contents = true
	box.add_child(river)
	var melds := HBoxContainer.new()
	melds.add_theme_constant_override("separation", 6)
	box.add_child(melds)
	while seat_info.size() <= seat:
		seat_info.append(null)
		seat_rivers.append(null)
		seat_melds.append(null)
		seat_backs.append(null)
	seat_info[seat] = info
	seat_rivers[seat] = river
	seat_melds[seat] = melds
	seat_backs[seat] = backs
	return box


func _new_match() -> void:
	game.scores = [25000, 25000, 25000, 25000]
	game.dealer = 0
	game.round_wind = 27
	game.honba = 0
	game.sticks = 0
	label_index = 0
	_start_round()


func _start_round() -> void:
	riichi_mode = false
	result_panel.visible = false
	var seed_value := int(Time.get_ticks_msec() % 100000000)
	game.start_round(seed_value)
	game.advance()
	_refresh()


func _on_tick() -> void:
	if game.result.is_empty() and game.awaiting.is_empty():
		game.advance()
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
			seat_info[seat].text = "CPU%d（%s家） %d点%s%s" % [seat, wind, p["score"], riichi_mark, turn_mark]
			_clear(seat_backs[seat])
			for i in p["hand"].size():
				seat_backs[seat].add_child(_tile_rect("back", Vector2(22, 33)))
			_refresh_river(seat_rivers[seat], p["discards"], Vector2(30, 45))
			_refresh_melds(seat_melds[seat], p["melds"])
	# human
	var hp: Dictionary = game.players[0]
	_refresh_river(human_river, hp["discards"], Vector2(34, 51))
	_refresh_melds(human_meld_box, hp["melds"])
	_refresh_hand(hp)
	_refresh_status(hp)
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
				one.add_child(_tile_rect("back", Vector2(30, 45)))
			else:
				one.add_child(_tile_rect(t, Vector2(30, 45)))
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
	var r := _tile_rect(tile, Vector2(52, 78))
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
	var txt := "あなた（%s家） %d点" % [wind, hp["score"]]
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
