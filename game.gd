extends RefCounted
## Mahjong game flow (Phase 3-4): one full round (kyoku) as a step-driven
## state machine. With human_seat = -1 every seat is CPU-driven and a whole
## round can be simulated headlessly (play_auto_round). With a human seat,
## advance() stops at that seat's decisions (see `awaiting`) and the UI
## resumes the flow with human_act(). Rules/math live in rules.gd / yaku.gd.
##
## Player state: {hand: Array[String] closed tiles, melds: Array,
##   discards: Array[String], riichi: bool, ippatsu: bool,
##   furiten_temp: bool, furiten_riichi: bool, score: int, first_turn: bool}
## Meld: {"kind": "chi"|"pon"|"kan_open"|"kan_closed", "tile": index,
##        "tiles": Array[String], "from": seat}

const Rules := preload("res://rules.gd")
const Yaku := preload("res://yaku.gd")
const SORT_HONOR := {"ton": 0, "nan": 1, "shaa": 2, "pei": 3, "haku": 4, "hatsu": 5, "chun": 6}
const SORT_SUIT := {"man": 0, "pin": 1, "sou": 2}
const WINDS_IDX := [27, 28, 29, 30]

var scores: Array = [25000, 25000, 25000, 25000]
var round_wind := 27
var dealer := 0
var honba := 0
var sticks := 0  # riichi sticks on the table (1000 each)
var human_seat := -1

var players: Array = []
var live: Array = []       # drawable wall (pop_back draws)
var dead: Array = []       # 14 dead-wall tiles: rinshan 0-3, indicators 4..
var rinshan_ptr := 0
var kan_count := 0
var any_calls := false
var result: Dictionary = {}

# flow state
var phase := "idle"  # draw | post_draw | discard_only | claims | done
var turn := 0
var drawn_tile := ""
var drawn_from_rinshan := false
var pending_rinshan := false
var claim_tile := ""
var claim_from := -1
var claim_kind := "discard"  # discard | kakan | ankan
var claim_stage := "ron"     # ron | pon | chi | complete_kan | next
var claim_was_riichi := false
var kan_seat := -1
var kan_pending_tile := ""
var awaiting: Dictionary = {}
var steps := 0

var _rng := RandomNumberGenerator.new()


# ---------------- setup ----------------

