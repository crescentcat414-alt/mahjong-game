extends RefCounted
## Mahjong rules (Phase 3-2): hand decomposition, yaku detection, fu and score.
## Works on the 34-slot count arrays from rules.gd.
##
## Meld format (fixed sets outside the closed hand):
##   {"kind": "chi"|"pon"|"kan_open"|"kan_closed", "tile": <lowest/base tile index>}
## evaluate() arguments:
##   closed_counts: 34 counts of the closed part INCLUDING the winning tile
##   melds: Array of meld dicts (may be empty)
##   win_tile: tile index of the winning tile (must be in the closed part)
##   ctx: {is_tsumo, seat_wind (27-30), round_wind (27-30), riichi, double_riichi,
##         ippatsu, haitei, houtei, rinshan, chankan}
## Result dict: {valid, yaku: [{name, han}], han, fu, yakuman, score}
##   score for ron: {"ron": points}; tsumo dealer: {"all": points};
##   tsumo non-dealer: {"dealer": points, "other": points}.

const Rules := preload("res://rules.gd")

const DRAGONS := [31, 32, 33]
const WINDS := [27, 28, 29, 30]


static func _is_terminal(i: int) -> bool:
	return i < 27 and (i % 9 == 0 or i % 9 == 8)


static func _is_th(i: int) -> bool:
	return i >= 27 or _is_terminal(i)


static func _is_simple(i: int) -> bool:
	return not _is_th(i)


# ---------- decomposition of the closed part ----------

static func decompositions(counts: Array) -> Array:
	var out: Array = []
	_decomp(counts.duplicate(), [], -1, out)
	return out


static func _decomp(c: Array, sets: Array, pair: int, out: Array) -> void:
	var i := 0
	while i < 34 and c[i] == 0:
		i += 1
	if i == 34:
		if pair != -1:
			out.append({"sets": sets.duplicate(), "pair": pair})
		return
	if c[i] >= 3:
		c[i] -= 3
		sets.append(["trip", i])
		_decomp(c, sets, pair, out)
		sets.pop_back()
		c[i] += 3
	if i < 27 and i % 9 <= 6 and c[i + 1] > 0 and c[i + 2] > 0:
		c[i] -= 1
		c[i + 1] -= 1
		c[i + 2] -= 1
		sets.append(["seq", i])
		_decomp(c, sets, pair, out)
		sets.pop_back()
		c[i] += 1
		c[i + 1] += 1
		c[i + 2] += 1
	if pair == -1 and c[i] >= 2:
		c[i] -= 2
		_decomp(c, sets, i, out)
		c[i] += 2


# ---------- scoring table ----------

static func _ceil100(x: int) -> int:
	return int((x + 99) / 100) * 100


static func score_points(han: int, fu: int, yakuman_count: int, is_dealer: bool, is_tsumo: bool) -> Dictionary:
	var base := 0
	if yakuman_count > 0:
		base = 8000 * yakuman_count
	else:
		base = fu * int(pow(2, 2 + han))
		if han >= 13:
			base = 8000
		elif han >= 11:
			base = 6000
		elif han >= 8:
			base = 4000
		elif han >= 6:
			base = 3000
		elif han >= 5 or (han == 4 and fu >= 40) or (han == 3 and fu >= 70):
			base = 2000
	if is_tsumo:
		if is_dealer:
			return {"all": _ceil100(2 * base)}
		return {"dealer": _ceil100(2 * base), "other": _ceil100(base)}
	if is_dealer:
		return {"ron": _ceil100(6 * base)}
	return {"ron": _ceil100(4 * base)}


# ---------- main evaluation ----------

## Count dora in a full 14-tile count array (closed + melds) from indicators.
static func count_dora(full: Array, indicators: Array) -> int:
	var n := 0
	for ind in indicators:
		n += full[Rules.next_tile_index(ind)]
	return n


