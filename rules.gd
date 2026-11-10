extends RefCounted
## Mahjong rules core (Phase 3-1): tile counting, shanten, win detection, waits.
## Closed-hand only for now (melds are handled in Phase 3-4).
## Tiles use the same string ids as main.gd: "man1".."man9", "man5r" (red five),
## "pin*", "sou*", and honors "ton","nan","shaa","pei","haku","hatsu","chun".
## Internally a hand is a 34-slot count array:
##   man 0-8, pin 9-17, sou 18-26, honors 27-33 (ton..chun).

const HONOR_INDEX := {
	"ton": 27, "nan": 28, "shaa": 29, "pei": 30,
	"haku": 31, "hatsu": 32, "chun": 33,
}
const TERMINAL_HONOR_INDICES := [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33]


static func tile_index(tile: String) -> int:
	if HONOR_INDEX.has(tile):
		return HONOR_INDEX[tile]
	var base := 0
	var rest := tile
	if tile.begins_with("pin"):
		base = 9
		rest = tile.trim_prefix("pin")
	elif tile.begins_with("sou"):
		base = 18
		rest = tile.trim_prefix("sou")
	else:
		rest = tile.trim_prefix("man")
	return base + int(rest) - 1


static func counts_from_tiles(tiles: Array) -> Array:
	var counts: Array = []
	counts.resize(34)
	for i in 34:
		counts[i] = 0
	for t in tiles:
		counts[tile_index(t)] += 1
	return counts


static func shanten(counts: Array) -> int:
	var s := shanten_standard(counts)
	s = mini(s, shanten_chiitoi(counts))
	s = mini(s, shanten_kokushi(counts))
	return s


static func is_winning(counts: Array) -> bool:
	return shanten(counts) == -1


## Tile indices that complete a 13-tile hand.
static func winning_tiles(counts13: Array) -> Array:
	var out: Array = []
	for i in 34:
		if counts13[i] >= 4:
			continue
		var c: Array = counts13.duplicate()
		c[i] += 1
		if is_winning(c):
			out.append(i)
	return out


## Tile indices that lower the shanten of a 13-tile hand (useful for CPU later).
static func effective_tiles(counts13: Array) -> Array:
	var out: Array = []
	var now := shanten(counts13)
	for i in 34:
		if counts13[i] >= 4:
			continue
		var c: Array = counts13.duplicate()
		c[i] += 1
		if shanten(c) < now:
			out.append(i)
	return out


# --- standard form (4 sets + 1 pair) ---

static func shanten_standard(counts: Array) -> int:
	var best := [8]
	_dfs(counts.duplicate(), 0, 0, 0, best)
	return best[0]


static func _dfs(c: Array, mentsu: int, taatsu: int, pair: int, best: Array) -> void:
	var i := 0
	while i < 34 and c[i] == 0:
		i += 1
	if i == 34:
		var t := taatsu
		if mentsu + t > 4:
			t = 4 - mentsu
		var s := 8 - 2 * mentsu - t - pair
		if s < best[0]:
			best[0] = s
		return
	# triplet
	if c[i] >= 3:
		c[i] -= 3
		_dfs(c, mentsu + 1, taatsu, pair, best)
		c[i] += 3
	# sequence
	if i < 27 and i % 9 <= 6 and c[i + 1] > 0 and c[i + 2] > 0:
		c[i] -= 1
		c[i + 1] -= 1
		c[i + 2] -= 1
		_dfs(c, mentsu + 1, taatsu, pair, best)
		c[i] += 1
		c[i + 1] += 1
		c[i + 2] += 1
	# pair as the head
	if pair == 0 and c[i] >= 2:
		c[i] -= 2
		_dfs(c, mentsu, taatsu, 1, best)
		c[i] += 2
	# pair-shaped taatsu (toitsu)
	if c[i] >= 2:
		c[i] -= 2
		_dfs(c, mentsu, taatsu + 1, pair, best)
		c[i] += 2
	# open-ended / edge taatsu
	if i < 27 and i % 9 <= 7 and c[i + 1] > 0:
		c[i] -= 1
		c[i + 1] -= 1
		_dfs(c, mentsu, taatsu + 1, pair, best)
		c[i] += 1
		c[i + 1] += 1
	# closed (kanchan) taatsu
	if i < 27 and i % 9 <= 6 and c[i + 2] > 0:
		c[i] -= 1
		c[i + 2] -= 1
		_dfs(c, mentsu, taatsu + 1, pair, best)
		c[i] += 1
		c[i + 2] += 1
	# leave the tile unused
	c[i] -= 1
	_dfs(c, mentsu, taatsu, pair, best)
	c[i] += 1


# --- seven pairs ---

static func shanten_chiitoi(counts: Array) -> int:
	var pairs := 0
	var kinds := 0
	for i in 34:
		if counts[i] > 0:
			kinds += 1
		if counts[i] >= 2:
			pairs += 1
	var s := 6 - pairs
	if kinds < 7:
		s += 7 - kinds
	return s


# --- thirteen orphans ---

static func shanten_kokushi(counts: Array) -> int:
	var kinds := 0
	var has_pair := false
	for i in TERMINAL_HONOR_INDICES:
		if counts[i] > 0:
			kinds += 1
		if counts[i] >= 2:
			has_pair = true
	var s := 13 - kinds
	if has_pair:
		s -= 1
	return s
