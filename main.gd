extends Control
## Phase 2 minimal prototype:
## deal 13 tiles, draw 1, click a hand tile to discard it, then draw again.
## No rules, no winning, no CPU yet -- just the draw/discard loop.

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
}
const SUIT_ORDER := {"man": 0, "pin": 1, "sou": 2}
const HONOR_ORDER := {"ton": 0, "nan": 1, "shaa": 2, "pei": 3, "haku": 4, "hatsu": 5, "chun": 6}
const HAND_TILE_SIZE := Vector2(58, 87)
const RIVER_TILE_SIZE := Vector2(40, 60)

var wall: Array = []
var hand: Array = []
var discards: Array = []
var textures: Dictionary = {}

var info_label: Label
var river_grid: GridContainer
var hand_box: HBoxContainer


func _ready() -> void:
	for key in TILE_FILES:
		textures[key] = load(TILE_DIR + TILE_FILES[key])
	_build_ui()
	start_game()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var top_row := HBoxContainer.new()
	vbox.add_child(top_row)

	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 20)
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(info_label)

	var restart_button := Button.new()
	restart_button.text = "配り直し"
	restart_button.pressed.connect(start_game)
	top_row.add_child(restart_button)

	var river_title := Label.new()
	river_title.text = "河（切った牌）"
	river_title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(river_title)

	river_grid = GridContainer.new()
	river_grid.columns = 14
	river_grid.add_theme_constant_override("h_separation", 4)
	river_grid.add_theme_constant_override("v_separation", 4)
	river_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(river_grid)

	var hand_title := Label.new()
	hand_title.text = "手牌（クリックで切る）"
	hand_title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(hand_title)

	hand_box = HBoxContainer.new()
	hand_box.add_theme_constant_override("separation", 3)
	hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hand_box)


func start_game() -> void:
	wall = _build_wall()
	wall.shuffle()
	hand.clear()
	discards.clear()
	for i in 13:
		hand.append(wall.pop_back())
	hand.sort_custom(_tile_less)
	_draw_tile()


func _build_wall() -> Array:
	var w: Array = []
	for suit in ["man", "pin", "sou"]:
		for n in range(1, 10):
			if n == 5:
				w.append(suit + "5")
				w.append(suit + "5")
				w.append(suit + "5")
				w.append(suit + "5r")
			else:
				for k in 4:
					w.append(suit + str(n))
	for honor in ["ton", "nan", "shaa", "pei", "haku", "hatsu", "chun"]:
		for k in 4:
			w.append(honor)
	return w


func _tile_less(a: String, b: String) -> bool:
	return _sort_key(a) < _sort_key(b)


func _sort_key(tile: String) -> int:
	if HONOR_ORDER.has(tile):
		return 300 + HONOR_ORDER[tile] * 10
	for suit in SUIT_ORDER:
		if tile.begins_with(suit):
			var rest := tile.trim_prefix(suit)
			var num := int(rest)
			var red := 1 if rest.ends_with("r") else 0
			return SUIT_ORDER[suit] * 100 + num * 10 + red
	return 999


func _draw_tile() -> void:
	if wall.is_empty():
		_refresh()
		info_label.text = "山が尽きたよ（流局）。「配り直し」でもう一度どうぞ。"
		return
	hand.append(wall.pop_back())
	_refresh()


func _on_hand_gui_input(event: InputEvent, idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_hand_pressed(idx)


func _on_hand_pressed(index: int) -> void:
	if index < 0 or index >= hand.size():
		return
	discards.append(hand[index])
	hand.remove_at(index)
	hand.sort_custom(_tile_less)
	_draw_tile()


func _refresh() -> void:
	for c in hand_box.get_children():
		hand_box.remove_child(c)
		c.queue_free()
	for i in hand.size():
		var b := TextureRect.new()
		b.texture = textures[hand[i]]
		b.custom_minimum_size = HAND_TILE_SIZE
		b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		b.stretch_mode = TextureRect.STRETCH_SCALE
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		b.gui_input.connect(_on_hand_gui_input.bind(i))
		hand_box.add_child(b)

	for c in river_grid.get_children():
		river_grid.remove_child(c)
		c.queue_free()
	for t in discards:
		var r := TextureRect.new()
		r.texture = textures[t]
		r.custom_minimum_size = RIVER_TILE_SIZE
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		river_grid.add_child(r)

	info_label.text = "山：残り %d 枚　手牌 %d 枚" % [wall.size(), hand.size()]