static func evaluate(closed_counts: Array, melds: Array, win_tile: int, ctx: Dictionary) -> Dictionary:
	var is_tsumo: bool = ctx.get("is_tsumo", false)
	var seat_wind: int = ctx.get("seat_wind", 27)
	var round_wind: int = ctx.get("round_wind", 27)
	var is_dealer := seat_wind == 27
	var is_closed := melds.all(func(m): return m["kind"] == "kan_closed")

	# full counts (closed + melds) for pattern checks
	var full: Array = closed_counts.duplicate()
	for m in melds:
		var t: int = m["tile"]
		match m["kind"]:
			"chi":
				full[t] += 1
				full[t + 1] += 1
				full[t + 2] += 1
			"pon":
				full[t] += 3
			_:
				full[t] += 4

	# yakuman patterns that do not need decomposition
	var ym := _yakuman_special(full, closed_counts, melds, win_tile, ctx)
	if ym > 0:
		# suuankou can stack on top of pattern yakuman (e.g. suuankou + tsuuiisou)
		for decomp in decompositions(closed_counts):
			var cand := _eval_decomp(decomp, melds, full, win_tile, ctx, is_closed)
			if cand.get("yakuman", 0) > 0:
				ym += cand["yakuman"]
				break
		return {"valid": true, "yaku": [{"name": "yakuman", "han": 0}], "han": 0,
			"fu": 0, "yakuman": ym,
			"score": score_points(0, 0, ym, is_dealer, is_tsumo)}

	# seven pairs candidate (closed only)
	var best: Dictionary = {"valid": false}
	if melds.is_empty() and Rules.shanten_chiitoi(closed_counts) == -1:
		var yaku: Array = [{"name": "chiitoitsu", "han": 2}]
		_add_context_yaku(yaku, ctx, is_closed, true)
		var han := _han_sum(yaku)
		var sc := score_points(han, 25, 0, is_dealer, is_tsumo)
		best = {"valid": true, "yaku": yaku, "han": han, "fu": 25, "yakuman": 0, "score": sc}

	for decomp in decompositions(closed_counts):
		var cand := _eval_decomp(decomp, melds, full, win_tile, ctx, is_closed)
		if not cand.get("valid", false):
			continue
		if not best.get("valid", false) or _score_value(cand["score"]) > _score_value(best["score"]):
			best = cand
	if best.get("valid", false):
		_apply_dora(best, full, ctx, is_dealer, is_tsumo)
	return best


## Dora / ura-dora / red fives add han (never a yaku by themselves).
## ctx keys: dora_indicators, ura_indicators (tile indices), red_count.
static func _apply_dora(result: Dictionary, full: Array, ctx: Dictionary, is_dealer: bool, is_tsumo: bool) -> void:
	var d := count_dora(full, ctx.get("dora_indicators", []))
	var u := 0
	if ctx.get("riichi", false) or ctx.get("double_riichi", false):
		u = count_dora(full, ctx.get("ura_indicators", []))
	var r: int = ctx.get("red_count", 0)
	if d > 0:
		result["yaku"].append({"name": "dora", "han": d})
	if u > 0:
		result["yaku"].append({"name": "ura_dora", "han": u})
	if r > 0:
		result["yaku"].append({"name": "aka_dora", "han": r})
	result["dora"] = d + u + r
	if d + u + r > 0:
		result["han"] += d + u + r
		result["score"] = score_points(result["han"], result["fu"], 0, is_dealer, is_tsumo)


static func _score_value(score: Dictionary) -> int:
	if score.has("ron"):
		return score["ron"]
	if score.has("all"):
		return score["all"] * 3
	return score.get("dealer", 0) + score.get("other", 0) * 2


static func _han_sum(yaku: Array) -> int:
	var s := 0
	for y in yaku:
		s += y["han"]
	return s


static func _add_context_yaku(yaku: Array, ctx: Dictionary, is_closed: bool, _is_chii: bool) -> void:
	var has_riichi: bool = ctx.get("double_riichi", false) or ctx.get("riichi", false)
	if is_closed and ctx.get("double_riichi", false):
		yaku.append({"name": "double_riichi", "han": 2})
	elif is_closed and ctx.get("riichi", false):
		yaku.append({"name": "riichi", "han": 1})
	if has_riichi and ctx.get("ippatsu", false):
		yaku.append({"name": "ippatsu", "han": 1})
	if ctx.get("is_tsumo", false) and is_closed:
		yaku.append({"name": "menzen_tsumo", "han": 1})
	if ctx.get("haitei", false):
		yaku.append({"name": "haitei", "han": 1})
	if ctx.get("houtei", false):
		yaku.append({"name": "houtei", "han": 1})
	if ctx.get("rinshan", false):
		yaku.append({"name": "rinshan", "han": 1})
	if ctx.get("chankan", false):
		yaku.append({"name": "chankan", "han": 1})


