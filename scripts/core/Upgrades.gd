# Upgrade definitions and the player's accumulated build.
#
# Pure logic, headlessly testable. Every stat the movement code reads is derived
# here from ranks, so there is exactly one place a number comes from.
#
# CLAUDE.md section 7.
class_name Upgrades
extends RefCounted

enum Line {
	PATH_INDICATOR,
	MINIMAP,
	BUFFER_WINDOW,
	FAST_TURNAROUND,
	BASE_SPEED,
	BARRIER_CAPACITY,
	BARRIER_REGEN,
	GATE_COMPASS,
	WALL_ARMOR,
	GOLDEN_TRAIL,
	SNAP_TURN,
}

# max_rank is the number of times a line can be taken. Lines whose effect is a
# table (indicator lookahead, minimap radius, reverse cost) cap at the length of
# that table.
const DEFINITIONS := {
	Line.PATH_INDICATOR: {
		"name": "Path Indicator",
		"max_rank": 3,
		"desc": [
			"At every T, a marker flashes GREEN toward the exit, RED away from it.",
			"The indicator appears a full cell earlier.",
			"Reads two junctions ahead.",
		],
	},
	Line.MINIMAP: {
		"name": "Minimap",
		"max_rank": 4,
		"desc": [
			"A circular map around you. Blurs during upgrade picks.",
			"Zoom out. More maze visible.",
			"Zoom out further.",
			"Maximum view radius.",
		],
	},
	Line.BUFFER_WINDOW: {
		"name": "Buffer Window",
		"max_rank": 5,
		"desc": [
			"+0.15 cells of turn buffer. Press earlier and still make the turn.",
			"+0.15 cells of turn buffer.",
			"+0.15 cells of turn buffer.",
			"+0.15 cells of turn buffer.",
			"+0.15 cells of turn buffer.",
		],
	},
	Line.FAST_TURNAROUND: {
		"name": "Fast Turnaround",
		"max_rank": 3,
		"desc": [
			"180 costs 1.5x instead of 2.0x.",
			"180 costs 1.0x.",
			"180 costs only 0.6x.",
		],
	},
	Line.BASE_SPEED: {
		"name": "Base Speed",
		"max_rank": 5,
		"desc": [
			"+0.25x speed floor. Less time in the slow band after a crash.",
			"+0.25x speed floor.",
			"+0.25x speed floor.",
			"+0.25x speed floor.",
			"+0.25x speed floor.",
		],
	},
	Line.BARRIER_CAPACITY: {
		"name": "Barrier Capacity",
		"max_rank": 4,
		"desc": [
			"+0.25s of wall contact before you crash.",
			"+0.25s of wall grace.",
			"+0.25s of wall grace.",
			"+0.25s of wall grace.",
		],
	},
	Line.BARRIER_REGEN: {
		"name": "Barrier Regen",
		"max_rank": 4,
		"desc": [
			"Barrier refills faster between scrapes.",
			"Barrier refills faster.",
			"Barrier refills faster.",
			"Barrier refills faster.",
		],
	},
	Line.GATE_COMPASS: {
		"name": "Gate Compass",
		"max_rank": 1,
		"desc": [
			"An arrow points toward the next gate. Always on.",
		],
	},
	Line.WALL_ARMOR: {
		"name": "Wall Armor",
		"max_rank": 3,
		"desc": [
			"Crashes deal 1 less damage.",
			"Crashes deal 1 less damage.",
			"Crashes deal 1 less damage.",
		],
	},
	Line.SNAP_TURN: {
		"name": "Snap Turn",
		"max_rank": 3,
		"desc": [
			"Corners hold you 25% less. Back up to speed sooner after every turn.",
			"Corners hold you 45% less.",
			"Corners hold you 60% less.",
		],
	},
	Line.GOLDEN_TRAIL: {
		"name": "Golden Trail",
		"max_rank": 3,
		"desc": [
			"Every 12s a golden streak races 10 cells down the best route.",
			"Every 8s, and it runs 15 cells.",
			"Every 5s, and it runs 20 cells.",
		],
	},
}


var ranks := {}

var _rng := RandomNumberGenerator.new()


func _init(p_seed: int = 0) -> void:
	for line in Line.values():
		ranks[line] = 0
	if p_seed != 0:
		_rng.seed = p_seed
	else:
		_rng.randomize()


func rank(line: int) -> int:
	return ranks.get(line, 0)


func take(line: int) -> void:
	if rank(line) < int(DEFINITIONS[line]["max_rank"]):
		ranks[line] = rank(line) + 1


func is_maxed(line: int) -> bool:
	return rank(line) >= int(DEFINITIONS[line]["max_rank"])


func line_name(line: int) -> String:
	return String(DEFINITIONS[line]["name"])


# Description of what the NEXT rank does -- that is what a card is offering.
func next_rank_description(line: int) -> String:
	var r := rank(line)
	var descs: Array = DEFINITIONS[line]["desc"]
	if r >= descs.size():
		return ""
	return String(descs[r])


