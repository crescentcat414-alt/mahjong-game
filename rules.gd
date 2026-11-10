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
	var s := shanten_standard(counts, 4)
	s = mini(s, shanten_chiitoi(counts))
	s = mini(s, shanten_kokushi(counts))
	return s


## Shanten when some sets are already melded (meld_count fixed sets).
## Chiitoi/kokushi do not apply once the hand is open.
static var _shanten_cache := {}

static func shanten_for(counts: Array, meld_count: int) -> int:
	var key := str(meld_count) + ":" + ",".join(counts.map(func(v): return str(v)))
	if _shanten_cache.has(key):
		return _shanten_cache[key]
	var s: int
	if meld_count == 0:
		s = shanten(counts)
	else:
		s = shanten_standard(counts, 4 - meld_count)
	_shanten_cache[key] = s
	return s


static func is_winning(counts: Array) -> bool:
	return shanten(counts) == -1


static func is_winning_for(counts: Array, meld_count: int) -> bool:
	return shanten_for(counts, meld_count) == -1


## Tile indices that complete a 13-tile hand.
static func winning_tiles(counts13: Array) -> Array:
	return winning_tiles_for(counts13, 0)


static func winning_tiles_for(counts13: Array, meld_count: int) -> Array:
	var out: Array = []
	for i in 34:
		if counts13[i] >= 4:
			continue
		var c: Array = counts13.duplicate()
		c[i] += 1
		if is_winning_for(c, meld_count):
			out.append(i)
	return out


## Tile indices that lower the shanten of a 13-tile hand (useful for CPU later).
static func effective_tiles(counts13: Array) -> Array:
	return effective_tiles_for(counts13, 0)


static func effective_tiles_for(counts13: Array, meld_count: int) -> Array:
	var out: Array = []
	var now := shanten_for(counts13, meld_count)
	for i in 34:
		if counts13[i] >= 4:
			continue
		var c: Array = counts13.duplicate()
		c[i] += 1
		if shanten_for(c, meld_count) < now:
			out.append(i)
	return out


## The tile that a dora indicator points to.
static func next_tile_index(i: int) -> int:
	if i < 27:
		var base := int(i / 9) * 9
		return base + (i - base + 1) % 9
	if i < 31:
		return 27 + (i - 27 + 1) % 4
	return 31 + (i - 31 + 1) % 3


## Permanent furiten: a 13-tile hand in tenpai whose winning tiles include
## a tile the player has already discarded. (Temporary and riichi furiten
## are game-state matters handled with the game flow.)
static func is_furiten(counts13: Array, own_discard_indices: Array) -> bool:
	return is_furiten_for(counts13, own_discard_indices, 0)


static func is_furiten_for(counts13: Array, own_discard_indices: Array, meld_count: int) -> bool:
	for w in winning_tiles_for(counts13, meld_count):
		if own_discard_indices.has(w):
			return true
	return false


## Riichi may be declared with a closed tenpai hand and at least 1000 points.
## (Closed-ness is the caller's state; this checks the hand and the points.)
static func can_riichi(counts13: Array, points: int) -> bool:
	return points >= 1000 and shanten(counts13) == 0


# --- standard form (sets + 1 pair); target = number of sets to complete ---
# Memoized DFS: the same (remaining tiles, sets, taatsu, pair) state recurs
# constantly across branches, so caching states keeps this fast enough to
# call thousands of times per round.

static func shanten_standard(counts: Array, target: int = 4) -> int:
	var memo := {}
	return _dfs_memo(counts.duplicate(), 0, 0, 0, target, memo)


static func _dfs_memo(c: Array, mentsu: int, taatsu: int, pair: int, target: int, memo: Dictionary) -> int:
	var i := 0
	while i < 34 and c[i] == 0:
		i += 1
	if i == 34:
		var t := taatsu
		if mentsu + t > target:
			t = target - mentsu
		return 2 * target - 2 * mentsu - t - pair
	var key := str(i) + "|" + str(mentsu) + "," + str(taatsu) + "," + str(pair) + "|" + ",".join(c.slice(i).map(func(v): return str(v)))
	if memo.has(key):
		return memo[key]
	var best := 99
	# triplet
	if c[i] >= 3:
		c[i] -= 3
		best = mini(best, _dfs_memo(c, mentsu + 1, taatsu, pair, target, memo))
		c[i] += 3
	# sequence
	if i < 27 and i % 9 <= 6 and c[i + 1] > 0 and c[i + 2] > 0:
		c[i] -= 1
		c[i + 1] -= 1
		c[i + 2] -= 1
		best = mini(best, _dfs_memo(c, mentsu + 1, taatsu, pair, target, memo))
		c[i] += 1
		c[i + 1] += 1
		c[i + 2] += 1
	# pair as the head
	if pair == 0 and c[i] >= 2:
		c[i] -= 2
		best = mini(best, _dfs_memo(c, mentsu, taatsu, 1, target, memo))
		c[i] += 2
	# pair-shaped taatsu (toitsu)
	if c[i] >= 2:
		c[i] -= 2
		best = mini(best, _dfs_memo(c, mentsu, taatsu + 1, pair, target, memo))
		c[i] += 2
	# open-ended / edge taatsu
	if i < 27 and i % 9 <= 7 and c[i + 1] > 0:
		c[i] -= 1
		c[i + 1] -= 1
		best = mini(best, _dfs_memo(c, mentsu, taatsu + 1, pair, target, memo))
		c[i] += 1
		c[i + 1] += 1
	# closed (kanchan) taatsu
	if i < 27 and i % 9 <= 6 and c[i + 2] > 0:
		c[i] -= 1
		c[i + 2] -= 1
		best = mini(best, _dfs_memo(c, mentsu, taatsu + 1, pair, target, memo))
		c[i] += 1
		c[i + 2] += 1
	# leave the tile unused
	c[i] -= 1
	best = mini(best, _dfs_memo(c, mentsu, taatsu, pair, target, memo))
	c[i] += 1
	memo[key] = best
	return best


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