static func _yakuman_special(full: Array, closed_counts: Array, melds: Array, win_tile: int, ctx: Dictionary) -> int:
	var total := 0
	# thirteen orphans (closed only); 13-wait counts double
	if melds.is_empty() and Rules.shanten_kokushi(closed_counts) == -1:
		var pre: Array = closed_counts.duplicate()
		pre[win_tile] -= 1
		var kinds := 0
		for i in Rules.TERMINAL_HONOR_INDICES:
			if pre[i] > 0:
				kinds += 1
		total += 2 if kinds == 13 else 1
	# four kans
	var kan_count := 0
	for m in melds:
		if m["kind"].begins_with("kan"):
			kan_count += 1
	if kan_count == 4:
		total += 1
	# four winds: big four winds counts double; do not also add all-honors
	var wind_trips := 0
	for wnd in WINDS:
		if full[wnd] >= 3:
			wind_trips += 1
	var is_daisuushi := wind_trips == 4
	if is_daisuushi:
		total += 2  # daisuushi counts double
	# all honors / all terminals
	var all_honor := true
	var all_terminal := true
	for i in 34:
		if full[i] == 0:
			continue
		if i < 27:
			all_honor = false
		else:
			all_terminal = false
		if _is_simple(i):
			all_honor = false
			all_terminal = false
	if all_honor and not is_daisuushi:
		total += 1
	if all_terminal:
		total += 1
	# big three dragons
	var dragon_trips := 0
	for d in DRAGONS:
		if full[d] >= 3:
			dragon_trips += 1
	if dragon_trips == 3:
		total += 1
	# all green: sou 2,3,4,6,8 and hatsu only
	var green := [20, 21, 22, 24, 26, 32]
	var all_green := true
	for i in 34:
		if full[i] > 0 and not green.has(i):
			all_green = false
	if all_green:
		total += 1
	# nine gates (closed, single suit): pattern 1112345678999 + any tile of the suit
	if melds.is_empty():
		for suit_base in [0, 9, 18]:
			var ok := true
			var cnt := 0
			for k in 9:
				cnt += closed_counts[suit_base + k]
			if cnt != 14:
				continue
			var pat := [3, 1, 1, 1, 1, 1, 1, 1, 3]
			for k in 9:
				if closed_counts[suit_base + k] < pat[k]:
					ok = false
			for i in 34:
				if i < suit_base or i > suit_base + 8:
					if closed_counts[i] > 0:
						ok = false
			if ok:
				var pre2: Array = closed_counts.duplicate()
				pre2[win_tile] -= 1
				var pure := true
				for k in 9:
					if pre2[suit_base + k] != pat[k]:
						pure = false
				total += 2 if pure else 1
	return total


# ---------- one decomposition ----------