func started_line_count() -> int:
	var count := 0
	for line in ranks:
		if ranks[line] > 0:
			count += 1
	return count


# --- Derived stats -----------------------------------------------------------
# The movement code reads these, never raw ranks.

func buffer_cells() -> float:
	return Tuning.BASE_BUFFER_CELLS + rank(Line.BUFFER_WINDOW) * Tuning.BUFFER_PER_RANK


# The post-turn hold, in seconds. Snap Turn shortens it.
#
# It is a REDUCTION, never a removal: at rank 3 the freeze is still 40% of base,
# because the freeze is what makes a corner readable at speed and zeroing it
# would hand the maxed build back the unreadable pivot the freeze exists to fix.
# What the line buys is time -- the freeze runs on the clock, and the clock is
# the score (CLAUDE.md section 8).
func turn_freeze() -> float:
	return Tuning.TURN_FREEZE * _freeze_scale()


func reverse_freeze() -> float:
	return Tuning.REVERSE_FREEZE * _freeze_scale()


func _freeze_scale() -> float:
	match rank(Line.SNAP_TURN):
		1: return 0.75
		2: return 0.55
		3: return 0.40
		_: return 1.0


func reverse_cost() -> float:
	var r := mini(rank(Line.FAST_TURNAROUND), Tuning.REVERSE_COST_BY_RANK.size() - 1)
	return float(Tuning.REVERSE_COST_BY_RANK[r])


func speed_floor() -> float:
	return Tuning.SPEED_FLOOR + rank(Line.BASE_SPEED) * Tuning.BASE_SPEED_PER_RANK


func barrier_capacity() -> float:
	return Tuning.BASE_BARRIER + rank(Line.BARRIER_CAPACITY) * Tuning.BARRIER_PER_RANK


func barrier_regen() -> float:
	return Tuning.BASE_BARRIER_REGEN + rank(Line.BARRIER_REGEN) * Tuning.BARRIER_REGEN_PER_RANK


func wall_damage() -> int:
	# Never heals on contact, however much armor is stacked.
	return maxi(0, Tuning.WALL_DAMAGE - rank(Line.WALL_ARMOR) * Tuning.WALL_ARMOR_PER_RANK)


func has_indicator() -> bool:
	return rank(Line.PATH_INDICATOR) > 0


func indicator_lookahead() -> float:
	var r := mini(rank(Line.PATH_INDICATOR), Tuning.INDICATOR_LOOKAHEAD_BY_RANK.size() - 1)
	return float(Tuning.INDICATOR_LOOKAHEAD_BY_RANK[r])


func has_minimap() -> bool:
	return rank(Line.MINIMAP) > 0


func minimap_radius() -> float:
	var r := mini(rank(Line.MINIMAP), Tuning.MINIMAP_RADIUS_BY_RANK.size() - 1)
	return float(Tuning.MINIMAP_RADIUS_BY_RANK[r])


func has_compass() -> bool:
	return rank(Line.GATE_COMPASS) > 0


func has_trail() -> bool:
	return rank(Line.GOLDEN_TRAIL) > 0


# Seconds between trail firings. 0.0 means the line is untaken -- callers must
# check has_trail() rather than dividing by this.
func trail_interval() -> float:
	var r := mini(rank(Line.GOLDEN_TRAIL), Tuning.TRAIL_INTERVAL_BY_RANK.size() - 1)
	return float(Tuning.TRAIL_INTERVAL_BY_RANK[r])


func trail_cells() -> float:
	var r := mini(rank(Line.GOLDEN_TRAIL), Tuning.TRAIL_CELLS_BY_RANK.size() - 1)
	return float(Tuning.TRAIL_CELLS_BY_RANK[r])


# --- Card offers -------------------------------------------------------------

# Three weighted-random cards. Never offers a maxed line. If the player has
# fewer than three lines started, guarantee a NEW line among the three -- early
# picks should feel like they open options, not deepen one stat
# (CLAUDE.md section 7).
func roll_cards(count: int = Tuning.CARDS_PER_GATE) -> Array[int]:
	var available: Array[int] = []
	for line in Line.values():
		if not is_maxed(line):
			available.append(line)

	var offered: Array[int] = []

	if started_line_count() < 3:
		var fresh: Array[int] = []
		for line in available:
			if rank(line) == 0:
				fresh.append(line)
		if not fresh.is_empty():
			var pick: int = fresh[_rng.randi_range(0, fresh.size() - 1)]
			offered.append(pick)
			available.erase(pick)

	while offered.size() < count and not available.is_empty():
		var pick: int = available[_rng.randi_range(0, available.size() - 1)]
		offered.append(pick)
		available.erase(pick)

	return offered


func snapshot() -> Dictionary:
	var result := {}
	for line in ranks:
		if ranks[line] > 0:
			result[line_name(line)] = ranks[line]
	return result