func start_round(seed_value: int) -> void:
	_rng.seed = seed_value
	players.clear()
	for s in 4:
		players.append({
			"hand": [], "melds": [], "discards": [], "riichi": false,
			"ippatsu": false, "furiten_temp": false, "furiten_riichi": false,
			"score": scores[s], "first_turn": true,
		})
	var wall := _build_wall()
	live = wall.slice(0, 122)
	dead = wall.slice(122, 136)
	rinshan_ptr = 0
	kan_count = 0
	turn = dealer
	any_calls = false
	result = {}
	phase = "draw"
	drawn_tile = ""
	pending_rinshan = false
	awaiting = {}
	steps = 0
	for s in 4:
		for i in 13:
			players[s]["hand"].append(live.pop_back())
		_sort_hand(players[s]["hand"])


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
	# Fisher-Yates with our seeded RNG
	for i in range(w.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = w[i]
		w[i] = w[j]
		w[j] = tmp
	return w


func _sort_key(tile: String) -> int:
	if SORT_HONOR.has(tile):
		return 300 + SORT_HONOR[tile] * 10
	for suit in SORT_SUIT:
		if tile.begins_with(suit):
			var rest := tile.trim_prefix(suit)
			return SORT_SUIT[suit] * 100 + int(rest) * 10 + (1 if rest.ends_with("r") else 0)
	return 999


func _sort_hand(h: Array) -> void:
	h.sort_custom(func(a, b): return _sort_key(a) < _sort_key(b))


func dora_indicators() -> Array:
	var out: Array = []
	for k in kan_count + 1:
		out.append(Rules.tile_index(dead[4 + 2 * k]))
	return out


func ura_indicators() -> Array:
	var out: Array = []
	for k in kan_count + 1:
		out.append(Rules.tile_index(dead[5 + 2 * k]))
	return out


# ---------------- legality ----------------

func _counts(seat: int) -> Array:
	return Rules.counts_from_tiles(players[seat]["hand"])


static func legal_pon(hand_counts: Array, tile_idx: int) -> bool:
	return hand_counts[tile_idx] >= 2


## Chi options (sequence start indices). Caller must check the discarder
## is the seat to the left; this only looks at the hand.
static func legal_chi(hand_counts: Array, tile_idx: int) -> Array:
	var out: Array = []
	if tile_idx >= 27:
		return out
	var n := tile_idx % 9
	if n >= 2 and hand_counts[tile_idx - 2] > 0 and hand_counts[tile_idx - 1] > 0:
		out.append(tile_idx - 2)
	if n >= 1 and n <= 7 and hand_counts[tile_idx - 1] > 0 and hand_counts[tile_idx + 1] > 0:
		out.append(tile_idx - 1)
	if n <= 6 and hand_counts[tile_idx + 1] > 0 and hand_counts[tile_idx + 2] > 0:
		out.append(tile_idx)
	return out


## Kan options from the hand itself: {"ankan": [tile...], "kakan": [tile...]}
func legal_kans(seat: int) -> Dictionary:
	var c := _counts(seat)
	var ankan: Array = []
	for i in 34:
		if c[i] == 4:
			ankan.append(i)
	var kakan: Array = []
	for m in players[seat]["melds"]:
		if m["kind"] == "pon" and c[m["tile"]] > 0:
			kakan.append(m["tile"])
	return {"ankan": ankan, "kakan": kakan}


static func legal_daiminkan(hand_counts: Array, tile_idx: int) -> bool:
	return hand_counts[tile_idx] >= 3


## Nine kinds of terminals/honors in the first uninterrupted turn.
static func kyushu_kinds(hand_tiles: Array) -> int:
	var seen := {}
	for t in hand_tiles:
		var idx := Rules.tile_index(t)
		if Rules.TERMINAL_HONOR_INDICES.has(idx):
			seen[idx] = true
	return seen.size()


# ---------------- win checking ----------------

func _seat_wind(seat: int) -> int:
	return 27 + (seat - dealer + 4) % 4


func _red_count(seat: int) -> int:
	var n := 0
	for t in players[seat]["hand"]:
		if str(t).ends_with("r"):
			n += 1
	for m in players[seat]["melds"]:
		for t in m["tiles"]:
			if str(t).ends_with("r"):
				n += 1
	return n


func _win_ctx(seat: int, is_tsumo: bool, extra: Dictionary) -> Dictionary:
	var ctx: Dictionary = {
		"is_tsumo": is_tsumo,
		"seat_wind": _seat_wind(seat),
		"round_wind": round_wind,
		"riichi": players[seat]["riichi"],
		"ippatsu": players[seat]["ippatsu"],
		"dora_indicators": dora_indicators(),
		"ura_indicators": ura_indicators(),
		"red_count": _red_count(seat),
	}
	for k in extra:
		ctx[k] = extra[k]
	return ctx


## Can `seat` ron `tile_idx` discarded by someone else right now?
## tile_str is the actual discarded tile string (for red-five accounting).
func can_ron(seat: int, tile_idx: int, extra: Dictionary = {}, tile_str: String = "") -> Dictionary:
	var p: Dictionary = players[seat]
	if p["furiten_riichi"]:
		return {"valid": false}
	if p["furiten_temp"]:
		return {"valid": false}
	var c := _counts(seat)
	# fast path: the tile must complete the hand, and no wait may be in
	# the player's own discards (furiten)
	var waits := Rules.winning_tiles_for(c, p["melds"].size())
	if not waits.has(tile_idx):
		return {"valid": false}
	for w in waits:
		if _discard_indices(seat).has(w):
			return {"valid": false}
	var ex: Dictionary = extra.duplicate()
	if tile_str.ends_with("r"):
		ex["red_count"] = _red_count(seat) + 1
	var closed: Array = []
	closed.assign(players[seat]["hand"])
	closed.append(_tile_name(tile_idx))
	var cc := Rules.counts_from_tiles(closed)
	var ev: Dictionary = Yaku.evaluate(cc, p["melds"], tile_idx, _win_ctx(seat, false, ex))
	return ev


func can_tsumo(seat: int, drawn_idx: int, extra: Dictionary = {}) -> Dictionary:
	var cc := _counts(seat)
	return Yaku.evaluate(cc, players[seat]["melds"], drawn_idx, _win_ctx(seat, true, extra))


func _discard_indices(seat: int) -> Array:
	var out: Array = []
	for t in players[seat]["discards"]:
		out.append(Rules.tile_index(t))
	return out


## Find an actual tile string in hand matching an index (prefer plain over red).
func _find_tile(seat: int, tile_idx: int) -> String:
	var red := ""
	for t in players[seat]["hand"]:
		if Rules.tile_index(t) == tile_idx:
			if not str(t).ends_with("r"):
				return t
			red = t
	return red


func _tile_name(tile_idx: int) -> String:
	# canonical (non-red) name for an index
	if tile_idx >= 27:
		return ["ton", "nan", "shaa", "pei", "haku", "hatsu", "chun"][tile_idx - 27]
	var suit: String = ["man", "pin", "sou"][int(tile_idx / 9)]
	return suit + str(tile_idx % 9 + 1)


func _remove_from_hand(seat: int, tile_name: String) -> void:
	var h: Array = players[seat]["hand"]
	h.erase(tile_name)


# ---------------- payments ----------------

func _apply_win(winners: Array, from_seat: int, is_tsumo: bool) -> void:
	# winners: [{seat, ev}] ; from_seat = discarder for ron, winner seat for tsumo
	for w in winners:
		var seat: int = w["seat"]
		var ev: Dictionary = w["ev"]
		var sc: Dictionary = ev["score"]
		var gain := sticks * 1000
		sticks = 0
		if is_tsumo:
			if sc.has("all"):
				for s in 4:
					if s != seat:
						players[s]["score"] -= sc["all"] + honba * 100
						gain += sc["all"] + honba * 100
			else:
				for s in 4:
					if s != seat:
						var pay: int = (sc["dealer"] if s == dealer else sc["other"]) + honba * 100
						players[s]["score"] -= pay
						gain += pay
		else:
			var pay: int = sc["ron"] + honba * 300
			players[from_seat]["score"] -= pay
			gain += pay
		players[seat]["score"] += gain
	for s in 4:
		scores[s] = players[s]["score"]


func _finish(reason: String, extra: Dictionary = {}) -> Dictionary:
	result = {"reason": reason, "scores": scores.duplicate(), "sticks": sticks, "honba": honba}
	for k in extra:
		result[k] = extra[k]
	phase = "done"
	awaiting = {}
	return result


# ---------------- CPU policy ----------------

func _cpu_choose_discard(seat: int) -> Dictionary:
	# returns {tile: String, riichi: bool}
	var p: Dictionary = players[seat]
	var hand: Array = p["hand"]
	var c := Rules.counts_from_tiles(hand)
	var meld_n: int = p["melds"].size()
	# pass 1: shanten only (cheap); pass 2: ukeire only among the best
	var cand_shanten := {}
	var min_sh := 99
	var seen0 := {}
	for t in hand:
		if seen0.has(t):
			continue
		seen0[t] = true
		var cc0: Array = c.duplicate()
		cc0[Rules.tile_index(t)] -= 1
		var sh0 := Rules.shanten_for(cc0, meld_n)
		cand_shanten[t] = sh0
		if sh0 < min_sh:
			min_sh = sh0
	var best_tile := ""
	var best_score := 1e9
	var best_riichi := false
	for t in cand_shanten:
		if cand_shanten[t] != min_sh:
			continue
		var cc: Array = c.duplicate()
		cc[Rules.tile_index(t)] -= 1
		var ukeire := 0
		if min_sh >= 0:
			ukeire = Rules.effective_tiles_for(cc, meld_n).size()
		var score := min_sh * 100.0 - ukeire
		if score < best_score:
			best_score = score
			best_tile = t
			best_riichi = min_sh == 0 and meld_n == 0 and p["score"] >= 1000 and not p["riichi"]
	return {"tile": best_tile, "riichi": best_riichi}


# ---------------- flow: advance / steps ----------------

func play_auto_round() -> Dictionary:
	advance()
	while result.is_empty() and steps < 4000:
		advance()
	return result if not result.is_empty() else _finish("abortive:too_many_actions")


## Run steps until the round ends or a human decision is needed.
func advance() -> void:
	while result.is_empty() and awaiting.is_empty() and steps < 4000:
		steps += 1
		_step()


func _step() -> void:
	match phase:
		"draw":
			_step_draw()
		"post_draw":
			_step_post_draw()
		"discard_only":
			_step_discard_only()
		"claims":
			_step_claims()


func _step_draw() -> void:
	var seat := turn
	var p: Dictionary = players[seat]
	p["furiten_temp"] = false
	if pending_rinshan:
		pending_rinshan = false
		drawn_from_rinshan = true
		drawn_tile = dead[rinshan_ptr]
		rinshan_ptr += 1
		p["hand"].append(drawn_tile)
		phase = "post_draw"
		return
	drawn_from_rinshan = false
	if live.is_empty():
		_exhaustive_draw()
		return
	drawn_tile = live.pop_back()
	p["hand"].append(drawn_tile)
	phase = "post_draw"


func _step_post_draw() -> void:
	var seat := turn
	var p: Dictionary = players[seat]
	var drawn_idx := Rules.tile_index(drawn_tile)
	var extra := {}
	if drawn_from_rinshan:
		extra["rinshan"] = true
	if live.is_empty() and not drawn_from_rinshan:
		extra["haitei"] = true
	var ev := can_tsumo(seat, drawn_idx, extra)
	var kans := legal_kans(seat)
	var can_kyushu: bool = p["first_turn"] and not any_calls and kyushu_kinds(p["hand"]) >= 9
	if seat == human_seat:
		awaiting = {
			"kind": "post_draw", "seat": seat,
			"can_tsumo": ev.get("valid", false), "tsumo_ev": ev,
			"ankan": kans["ankan"], "kakan": kans["kakan"],
			"kyushu": can_kyushu, "drawn": drawn_tile,
		}
		return
	# CPU
	if ev.get("valid", false):
		_apply_win([{"seat": seat, "ev": ev}], seat, true)
		_finish("tsumo", {"winner": seat, "ev": ev})
		return
	if can_kyushu:
		_finish("abortive:kyushu", {})
		return
	if not kans["ankan"].is_empty():
		_declare_ankan(seat, kans["ankan"][0])
		return
	if not kans["kakan"].is_empty():
		_declare_kakan(seat, kans["kakan"][0])
		return
	_cpu_discard(seat)


func _step_discard_only() -> void:
	var seat := turn
	if seat == human_seat:
		awaiting = {"kind": "discard_only", "seat": seat}
		return
	_cpu_discard(seat)


func _cpu_discard(seat: int) -> void:
	var p: Dictionary = players[seat]
	if p["riichi"]:
		_do_discard(seat, drawn_tile if phase == "post_draw" else p["hand"][p["hand"].size() - 1], false)
		return
	_sort_hand(p["hand"])
	var choice := _cpu_choose_discard(seat)
	_do_discard(seat, choice["tile"], choice["riichi"])


func _do_discard(seat: int, tile: String, declare_riichi: bool) -> void:
	var p: Dictionary = players[seat]
	_remove_from_hand(seat, tile)
	p["discards"].append(tile)
	p["first_turn"] = false
	claim_was_riichi = false
	if declare_riichi and not p["riichi"]:
		p["riichi"] = true
		p["ippatsu"] = true
		claim_was_riichi = true
		p["score"] -= 1000
		scores[seat] = p["score"]
		sticks += 1
	elif p["ippatsu"]:
		# ippatsu window closes after the riichi player's next discard
		p["ippatsu"] = false
	claim_tile = tile
	claim_from = seat
	claim_kind = "discard"
	claim_stage = "ron"
	phase = "claims"


# ---------------- claims ----------------

func _step_claims() -> void:
	match claim_stage:
		"ron":
			_claims_ron_stage()
		"pon":
			_claims_pon_stage()
		"chi":
			_claims_chi_stage()
		"complete_kan":
			_complete_kan()
		"next":
			_claims_next()


func _ron_candidates() -> Dictionary:
	# {cpu_winners: [{seat, ev}], human_ev: Dictionary or {}}
	var tile_idx := Rules.tile_index(claim_tile)
	var out := {"cpu_winners": [], "human_ev": {}}
	for k in range(1, 4):
		var s := (claim_from + k) % 4
		if s == kan_seat and claim_kind != "discard":
			continue  # the kan declarer cannot ron their own kan tile
		var extra := {}
		if claim_kind != "discard":
			extra["chankan"] = true
		if claim_kind == "discard" and live.is_empty():
			extra["houtei"] = true
		var ev := can_ron(s, tile_idx, extra, claim_tile)
		if not ev.get("valid", false):
			continue
		if claim_kind == "ankan":
			# only a kokushi can ron a closed kan
			var has_kokushi := false
			for y in ev.get("yaku", []):
				if y["name"] == "kokushi":
					has_kokushi = true
			if not has_kokushi:
				continue
		if s == human_seat:
			out["human_ev"] = ev
		else:
			out["cpu_winners"].append({"seat": s, "ev": ev})
	return out


func _claims_ron_stage() -> void:
	var cands := _ron_candidates()
	var human_ev: Dictionary = cands["human_ev"]
	if not human_ev.is_empty():
		awaiting = {
			"kind": "claims_ron", "seat": human_seat, "tile": claim_tile,
			"from": claim_from, "ev": human_ev, "chankan": claim_kind != "discard",
		}
		return
	_resolve_ron_winners(cands["cpu_winners"])


func _resolve_ron_winners(winners: Array) -> void:
	if winners.size() >= 3:
		_finish("abortive:sanchahou", {})
		return
	if not winners.is_empty():
		_apply_win(winners, claim_from, false)
		var seats: Array = winners.map(func(w): return w["seat"])
		_finish("ron" if winners.size() == 1 else "double_ron",
			{"winners": seats, "from": claim_from, "ev": winners[0]["ev"]})
		return
	# nobody ronned: four riichi / four winds abortives trigger now
	if claim_kind == "discard" and claim_was_riichi and _all_riichi():
		_finish("abortive:suuriichi", {})
		return
	if claim_kind == "discard" and _check_four_winds():
		_finish("abortive:suufon", {})
		return
	claim_stage = "pon" if claim_kind == "discard" else "complete_kan"


func _claims_pon_stage() -> void:
	var tile_idx := Rules.tile_index(claim_tile)
	# find the (unique) pon/daiminkan claimant
	var claimant := -1
	var is_kan := false
	for k in range(1, 4):
		var s := (claim_from + k) % 4
		if players[s]["riichi"]:
			continue
		var c := _counts(s)
		if legal_daiminkan(c, tile_idx):
			claimant = s
			is_kan = true
			break
		if legal_pon(c, tile_idx):
			claimant = s
			is_kan = false
			break
	if claimant == -1:
		claim_stage = "chi"
		return
	if claimant == human_seat:
		awaiting = {
			"kind": "claims_call", "seat": human_seat, "tile": claim_tile,
			"from": claim_from, "can_pon": not is_kan, "can_daiminkan": is_kan,
			"chi_options": [],
		}
		return
	# CPU policy: call if it does not raise shanten
	var c2 := _counts(claimant)
	var meld_n: int = players[claimant]["melds"].size()
	var before := Rules.shanten_for(c2, meld_n)
	var cc: Array = c2.duplicate()
	cc[tile_idx] -= 3 if is_kan else 2
	if Rules.shanten_for(cc, meld_n + 1) <= before:
		if is_kan:
			_do_daiminkan(claimant, claim_from, claim_tile)
		else:
			_do_pon(claimant, claim_from, claim_tile)
	else:
		claim_stage = "chi"


func _claims_chi_stage() -> void:
	var tile_idx := Rules.tile_index(claim_tile)
	var nxt := (claim_from + 1) % 4
	if players[nxt]["riichi"]:
		claim_stage = "next"
		return
	var c := _counts(nxt)
	var opts := legal_chi(c, tile_idx)
	if opts.is_empty():
		claim_stage = "next"
		return
	if nxt == human_seat:
		awaiting = {
			"kind": "claims_call", "seat": human_seat, "tile": claim_tile,
			"from": claim_from, "can_pon": false, "can_daiminkan": false,
			"chi_options": opts,
		}
		return
	# CPU policy: chi if it lowers shanten
	var meld_n: int = players[nxt]["melds"].size()
	var before := Rules.shanten_for(c, meld_n)
	var start: int = opts[0]
	var cc: Array = c.duplicate()
	for d in [0, 1, 2]:
		if start + d != tile_idx:
			cc[start + d] -= 1
	if Rules.shanten_for(cc, meld_n + 1) < before:
		_do_chi(nxt, claim_from, claim_tile, start)
	else:
		claim_stage = "next"


func _claims_next() -> void:
	turn = (claim_from + 1) % 4
	phase = "draw"


func _all_riichi() -> bool:
	for s in 4:
		if not players[s]["riichi"]:
			return false
	return true


func _check_four_winds() -> bool:
	if any_calls:
		return false
	for s in 4:
		if players[s]["discards"].size() != 1:
			return false
	var first := Rules.tile_index(players[0]["discards"][0])
	if not WINDS_IDX.has(first):
		return false
	for s in 4:
		if Rules.tile_index(players[s]["discards"][0]) != first:
			return false
	return true


# ---------------- meld actions ----------------

func _do_pon(seat: int, from_seat: int, tile: String) -> void:
	any_calls = true
	_clear_all_ippatsu()
	var idx := Rules.tile_index(tile)
	var used: Array = [tile]
	for k in 2:
		var t := _find_tile(seat, idx)
		_remove_from_hand(seat, t)
		used.append(t)
	players[seat]["melds"].append({"kind": "pon", "tile": idx, "tiles": used, "from": from_seat})
	players[from_seat]["discards"].pop_back()
	turn = seat
	phase = "discard_only"


func _do_chi(seat: int, from_seat: int, tile: String, start: int) -> void:
	any_calls = true
	_clear_all_ippatsu()
	var used: Array = [tile]
	for d in [0, 1, 2]:
		var ti: int = start + d
		if ti != Rules.tile_index(tile):
			var t := _find_tile(seat, ti)
			_remove_from_hand(seat, t)
			used.append(t)
	players[seat]["melds"].append({"kind": "chi", "tile": start, "tiles": used, "from": from_seat})
	players[from_seat]["discards"].pop_back()
	turn = seat
	phase = "discard_only"


func _do_daiminkan(seat: int, from_seat: int, tile: String) -> void:
	any_calls = true
	_clear_all_ippatsu()
	var idx := Rules.tile_index(tile)
	var used: Array = [tile]
	for k in 3:
		var t := _find_tile(seat, idx)
		_remove_from_hand(seat, t)
		used.append(t)
	players[seat]["melds"].append({"kind": "kan_open", "tile": idx, "tiles": used, "from": from_seat})
	players[from_seat]["discards"].pop_back()
	turn = seat
	_after_kan(seat)


func _declare_ankan(seat: int, tile_idx: int) -> void:
	any_calls = true
	_clear_all_ippatsu()
	var used: Array = []
	for k in 4:
		var t := _find_tile(seat, tile_idx)
		_remove_from_hand(seat, t)
		used.append(t)
	players[seat]["melds"].append({"kind": "kan_closed", "tile": tile_idx, "tiles": used, "from": seat})
	kan_seat = seat
	kan_pending_tile = ""
	claim_tile = _tile_name(tile_idx)
	claim_from = seat
	claim_kind = "ankan"
	claim_stage = "ron"
	claim_was_riichi = false
	phase = "claims"


func _declare_kakan(seat: int, tile_idx: int) -> void:
	any_calls = true
	kan_seat = seat
	kan_pending_tile = _find_tile(seat, tile_idx)
	_remove_from_hand(seat, kan_pending_tile)
	claim_tile = kan_pending_tile
	claim_from = seat
	claim_kind = "kakan"
	claim_stage = "ron"
	claim_was_riichi = false
	phase = "claims"


func _complete_kan() -> void:
	if claim_kind == "kakan":
		_clear_all_ippatsu()
		for m in players[kan_seat]["melds"]:
			if m["kind"] == "pon" and m["tile"] == Rules.tile_index(kan_pending_tile):
				m["kind"] = "kan_open"
				m["tiles"].append(kan_pending_tile)
				break
	_after_kan(kan_seat)


func _after_kan(seat: int) -> void:
	kan_count += 1
	if kan_count == 4:
		var owners := {}
		for s in 4:
			for m in players[s]["melds"]:
				if str(m["kind"]).begins_with("kan"):
					owners[s] = true
		if owners.size() > 1:
			_finish("abortive:suukantsu", {})
			return
	# move one live tile to the dead wall end (keeps the dead wall at 14)
	if not live.is_empty():
		live.pop_back()
	turn = seat
	pending_rinshan = true
	phase = "draw"


func _clear_all_ippatsu() -> void:
	for s in 4:
		players[s]["ippatsu"] = false


# ---------------- human actions ----------------

func human_act(action: Dictionary) -> void:
	if awaiting.is_empty():
		return
	var kind: String = awaiting["kind"]
	var was_pon_offer: bool = awaiting.get("can_pon", false) or awaiting.get("can_daiminkan", false)
	var seat := human_seat
	awaiting = {}
	match kind:
		"post_draw":
			match str(action.get("type", "")):
				"tsumo":
					var extra := {}
					if drawn_from_rinshan:
						extra["rinshan"] = true
					if live.is_empty() and not drawn_from_rinshan:
						extra["haitei"] = true
					var ev := can_tsumo(seat, Rules.tile_index(drawn_tile), extra)
					if ev.get("valid", false):
						_apply_win([{"seat": seat, "ev": ev}], seat, true)
						_finish("tsumo", {"winner": seat, "ev": ev})
				"kyushu":
					_finish("abortive:kyushu", {})
				"ankan":
					_declare_ankan(seat, int(action["tile"]))
				"kakan":
					_declare_kakan(seat, int(action["tile"]))
				"discard":
					_do_discard(seat, str(action["tile"]), bool(action.get("riichi", false)))
		"discard_only":
			if action.get("type") == "discard":
				_do_discard(seat, str(action["tile"]), false)
		"claims_ron":
			if action.get("type") == "ron":
				var cands := _ron_candidates()
				var winners: Array = cands["cpu_winners"]
				winners.append({"seat": seat, "ev": cands["human_ev"]})
				_resolve_ron_winners(winners)
			else:  # pass: furiten applies
				var p: Dictionary = players[seat]
				if p["riichi"]:
					p["furiten_riichi"] = true
				else:
					p["furiten_temp"] = true
				var cands2 := _ron_candidates()
				_resolve_ron_winners(cands2["cpu_winners"])
		"claims_call":
			match str(action.get("type", "")):
				"pon":
					_do_pon(seat, claim_from, claim_tile)
				"daiminkan":
					_do_daiminkan(seat, claim_from, claim_tile)
				"chi":
					_do_chi(seat, claim_from, claim_tile, int(action["start"]))
				"pass":
					# passing a pon/daiminkan offer still allows the chi stage;
					# passing a chi offer ends the claims for this discard
					claim_stage = "chi" if was_pon_offer else "next"
	advance()


# ---------------- round end ----------------

func _exhaustive_draw() -> void:
	var tenpai: Array = []
	for s in 4:
		var c := _counts(s)
		tenpai.append(Rules.shanten_for(c, players[s]["melds"].size()) == 0)
	var n := 0
	for t in tenpai:
		if t:
			n += 1
	if n > 0 and n < 4:
		var gain := 3000 / n
		var lose := 3000 / (4 - n)
		for s in 4:
			players[s]["score"] += gain if tenpai[s] else -lose
			scores[s] = players[s]["score"]
	honba += 1
	_finish("ryuukyoku", {"tenpai": tenpai})


## Compute the next round's dealer/honba after a finished round.
func next_round_state() -> Dictionary:
	var dealer_keeps := false
	var reason: String = result.get("reason", "")
	if reason.begins_with("abortive"):
		dealer_keeps = true  # abortive draws replay the round with the same dealer
	elif reason == "tsumo" or reason == "ron" or reason == "double_ron":
		var winners: Array = []
		if result.has("winner"):
			winners = [result["winner"]]
		elif result.has("winners"):
			winners = result["winners"]
		dealer_keeps = winners.has(dealer)
	elif reason == "ryuukyoku":
		dealer_keeps = result["tenpai"][dealer]
	var nd := dealer
	var nh := honba
	if dealer_keeps:
		nh += 1
	else:
		nd = (dealer + 1) % 4
		if reason.begins_with("abortive"):
			nh += 1
	return {"dealer": nd, "honba": nh, "sticks": sticks}
