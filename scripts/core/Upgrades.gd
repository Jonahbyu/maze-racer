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
	PLATINUM_TRAIL,
	SNAP_TURN,
	CORNERING,
	EXPIRY_GRACE,
	HP_REGEN,
	SCORE_BONUS,
	QUADRANT,
	COMPASS,
	TRAIL_MEMORY,
	# Legendaries. Rare, active, one per run -- see is_legendary() and the
	# rarity rule in roll_cards().
	WALL_SMASHER,
	FLYING_VISION,
	AUTO_STEER,
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
		"max_rank": 7,
		"desc": [
			"+0.15 cells of turn buffer. Press earlier and still make the turn.",
			"+0.15 cells of turn buffer.",
			"+0.15 cells of turn buffer.",
			"+0.15 cells of turn buffer.",
			"+0.15 cells of turn buffer.",
			"+0.15 cells of turn buffer.",
			"+0.15 cells of turn buffer. Over two cells of forgiveness.",
		],
	},
	Line.FAST_TURNAROUND: {
		"name": "Fast Turnaround",
		"max_rank": 3,
		# Left empty on purpose: the text is DERIVED from
		# Tuning.REVERSE_COST_BY_RANK in next_rank_description(), because these
		# strings had drifted badly -- they still advertised "1.5x instead of
		# 2.0x" long after the 180 was retuned to 0.75x (CLAUDE.md section 5.3),
		# so the cards were quoting numbers the game had not used for a while.
		# A description that restates a tuning value is the same transcription
		# trap section 12 flags for tests.
		"desc": [],
	},
	Line.BASE_SPEED: {
		"name": "Base Speed",
		"max_rank": 7,
		"desc": [
			"+0.25x speed floor. Less time in the slow band after a crash.",
			"+0.25x speed floor.",
			"+0.25x speed floor.",
			"+0.25x speed floor.",
			"+0.25x speed floor.",
			"+0.25x speed floor.",
			"+0.25x speed floor. You never drop below 2.5x.",
		],
	},
	Line.BARRIER_CAPACITY: {
		"name": "Barrier Capacity",
		"max_rank": 6,
		"desc": [
			"+0.25s of wall contact before you crash.",
			"+0.25s of wall grace.",
			"+0.25s of wall grace.",
			"+0.25s of wall grace.",
			"+0.25s of wall grace.",
			"+0.25s of wall grace. Two full seconds on the wall.",
		],
	},
	Line.BARRIER_REGEN: {
		"name": "Barrier Regen",
		"max_rank": 6,
		"desc": [
			"Barrier refills faster between scrapes.",
			"Barrier refills faster.",
			"Barrier refills faster.",
			"Barrier refills faster.",
			"Barrier refills faster.",
			"Barrier refills faster. Back to full in under a second.",
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
			"Every 12s a gold streak runs the whole route to the next gate.",
			"Every 8s.",
			"Every 5s.",
		],
	},
	Line.PLATINUM_TRAIL: {
		"name": "Platinum Trail",
		"max_rank": 3,
		"desc": [
			"After 5 gates, every 15s a silver streak runs the shortest way OUT.",
			"Every 10s.",
			"Every 6s.",
		],
	},
	Line.CORNERING: {
		"name": "Cornering",
		"max_rank": 3,
		"desc": [
			"Turns cost 20% less speed. Turn-heavy routes stop bleeding you dry.",
			"Turns cost 40% less.",
			"Turns cost 60% less. Corner as much as the maze asks.",
		],
	},
	Line.EXPIRY_GRACE: {
		"name": "Expiry Grace",
		"max_rank": 3,
		"desc": [
			"An expired press costs 0.38x instead of 0.5x. Press early more freely.",
			"An expired press costs 0.26x.",
			"An expired press costs only 0.15x.",
		],
	},
	Line.HP_REGEN: {
		"name": "Repair Field",
		"max_rank": 3,
		"desc": [
			"Recover 0.6 HP per second of clean travel.",
			"Recover 1.2 HP per second.",
			"Recover 2.0 HP per second. Drive clean and you drive it off.",
		],
	},
	Line.QUADRANT: {
		"name": "Quadrant",
		"max_rank": 3,
		"desc": [
			"A corner box splits the maze in four and lights the quarter you are in.",
			"Nine regions instead of four. A finer read on how far you have come.",
			"Sixteen regions. The exit is always the highest.",
		],
	},
	Line.COMPASS: {
		"name": "Compass",
		"max_rank": 1,
		"desc": [
			"Read the direction you face: N, E, S or W. The exit lies south-east.",
		],
	},
	Line.SCORE_BONUS: {
		"name": "Score Multiplier",
		"max_rank": 4,
		"desc": [
			"+15% points earned. Stacks before the time bonus.",
			"+30% points earned.",
			"+45% points earned.",
			"+60% points earned.",
		],
	},
	Line.TRAIL_MEMORY: {
		"name": "Trail Memory",
		"max_rank": 6,
		# Descriptions are generated from the rank table in
		# next_rank_description(), so this list is only the flavour of the FIRST
		# rank -- see the comment there.
		"desc": [],
	},
	Line.WALL_SMASHER: {
		"name": "Wall Smasher",
		"max_rank": 3,
		"legendary": true,
		"desc": [
			"LEGENDARY  -  Every 45s, crash through a wall instead of stopping. Keep your speed; the wall is destroyed.",
			"Cooldown down to 30s.",
			"Cooldown down to 20s.",
		],
	},
	Line.FLYING_VISION: {
		"name": "Flying Vision",
		"max_rank": 3,
		"legendary": true,
		"desc": [
			"LEGENDARY  -  Double-tap DOWN to stop time and rise above the maze for 5s. Every 45s.",
			"Cooldown down to 30s.",
			"Cooldown down to 20s.",
		],
	},
	Line.AUTO_STEER: {
		"name": "Auto-Steer",
		"max_rank": 3,
		"legendary": true,
		"desc": [
			"LEGENDARY  -  Double-tap DOWN to be driven down the best route at 2x speed for 3s, untouchable. Every 45s.",
			"It runs for 4.5s.",
			"It runs for 6s.",
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

	# Fast Turnaround reads its numbers from the tuning table rather than from a
	# fixed string, so the card can never advertise a cost the game does not
	# charge.
	if line == Line.FAST_TURNAROUND:
		var costs: Array = Tuning.REVERSE_COST_BY_RANK
		if r + 1 >= costs.size():
			return ""
		return "A 180 costs %.2fx instead of %.2fx." % [
			float(costs[r + 1]), float(costs[r])
		]

	# Both trail lines derive their numbers for the same reason: a card that
	# restates a tuning value is a transcription that goes stale silently, and
	# the player makes a decision on it. Fast Turnaround's strings had already
	# drifted a whole retune before this was noticed (CLAUDE.md section 7).
	if line == Line.GOLDEN_TRAIL:
		var gi: Array = Tuning.TRAIL_INTERVAL_BY_RANK
		if r + 1 >= gi.size():
			return ""
		if r == 0:
			return "Every %ds a gold streak runs the whole route to the next gate." % int(gi[r + 1])
		return "Every %ds instead of %ds." % [int(gi[r + 1]), int(gi[r])]

	if line == Line.PLATINUM_TRAIL:
		var pi: Array = Tuning.PLATINUM_INTERVAL_BY_RANK
		if r + 1 >= pi.size():
			return ""
		if r == 0:
			return "After %d gates, every %ds a silver streak runs the shortest way OUT." % [
				Tuning.PLATINUM_MIN_GATES, int(pi[r + 1])
			]
		return "Every %ds instead of %ds." % [int(pi[r + 1]), int(pi[r])]

	# Trail Memory's cards are generated from the window table for the same
	# reason Fast Turnaround's are: a hand-written string that restates a tuning
	# number drifts silently, and the player picks a card on what it says.
	if line == Line.TRAIL_MEMORY:
		var windows: Array = Tuning.TRAIL_WINDOW_BY_RANK
		if r + 1 >= windows.size():
			return ""
		var next_w := float(windows[r + 1])
		if next_w == Tuning.TRAIL_WINDOW_INFINITE:
			return "Ground you have driven stays lit for the REST OF THE MAZE."
		var text := "%d:%02d" % [int(next_w) / 60, int(next_w) % 60]
		if r == 0:
			return "Ground you have driven lights up, dimming as you re-cross it. Remembered for %s." % text
		return "Remembered for %s." % text

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


# Damage from one crash, on the given maze.
#
# The maze index is a PARAMETER rather than state held here, because Upgrades is
# the player's build and the maze is not part of it -- the same build crashing
# on maze 1 and maze 5 must give different answers, and an Upgrades that
# remembered which maze it was on would be two things at once.
#
# Armor subtracts AFTER the per-maze scaling, so a rank of Wall Armor is worth
# the same flat point everywhere rather than being multiplied up in the late
# mazes where the damage is already largest.
func wall_damage(maze_index: int = 0) -> int:
	var base := Tuning.WALL_DAMAGE + maxi(0, maze_index) * Tuning.WALL_DAMAGE_PER_MAZE
	# Never heals on contact, however much armor is stacked.
	return maxi(0, base - rank(Line.WALL_ARMOR) * Tuning.WALL_ARMOR_PER_RANK)


# The per-turn speed cost. Cornering reduces it, never to zero -- a free turn
# would remove the routing decision the cost exists to create (section 5.3).
func turn_cost() -> float:
	var r := mini(rank(Line.CORNERING), Tuning.TURN_COST_BY_RANK.size() - 1)
	return float(Tuning.TURN_COST_BY_RANK[r])


# The speed cost of an expired turn input. Expiry Grace shrinks it, never to
# zero -- an expired press must always mean something.
func slowdown_penalty() -> float:
	var r := mini(rank(Line.EXPIRY_GRACE), Tuning.SLOWDOWN_PENALTY_BY_RANK.size() - 1)
	return float(Tuning.SLOWDOWN_PENALTY_BY_RANK[r])


# HP restored per second of clean travel. Zero without the line, so HP only ever
# falls on an unupgraded build.
func hp_regen() -> float:
	var r := mini(rank(Line.HP_REGEN), Tuning.HP_REGEN_BY_RANK.size() - 1)
	return float(Tuning.HP_REGEN_BY_RANK[r])


func has_hp_regen() -> bool:
	return rank(Line.HP_REGEN) > 0


# Multiplier on points earned, from the Score Multiplier line. Applied to the
# maze subtotal before the time multiplier (CLAUDE.md section 8b).
func score_multiplier() -> float:
	return 1.0 + rank(Line.SCORE_BONUS) * Tuning.SCORE_BONUS_PER_RANK


# --- Legendaries -------------------------------------------------------------

func is_legendary(line: int) -> bool:
	return bool(DEFINITIONS[line].get("legendary", false))


# The legendary held this run, or -1. One per run is enforced at the OFFER
# (roll_cards), so this can never find more than one.
func legendary_line() -> int:
	for line in Line.values():
		if is_legendary(line) and rank(line) > 0:
			return line
	return -1


func has_legendary() -> bool:
	return legendary_line() != -1


# Cooldown for whichever legendary is held, in seconds. 0.0 when none is.
func legendary_cooldown() -> float:
	var line := legendary_line()
	if line == -1:
		return 0.0
	var r := rank(line)
	if line == Line.AUTO_STEER:
		return Tuning.AUTOSTEER_COOLDOWN
	var table: Array = Tuning.LEGENDARY_COOLDOWN_BY_RANK
	return float(table[mini(r, table.size() - 1)])


func has_wall_smasher() -> bool:
	return rank(Line.WALL_SMASHER) > 0


func has_flying_vision() -> bool:
	return rank(Line.FLYING_VISION) > 0


func has_auto_steer() -> bool:
	return rank(Line.AUTO_STEER) > 0


func auto_steer_duration() -> float:
	var r := mini(rank(Line.AUTO_STEER), Tuning.AUTOSTEER_DURATION_BY_RANK.size() - 1)
	return float(Tuning.AUTOSTEER_DURATION_BY_RANK[r])


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


# --- Quadrant and Compass ----------------------------------------------------
# Position and orientation. Both sit on the "have I been here" side of the line
# landmarks, spent gates and the rear-view mirror hold (CLAUDE.md section 7) --
# they never answer "which way", which is what keeps them clear of the three
# paid route lines.

func has_quadrant() -> bool:
	return rank(Line.QUADRANT) > 0


# Divisions per AXIS: 2, 3 or 4, giving 4, 9 or 16 regions. Zero when the line
# is untaken, so callers must check has_quadrant() rather than dividing by this.
func quadrant_divisions() -> int:
	var r := mini(rank(Line.QUADRANT), Tuning.QUADRANT_DIVISIONS_BY_RANK.size() - 1)
	return int(Tuning.QUADRANT_DIVISIONS_BY_RANK[r])


func has_cardinal_compass() -> bool:
	return rank(Line.COMPASS) > 0


# --- Trail Memory ------------------------------------------------------------
# Ground the player has driven, tinted on the floor and on the minimap. It sits
# on the "have I been here" side of the line landmarks, spent gates and the
# rear-view mirror hold (CLAUDE.md sections 6 and 7) -- it says nothing whatever
# about the route ahead, which is what keeps it clear of Path Indicator, Gate
# Compass and Golden Trail. Being PAID makes it the strongest statement of that
# position in the tree, not a departure from it.

func has_trail_memory() -> bool:
	return rank(Line.TRAIL_MEMORY) > 0


# How long a driven cell stays remembered, in seconds. Returns
# Tuning.TRAIL_WINDOW_INFINITE (a negative sentinel) at the top rank, and 0.0
# when the line is untaken -- callers must check has_trail_memory() rather than
# treating 0.0 as a duration.
func trail_memory_window() -> float:
	var r := mini(rank(Line.TRAIL_MEMORY), Tuning.TRAIL_WINDOW_BY_RANK.size() - 1)
	return float(Tuning.TRAIL_WINDOW_BY_RANK[r])


func has_trail() -> bool:
	return rank(Line.GOLDEN_TRAIL) > 0


# Seconds between trail firings. 0.0 means the line is untaken -- callers must
# check has_trail() rather than dividing by this.
func trail_interval() -> float:
	var r := mini(rank(Line.GOLDEN_TRAIL), Tuning.TRAIL_INTERVAL_BY_RANK.size() - 1)
	return float(Tuning.TRAIL_INTERVAL_BY_RANK[r])


func has_platinum_trail() -> bool:
	return rank(Line.PLATINUM_TRAIL) > 0


func platinum_interval() -> float:
	var r := mini(rank(Line.PLATINUM_TRAIL), Tuning.PLATINUM_INTERVAL_BY_RANK.size() - 1)
	return float(Tuning.PLATINUM_INTERVAL_BY_RANK[r])


# --- Card offers -------------------------------------------------------------

# Three weighted-random cards. Never offers a maxed line. If the player has
# fewer than three lines started, guarantee a NEW line among the three -- early
# picks should feel like they open options, not deepen one stat
# (CLAUDE.md section 7).
func roll_cards(count: int = Tuning.CARDS_PER_GATE) -> Array[int]:
	# One legendary per run, enforced at the OFFER rather than at the take: once
	# any legendary is held, no legendary is ever offered again. Refusing a
	# second at pick time instead would waste the pick and read as a bug
	# (CLAUDE.md section 7).
	var holds_legendary := has_legendary()

	var available: Array[int] = []
	for line in Line.values():
		if is_maxed(line):
			continue
		# A legendary already started stays upgradeable; a DIFFERENT one is
		# locked out for the rest of the run.
		if is_legendary(line) and holds_legendary and rank(line) == 0:
			continue
		available.append(line)

	var offered: Array[int] = []

	if started_line_count() < 3:
		var fresh: Array[int] = []
		for line in available:
			# Never satisfy the "open a new line" guarantee with a legendary:
			# that rule exists so early picks feel like they open options, and
			# spending it on the rare tier would make a legendary a near-certain
			# opener rather than a rare find.
			if rank(line) == 0 and not is_legendary(line):
				fresh.append(line)
		if not fresh.is_empty():
			var pick: int = fresh[_rng.randi_range(0, fresh.size() - 1)]
			offered.append(pick)
			available.erase(pick)

	while offered.size() < count and not available.is_empty():
		var pick: int = _weighted_pick(available)
		offered.append(pick)
		available.erase(pick)

	return offered


# Weighted draw. Ordinary lines weigh 1.0; legendaries weigh far less, which is
# what actually makes the tier RARE -- a uniform draw would surface a legendary
# as often as Buffer Window, and "rare" would be a label rather than a fact.
#
# An UNSTARTED legendary is the rare case. Once one is held it is an ordinary
# part of the build and upgrading it should not be a lottery, so it draws at
# full weight like anything else.
func _weighted_pick(pool: Array[int]) -> int:
	var total := 0.0
	for line in pool:
		total += _draw_weight(line)

	var roll := _rng.randf() * total
	for line in pool:
		roll -= _draw_weight(line)
		if roll <= 0.0:
			return line
	return pool[pool.size() - 1]


func _draw_weight(line: int) -> float:
	if is_legendary(line) and rank(line) == 0:
		return Tuning.LEGENDARY_DRAW_WEIGHT
	return 1.0


func snapshot() -> Dictionary:
	var result := {}
	for line in ranks:
		if ranks[line] > 0:
			result[line_name(line)] = ranks[line]
	return result