static func _eval_decomp(decomp: Dictionary, melds: Array, full: Array, win_tile: int, ctx: Dictionary, is_closed: bool) -> Dictionary:
	var is_tsumo: bool = ctx.get("is_tsumo", false)
	var seat_wind: int = ctx.get("seat_wind", 27)
	var round_wind: int = ctx.get("round_wind", 27)
	var is_dealer := seat_wind == 27

	# unified set list: [kind, tile, open, is_kan]
	var sets: Array = []
	for s in decomp["sets"]:
		sets.append([s[0], s[1], false, false])
	for m in melds:
		match m["kind"]:
			"chi":
				sets.append(["seq", m["tile"], true, false])
			"pon":
				sets.append(["trip", m["tile"], true, false])
			"kan_open":
				sets.append(["trip", m["tile"], true, true])
			"kan_closed":
				sets.append(["trip", m["tile"], false, true])
	var pair_tile: int = decomp["pair"]

	# possible roles of the winning tile inside the closed sets / pair
	var roles: Array = []  # each: {wait: String, win_set: int (-1 = pair)}
	if pair_tile == win_tile:
		roles.append({"wait": "tanki", "win_set": -1})
	for si in sets.size():
		var s: Array = sets[si]
		if s[2]:
			continue  # melds never contain the winning tile
		if s[0] == "trip" and s[1] == win_tile:
			roles.append({"wait": "shanpon", "win_set": si})
		elif s[0] == "seq":
			var st: int = s[1]
			if win_tile == st:
				roles.append({"wait": "penchan" if st % 9 == 6 else "ryanmen", "win_set": si})
			elif win_tile == st + 1:
				roles.append({"wait": "kanchan", "win_set": si})
			elif win_tile == st + 2:
				roles.append({"wait": "penchan" if st % 9 == 0 else "ryanmen", "win_set": si})
	if roles.is_empty():
		return {"valid": false}

	var best: Dictionary = {"valid": false}
	for role in roles:
		var cand := _eval_role(sets, pair_tile, role, full, ctx, is_closed)
		if not cand.get("valid", false):
			continue
		# suuankou: 4 closed triplets; tanki wait counts double yakuman
		if cand.get("ankou", 0) == 4:
			var ym := 1
			if role["wait"] == "tanki":
				ym = 2
			var sc := score_points(0, 0, ym, is_dealer, is_tsumo)
			return {"valid": true, "yaku": [{"name": "suuankou", "han": 0}], "han": 0,
				"fu": cand["fu"], "yakuman": ym, "score": sc}
		if not best.get("valid", false) or _score_value(cand["score"]) > _score_value(best["score"]):
			best = cand
	return best


static func _eval_role(sets: Array, pair_tile: int, role: Dictionary, full: Array, ctx: Dictionary, is_closed: bool) -> Dictionary:
	var is_tsumo: bool = ctx.get("is_tsumo", false)
	var seat_wind: int = ctx.get("seat_wind", 27)
	var round_wind: int = ctx.get("round_wind", 27)
	var is_dealer := seat_wind == 27
	var wait: String = role["wait"]
	var win_set: int = role["win_set"]

	var yaku: Array = []
	_add_context_yaku(yaku, ctx, is_closed, false)

	# ---- fu (also gathers ankou / shape facts) ----
	var fu := 20
	var ankou := 0
	var trips := 0
	var seq_starts: Array = []
	var all_seq := true
	for si in sets.size():
		var s: Array = sets[si]
		var kind: String = s[0]
		var t: int = s[1]
		var open_set: bool = s[2]
		var is_kan: bool = s[3]
		if kind == "seq":
			seq_starts.append(t)
		else:
			all_seq = false
			trips += 1
			var ron_completed := (not is_tsumo) and si == win_set
			var closed_trip := not open_set and not ron_completed
			if closed_trip:
				ankou += 1
			var base_fu := 2
			if _is_th(t):
				base_fu = 4
			if closed_trip:
				base_fu *= 2
			if is_kan:
				base_fu *= 4
			fu += base_fu
	# pair fu
	if DRAGONS.has(pair_tile) or pair_tile == seat_wind or pair_tile == round_wind:
		fu += 4 if (pair_tile == seat_wind and pair_tile == round_wind) else 2
	# wait fu
	if wait == "tanki" or wait == "kanchan" or wait == "penchan":
		fu += 2
	if not is_tsumo and is_closed:
		fu += 10
	if is_tsumo:
		fu += 2

	# ---- shape yaku ----
	# pinfu: all sequences, non-yakuhai pair, ryanmen wait
	var pair_yakuhai := DRAGONS.has(pair_tile) or pair_tile == seat_wind or pair_tile == round_wind
	var is_pinfu_shape := all_seq and not pair_yakuhai and wait == "ryanmen"
	if is_pinfu_shape and is_closed:
		yaku.append({"name": "pinfu", "han": 1})
	# tanyao
	var tanyao := true
	for i in 34:
		if full[i] > 0 and _is_th(i):
			tanyao = false
	if tanyao:
		yaku.append({"name": "tanyao", "han": 1})
	# iipeikou / ryanpeikou (closed only counts for iipeikou; ryanpeikou closed-only yaku)
	if is_closed:
		var sig_count := {}
		for st in seq_starts:
			sig_count[st] = sig_count.get(st, 0) + 1
		var peikou_pairs := 0
		for k in sig_count:
			peikou_pairs += int(sig_count[k] / 2)
		if peikou_pairs >= 2:
			yaku.append({"name": "ryanpeikou", "han": 3})
		elif peikou_pairs == 1:
			yaku.append({"name": "iipeikou", "han": 1})
	# yakuhai triplets
	for s in sets:
		if s[0] == "trip":
			var t: int = s[1]
			if DRAGONS.has(t):
				yaku.append({"name": "yakuhai", "han": 1})
			else:
				if t == seat_wind:
					yaku.append({"name": "yakuhai", "han": 1})
				if t == round_wind:
					yaku.append({"name": "yakuhai", "han": 1})
	# sanshoku doukou (same number triplet in all suits)
	for n in 9:
		if full[n] >= 3 and full[9 + n] >= 3 and full[18 + n] >= 3:
			yaku.append({"name": "sanshoku_doukou", "han": 2})
	# toitoi / sanankou / honroutou
	if trips == 4:
		yaku.append({"name": "toitoi", "han": 2})
	if ankou == 3:
		yaku.append({"name": "sanankou", "han": 2})
	# chantai family / honroutou
	var all_th := true
	var has_seq := false
	var all_terminal_only := true
	for s in sets:
		if s[0] == "seq":
			has_seq = true
			if not _is_terminal(s[1]) and not _is_terminal(s[1] + 2):
				all_th = false
			if s[1] % 9 != 0 and (s[1] + 2) % 9 != 8:
				all_terminal_only = false
		else:
			if not _is_th(s[1]):
				all_th = false
			if not _is_terminal(s[1]):
				all_terminal_only = false
	if not _is_th(pair_tile):
		all_th = false
	if not _is_terminal(pair_tile):
		all_terminal_only = false
	if all_th:
		if not has_seq:
			yaku.append({"name": "honroutou", "han": 2})
		elif all_terminal_only:
			yaku.append({"name": "junchan", "han": 3 if is_closed else 2})
		else:
			yaku.append({"name": "chantai", "han": 2 if is_closed else 1})
	# ikki tsuukan
	for base in [0, 9, 18]:
		if seq_starts.has(base) and seq_starts.has(base + 3) and seq_starts.has(base + 6):
			yaku.append({"name": "ikkitsuukan", "han": 2 if is_closed else 1})
	# sanshoku doujun
	for n in 7:
		if seq_starts.has(n) and seq_starts.has(9 + n) and seq_starts.has(18 + n):
			yaku.append({"name": "sanshoku_doujun", "han": 2 if is_closed else 1})
	# shousuushi (yakuman version handled in special: only daisuushi there)
	var wind_trips := 0
	for s in sets:
		if s[0] == "trip" and WINDS.has(s[1]):
			wind_trips += 1
	if wind_trips == 3 and WINDS.has(pair_tile):
		yaku.append({"name": "shousuushi", "han": 2})
	# honitsu / chinitsu
	var suits_present := {}
	var honors_present := false
	for i in 34:
		if full[i] == 0:
			continue
		if i >= 27:
			honors_present = true
		else:
			suits_present[int(i / 9)] = true
	if suits_present.size() == 1:
		if honors_present:
			yaku.append({"name": "honitsu", "han": 3 if is_closed else 2})
		else:
			yaku.append({"name": "chinitsu", "han": 6 if is_closed else 5})

	if _han_sum(yaku) == 0:
		return {"valid": false}

	# fu finalization
	if is_pinfu_shape:
		fu = 20 if is_tsumo else 30
	else:
		if fu == 20 and not is_closed:
			fu = 30  # open hand, base only -> treated as 30
		fu = int(ceil(fu / 10.0)) * 10
	var han := _han_sum(yaku)
	var sc := score_points(han, fu, 0, is_dealer, is_tsumo)
	return {"valid": true, "yaku": yaku, "han": han, "fu": fu, "yakuman": 0,
		"score": sc, "ankou": ankou}
