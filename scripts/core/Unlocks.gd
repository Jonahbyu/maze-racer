# What the player has earned, and what earns it.
#
# COSMETICS ONLY, and that line is the whole reason this is allowed to exist.
# CLAUDE.md section 10 defers meta-progression, and every example it names --
# upgrade lines, starting bonuses, maze modifiers -- changes how a run PLAYS.
# That is what "v1 is a single self-contained run" protects. A marker shape
# changes nothing: section 12 already asserts the simulation cannot read the
# choice, by driving two racers side by side on one seed.
#
# So the rule is NARROWED rather than broken. The line to hold, forever: if an
# unlock would change a number the racer reads, it does not belong here.
#
# Nothing in the simulation may read this autoload. Same separation landmarks
# (section 6), music (9c), touch controls (9d) and the marker picker have -- it
# is absent in every harness that instantiates Game.tscn bare, so every read is
# guarded rather than assumed.
# NO class_name, deliberately. A script whose class_name matches its autoload
# name fails to parse -- "Class X hides an autoload singleton" -- and the
# autoload then never loads at all, which reads exactly like forgetting to
# register it. Music, Settings and Leaderboard all omit it for the same reason.
#
# Callers reach the table through the autoload (`Unlocks.ACHIEVEMENTS`) or, in a
# harness with no autoloads, by preloading this script.
extends Node

signal unlocked(ids: Array)

# Beside the preferences rather than in a file of its own: one place a player
# can clear, and one file to keep in step. Settings owns the same path.
const CONFIG_PATH := "user://settings.cfg"
const SECTION := "unlocks"

# Ids are NAMESPACED so one earned set covers shapes, colours and decals without
# three parallel dictionaries to keep in step -- the failure section 6 records
# for landmark density and 9c for music tracks.
const KIND_SHAPE := "shape"
const KIND_COLOUR := "colour"
const KIND_DECAL := "decal"
const KIND_PALETTE := "palette"


static func id_for(kind: String, name: String) -> String:
	return "%s:%s" % [kind, name]


# What each achievement asks for, and what it grants.
#
# Every requirement is measurable from data the game ALREADY keeps -- Score's
# tallies and per-maze results, and the finishing Upgrades. Peak speed is the one
# addition, and it is the only change this feature makes to a file the simulation
# touches. Nothing else here required growing a rules-layer class.
#
# "requirement" is shown VERBATIM under a locked entry in the picker, so it is
# written for a player rather than as a rule name. It and _met() must say the
# same thing: a description that drifts from what it describes is the trap
# section 7 records for upgrade card text, and it is worse here because the
# player is working toward it.
const ACHIEVEMENTS := {
	# --- Shapes: earned by getting THROUGH the game -----------------------
	"first_blood": {
		"label": "FIRST BLOOD",
		"requirement": "Finish a run",
		"grants": "shape:dart",
	},
	"the_tangle": {
		"label": "INTO THE TANGLE",
		"requirement": "Reach maze 3",
		"grants": "shape:delta",
	},
	"the_vault": {
		"label": "THE VAULT",
		"requirement": "Reach maze 5",
		"grants": "shape:kite",
	},
	"clear_run": {
		"label": "ALL FIVE",
		"requirement": "Clear all five mazes",
		"grants": "shape:chevron",
	},
	"flawless": {
		"label": "FLAWLESS",
		"requirement": "Finish a run without crashing",
		"grants": "shape:cycle",
	},

	# --- Colours: earned by HOW you drive ---------------------------------
	"ton_up": {
		"label": "TON UP",
		"requirement": "Reach 6x speed",
		"grants": "colour:ice",
	},
	"redline": {
		"label": "REDLINE",
		"requirement": "Reach 8x speed",
		"grants": "colour:coral",
	},
	"clean_hands": {
		"label": "CLEAN HANDS",
		"requirement": "Finish a run without touching a wall",
		"grants": "colour:jade",
	},
	"wall_dancer": {
		"label": "WALL DANCER",
		"requirement": "Escape 50 scrapes in one run",
		"grants": "colour:gold",
	},
	"no_looking_back": {
		"label": "NO LOOKING BACK",
		"requirement": "Finish a run without re-crossing a cell",
		"grants": "colour:rust",
	},
	"century": {
		"label": "CENTURY",
		"requirement": "Bank 100,000 points in a run",
		"grants": "colour:magenta",
	},
	"half_million": {
		"label": "HALF A MILLION",
		"requirement": "Bank 500,000 points in a run",
		"grants": "colour:violet",
	},
	"survivor": {
		"label": "SURVIVOR",
		"requirement": "Clear the run with under 10 HP left",
		"grants": "colour:steel",
	},
	"cornerer": {
		"label": "CORNERER",
		"requirement": "Take 500 clean turns in one run",
		"grants": "colour:lime",
	},
	# Cobalt became lockable when colour 2's default moved to white. It was
	# unlocked from the start purely to be the second default, which is a
	# cosmetic nobody had to earn -- the mirror of the "achievement granting
	# something already held" bug, and asserted in both directions now.
	"gatecrasher": {
		"label": "GATECRASHER",
		"requirement": "Collect every gate in three mazes",
		"grants": "colour:cobalt",
	},

	# --- Palettes: earned across the whole spread of play -----------------
	#
	# Twenty colourways on top of the five a fresh profile already has, spread
	# deliberately across DIFFERENT axes -- progress, score, speed, cornering,
	# scraping, build width and even failure -- so no single style of run sweeps
	# them. A player who never crashes never earns CRIMSON, and one who never
	# scrapes never earns JADE.
	#
	# The four "reach maze N" entries grant the mazes' OWN colourways, and that
	# pairing is deliberate: reaching The Ember is what earns you the right to
	# put ember on another maze. The reward is the thing the player just drove
	# through, which needs no explaining.
	"palette_magenta": {
		"label": "THE EMBER",
		"requirement": "Reach maze 2",
		"grants": "palette:magenta",
	},
	"palette_acid": {
		"label": "THE TANGLE",
		"requirement": "Clear two mazes under 120 seconds each",
		"grants": "palette:acid",
	},
	"palette_ember": {
		"label": "THE LABYRINTH",
		"requirement": "Reach maze 4",
		"grants": "palette:ember",
	},
	"palette_violet": {
		"label": "THE VAULT",
		"requirement": "Take 750 clean turns in one run",
		"grants": "palette:violet",
	},
	# These four moved OFF "reach maze N" when the authored colourways took
	# those slots. Two goals with the same requirement unlock as a pair, which
	# spends two entries to ask one question -- so these sit on score, speed and
	# survival instead, keeping the spread this block is built around.
	"palette_ice": {
		"label": "ICE",
		"requirement": "Bank 50,000 points in a run",
		"grants": "palette:ice",
	},
	"palette_azure": {
		"label": "AZURE",
		"requirement": "Reach 5x speed",
		"grants": "palette:azure",
	},
	"palette_cobalt": {
		"label": "COBALT",
		"requirement": "Reach 4x speed crashing at most once",
		"grants": "palette:cobalt",
	},
	"palette_indigo": {
		"label": "INDIGO",
		"requirement": "Bank a maze at a x3 time multiplier or better",
		"grants": "palette:indigo",
	},
	"palette_orchid": {
		"label": "ORCHID",
		"requirement": "Clear all five mazes banking 400,000 points",
		"grants": "palette:orchid",
	},
	"palette_plum": {
		"label": "PLUM",
		"requirement": "Bank 250,000 points in a run",
		"grants": "palette:plum",
	},
	"palette_fuchsia": {
		"label": "FUCHSIA",
		"requirement": "Bank 750,000 points in a run",
		"grants": "palette:fuchsia",
	},
	"palette_rose": {
		"label": "ROSE",
		"requirement": "Bank 1,000,000 points in a run",
		"grants": "palette:rose",
	},
	"palette_crimson": {
		"label": "CRIMSON",
		"requirement": "Crash 10 times in one run",
		"grants": "palette:crimson",
	},
	"palette_coral": {
		"label": "CORAL",
		"requirement": "Reach 7x speed",
		"grants": "palette:coral",
	},
	"palette_bronze": {
		"label": "BRONZE",
		"requirement": "Reach 9x speed",
		"grants": "palette:bronze",
	},
	"palette_sand": {
		"label": "SAND",
		"requirement": "Take 250 clean turns in one run",
		"grants": "palette:sand",
	},
	"palette_olive": {
		"label": "OLIVE",
		"requirement": "Take 1,000 clean turns in one run",
		"grants": "palette:olive",
	},
	"palette_lime": {
		"label": "LIME",
		"requirement": "Escape 20 scrapes in one run",
		"grants": "palette:lime",
	},
	"palette_jade": {
		"label": "JADE",
		"requirement": "Escape 100 scrapes in one run",
		"grants": "palette:jade",
	},
	"palette_mint": {
		"label": "MINT",
		"requirement": "Clear a run without a single scrape",
		"grants": "palette:mint",
	},
	"palette_teal": {
		"label": "TEAL",
		"requirement": "Finish a run holding 8 upgrade lines",
		"grants": "palette:teal",
	},
	"palette_aqua": {
		"label": "AQUA",
		"requirement": "Finish a run holding 16 upgrade lines",
		"grants": "palette:aqua",
	},
	"palette_slate": {
		"label": "SLATE",
		"requirement": "Finish a run with full health",
		"grants": "palette:slate",
	},
	"palette_ash": {
		"label": "ASH",
		"requirement": "Re-cross 100 cells in one run",
		"grants": "palette:ash",
	},

	# --- Speed of SOLVING, an axis nothing else asks about ----------------
	#
	# maze_results already records per-maze time and multiplier, and until now
	# nothing read either. Every other achievement here measures how the player
	# drove; these measure how quickly they got OUT, which section 8b calls the
	# routing skill the score exists to reward. A player can be fast and scruffy
	# or clean and slow, so these do not fall out of the existing set.
	"quick_study": {
		"label": "QUICK STUDY",
		"requirement": "Clear a maze in under 90 seconds",
		"grants": "colour:sky",
	},
	"pathfinder": {
		"label": "PATHFINDER",
		"requirement": "Clear a maze in under 60 seconds",
		"grants": "colour:mint",
	},
	"trailblazer": {
		"label": "TRAILBLAZER",
		"requirement": "Bank a maze at a x4 time multiplier or better",
		"grants": "shape:spear",
	},
	"the_shortcut": {
		"label": "THE SHORTCUT",
		"requirement": "Clear three mazes under 90 seconds each",
		"grants": "decal:chevrons",
	},

	# --- Consistency, rather than a single best moment --------------------
	#
	# Every threshold above fires on a PEAK -- one fast maze, one high score.
	# These ask for the same standard held across a whole run, which is a
	# different skill and a much harder one: a player who spikes to 8x once
	# will not necessarily average well.
	"steady_hand": {
		"label": "STEADY HAND",
		"requirement": "Clear all five mazes with no maze over 150 seconds",
		"grants": "shape:wedge",
	},
	"metronome": {
		"label": "METRONOME",
		"requirement": "Bank every maze of a full run above 50,000 points",
		"grants": "colour:amber",
	},
	"unbroken": {
		"label": "UNBROKEN",
		"requirement": "Clear all five mazes finishing above half health",
		"grants": "decal:bars",
	},
	"purist": {
		"label": "PURIST",
		"requirement": "Clear a run holding 3 upgrade lines or fewer",
		"grants": "colour:sand",
	},

	# --- The extremes of the damage economy -------------------------------
	"last_stand": {
		"label": "LAST STAND",
		"requirement": "Clear the run with 1 HP left",
		"grants": "colour:crimson",
	},
	"untouchable": {
		"label": "UNTOUCHABLE",
		"requirement": "Bank 100,000 points in a single maze",
		"grants": "decal:tail",
	},
	"deep_pockets": {
		"label": "DEEP POCKETS",
		"requirement": "Take a line to rank 5 or higher",
		"grants": "colour:teal",
	},
	"generalist": {
		"label": "GENERALIST",
		"requirement": "Finish a run holding 20 upgrade lines",
		"grants": "colour:plum",
	},
	"the_scenic_route": {
		"label": "THE SCENIC ROUTE",
		"requirement": "Re-cross 500 cells in one run",
		"grants": "colour:rose",
	},

	# --- Decals: earned by what you BUILD ---------------------------------
	"legend": {
		"label": "LEGEND",
		"requirement": "Hold a legendary upgrade",
		"grants": "decal:stripe",
	},
	"maxed": {
		"label": "MAXED",
		"requirement": "Take a line to its highest rank",
		"grants": "decal:notch",
	},
	"specialist": {
		"label": "SPECIALIST",
		"requirement": "Finish a run holding 12 upgrade lines",
		"grants": "decal:tip",
	},
	"the_long_way": {
		"label": "THE LONG WAY",
		"requirement": "Collect every gate in a maze",
		"grants": "decal:split",
	},
}


# Earned cosmetic ids. Keyed by the namespaced id, never by achievement -- what
# the picker asks is "may I offer this", and an achievement is only how it got
# there.
var earned := {}


func _ready() -> void:
	_load()


func is_unlocked(id: String) -> bool:
	# The three defaults are never lockable. A saved name that no longer
	# resolves falls back to them (section 12), so a locked default would strand
	# the player with no marker at all.
	if _is_default(id):
		return true
	return bool(earned.get(id, false))


func _is_default(id: String) -> bool:
	return id == id_for(KIND_SHAPE, Tuning.MARKER_SHAPE_DEFAULT) 		or id == id_for(KIND_DECAL, Tuning.MARKER_DECAL_DEFAULT) 		or id == id_for(KIND_COLOUR, Tuning.MARKER_COLOUR_DEFAULT) 		or id == id_for(KIND_COLOUR, Tuning.MARKER_COLOUR_2_DEFAULT) 		or _is_authored_palette(id)


# MAZE 1's palette, the one colourway that can never be locked.
#
# All five authored palettes used to sit here, and that gave a fresh profile
# five ready choices on a screen whose whole job is to be a goal list -- the
# five were simultaneously every maze's default AND every slot's alternative,
# so the screen opened fully stocked and nothing on it read as earnable.
#
# Displaying a colourway and being able to REASSIGN it are different rights, and
# only the first has to be free: Game reads default_palette_id() directly, so
# every maze still SHOWS its own authored hue on a fresh profile and the
# escalation section 8 tuned is intact. What is earned is the ability to move a
# colourway onto a slot it does not belong to.
#
# Maze 1's stays unlocked because a profile with nothing earned could otherwise
# assign nothing at all, which is a screen with no legal move on it.
func _is_authored_palette(id: String) -> bool:
	return id == id_for(KIND_PALETTE, Tuning.default_palette_id(0))


# Every cosmetic that CAN be locked -- everything but the three defaults.
static func lockable_ids() -> Array:
	var out: Array = []
	for shape in Tuning.MARKER_SHAPES:
		if String(shape["id"]) != Tuning.MARKER_SHAPE_DEFAULT:
			out.append(id_for(KIND_SHAPE, String(shape["id"])))
	for entry in Tuning.MARKER_COLOURS:
		# BOTH colour defaults are excluded. Colour 2 defaults to cobalt rather
		# than to white, because two identical defaults would show a white
		# pattern on a white mark and read as a broken decal -- so cobalt is a
		# default too and cannot be lockable. RulesTest caught the contradiction
		# the moment only one was excluded.
		var cid := String(entry["id"])
		if cid != Tuning.MARKER_COLOUR_DEFAULT 				and cid != Tuning.MARKER_COLOUR_2_DEFAULT:
			out.append(id_for(KIND_COLOUR, cid))
	for decal in Tuning.MARKER_DECALS:
		if String(decal["id"]) != Tuning.MARKER_DECAL_DEFAULT:
			out.append(id_for(KIND_DECAL, String(decal["id"])))
	# Every palette but MAZE 1's is earned, including the other four authored
	# ones. That does NOT make a first run cyan: Game resolves an unassigned
	# slot through default_palette_id(), which never consults this set, so each
	# maze still wears its own colourway from the first run. What is locked is
	# only the right to MOVE a colourway to another maze.
	#
	# Index 0 rather than a literal, since default_palette_id() maps maze N to
	# PALETTES[N] and maze 1 is the slot that must always have a legal choice.
	for i in range(1, Tuning.PALETTES.size()):
		out.append(id_for(KIND_PALETTE, String(Tuning.PALETTES[i].get("id", ""))))
	return out


# Does a namespaced id name something that actually exists?
#
# This is what stops an achievement granting a typo forever -- a lookup that
# falls back to the default would otherwise make "colour:puce" look valid.
static func cosmetic_exists(id: String) -> bool:
	var parts := id.split(":")
	if parts.size() != 2:
		return false
	match parts[0]:
		KIND_SHAPE:
			return String(Tuning.marker_shape(parts[1])["id"]) == parts[1]
		KIND_COLOUR:
			return String(Tuning.marker_colour(parts[1])["id"]) == parts[1]
		KIND_DECAL:
			return String(Tuning.marker_decal(parts[1])["id"]) == parts[1]
		KIND_PALETTE:
			return String(Tuning.palette_by_id(parts[1]).get("id", "")) 				== parts[1]
	return false


# The achievement granting an id, or an empty dictionary. This is what the
# picker prints under a locked entry.
static func achievement_for(id: String) -> Dictionary:
	for aid in ACHIEVEMENTS:
		if String(ACHIEVEMENTS[aid]["grants"]) == id:
			return ACHIEVEMENTS[aid]
	return {}


# Award everything this run earned, and return only what was NEWLY earned.
#
# Called from exactly one place -- Game._post_run, whose own comment already
# calls it "the only point at which a run is genuinely over and its score
# final". Deliberately not evaluated during play: an unlock popup over a
# corridor at 8x is a distraction placed exactly where section 11.3 says the
# player has no attention to spare.
#
# Already-earned achievements are excluded from the return, or the summary would
# announce the same one after every run forever.
func evaluate(score: Score, upgrades: Upgrades, maze_index: int,
		hp: int, cleared: bool) -> Array:
	var won: Array = []

	for aid in ACHIEVEMENTS:
		var granted := String(ACHIEVEMENTS[aid]["grants"])
		if is_unlocked(granted):
			continue
		if not _met(aid, score, upgrades, maze_index, hp, cleared):
			continue
		earned[granted] = true
		won.append(aid)

	if not won.is_empty():
		_save()
		unlocked.emit(won)
	return won


# Whether one achievement's requirement is met.
#
# One match rather than a callable per table entry: a table of lambdas would put
# the requirement TEXT and the test it describes in two places, and the player
# reads the text and works toward it.
func _met(aid: String, score: Score, upgrades: Upgrades, maze_index: int,
		hp: int, cleared: bool) -> bool:
	# Every "finish a run without X" achievement needs a run that actually
	# happened. Without this, a run that ended before banking anything would
	# satisfy every clean-driving achievement at once by having done nothing.
	var drove := not score.maze_results.is_empty()

	match aid:
		"first_blood": return drove
		"the_tangle": return maze_index >= 2 or cleared
		"the_vault": return maze_index >= 4 or cleared
		"palette_ice": return score.banked >= 50000.0
		"palette_azure": return score.peak_speed >= 5.0
		"palette_cobalt": return drove and score.crashes <= 1 and score.peak_speed >= 4.0
		"palette_indigo": return _best_multiplier(score) >= 3.0
		"palette_magenta": return maze_index >= 1 or cleared
		"palette_acid": return _mazes_under(score, 120.0) >= 2
		"palette_ember": return maze_index >= 3 or cleared
		"palette_violet": return score.clean_turns >= 750
		"palette_orchid": return cleared and score.banked >= 400000.0
		"palette_plum": return score.banked >= 250000.0
		"palette_fuchsia": return score.banked >= 750000.0
		"palette_rose": return score.banked >= 1000000.0
		"palette_crimson": return score.crashes >= 10
		"palette_coral": return score.peak_speed >= 7.0
		"palette_bronze": return score.peak_speed >= 9.0
		"palette_sand": return score.clean_turns >= 250
		"palette_olive": return score.clean_turns >= 1000
		"palette_lime": return score.scraped_turns >= 20
		"palette_jade": return score.scraped_turns >= 100
		"palette_mint": return cleared and score.scraped_turns == 0
		"palette_teal": return drove and upgrades.started_line_count() >= 8
		"palette_aqua": return drove and upgrades.started_line_count() >= 16
		"palette_slate": return cleared and hp >= Tuning.MAX_HP
		"palette_ash": return score.repeat_cells >= 100
		"clear_run": return cleared
		"flawless": return drove and score.crashes == 0
		"ton_up": return score.peak_speed >= 6.0
		"redline": return score.peak_speed >= 8.0
		"clean_hands": return drove and score.scraped_turns == 0
		"wall_dancer": return score.scraped_turns >= 50
		"no_looking_back": return drove and score.repeat_cells == 0
		"century": return score.banked >= 100000.0
		"half_million": return score.banked >= 500000.0
		"survivor": return cleared and hp > 0 and hp < 10
		"cornerer": return score.clean_turns >= 500
		"gatecrasher": return _mazes_fully_gated(score) >= 3
		"legend": return upgrades.has_legendary()
		"maxed": return _has_a_maxed_line(upgrades)
		"specialist": return upgrades.started_line_count() >= 12
		"the_long_way": return _took_every_gate(score)
		"quick_study": return _fastest_maze(score) < 90.0
		"pathfinder": return _fastest_maze(score) < 60.0
		"trailblazer": return _best_multiplier(score) >= 4.0
		"the_shortcut": return _mazes_under(score, 90.0) >= 3
		"steady_hand": return cleared and _slowest_maze(score) <= 150.0
		"metronome": return cleared and _worst_maze_score(score) > 50000.0
		"unbroken": return cleared and hp >= Tuning.MAX_HP / 2
		"purist": return cleared and upgrades.started_line_count() <= 3
		"last_stand": return cleared and hp == 1
		"untouchable": return _best_maze_score(score) >= 100000.0
		"deep_pockets": return _deepest_rank(upgrades) >= 5
		"generalist": return drove and upgrades.started_line_count() >= 20
		"the_scenic_route": return score.repeat_cells >= 500
	return false


# --- Helpers over maze_results ----------------------------------------------
#
# These read per-maze time, multiplier and score, which the Score class has
# recorded since section 8b and which no achievement previously touched. Adding
# a field to Score to satisfy an achievement is forbidden (section 10) -- the
# rule is to pick a requirement the EXISTING data supports, and this is that
# data.
#
# An empty run must never satisfy a "fastest" or "lowest" test by vacuous truth,
# which is the same trap `drove` guards for the clean-driving achievements. Each
# helper below returns a value that FAILS its comparison when nothing was
# banked, rather than one that passes.


# The quickest banked maze, in seconds. INF when nothing was banked, so every
# "under N seconds" test fails on an empty run rather than passing.
func _fastest_maze(score: Score) -> float:
	var best := INF
	for result in score.maze_results:
		best = minf(best, float(result.get("time", INF)))
	return best


# The slowest banked maze. Returns INF when nothing was banked, so a "no maze
# over N seconds" test cannot be satisfied by having driven no mazes.
func _slowest_maze(score: Score) -> float:
	var worst := INF
	for result in score.maze_results:
		if worst == INF:
			worst = 0.0
		worst = maxf(worst, float(result.get("time", 0.0)))
	return worst


func _mazes_under(score: Score, seconds: float) -> int:
	var n := 0
	for result in score.maze_results:
		if float(result.get("time", INF)) < seconds:
			n += 1
	return n


func _best_multiplier(score: Score) -> float:
	var best := 0.0
	for result in score.maze_results:
		best = maxf(best, float(result.get("multiplier", 0.0)))
	return best


# The lowest score banked by any single maze. Zero when nothing was banked, so
# an "every maze above N" test fails on an empty run.
func _worst_maze_score(score: Score) -> float:
	if score.maze_results.is_empty():
		return 0.0
	var worst := INF
	for result in score.maze_results:
		worst = minf(worst, float(result.get("score", 0.0)))
	return worst


# The best single maze SCORE, where _worst_maze_score is the floor. Per-maze
# rather than the run total, so it rewards one exceptional maze rather than
# five ordinary ones -- CENTURY already asks the latter.
func _best_maze_score(score: Score) -> float:
	var best := 0.0
	for result in score.maze_results:
		best = maxf(best, float(result.get("score", 0.0)))
	return best


# The highest rank held in any single line -- depth, where started_line_count()
# measures width. The two pull in opposite directions, which is what makes
# DEEP POCKETS and GENERALIST different goals rather than the same one twice.
func _deepest_rank(upgrades: Upgrades) -> int:
	var best := 0
	for line in upgrades.ranks:
		best = maxi(best, int(upgrades.ranks[line]))
	return best


func _has_a_maxed_line(upgrades: Upgrades) -> bool:
	for line in Upgrades.DEFINITIONS:
		if upgrades.rank(line) > 0 and upgrades.is_maxed(line):
			return true
	return false


# Every gate in a maze taken.
#
# Read off `progress`, which a banked maze already carries: section 8b defines it
# as gates_taken / gates_in_maze, so 1.0 IS "took every gate". A death banks a
# partial maze at its real fraction, which is exactly the distinction wanted.
#
# There is no `gates_taken` field and no Tuning.GATES_PER_MAZE constant -- gates
# are a per-maze entry in Tuning.MAZES. Checked before writing this rather than
# assumed, because an achievement must never be the reason a rules-layer class
# grows a field.
# How many banked mazes had every one of their gates collected. The gate
# achievement above asks for one; this asks for three, so the two sit on the
# same axis at different depths rather than needing a new tally on Score.
func _mazes_fully_gated(score: Score) -> int:
	var n := 0
	for result in score.maze_results:
		if float(result.get("progress", 0.0)) >= 1.0:
			n += 1
	return n


func _took_every_gate(score: Score) -> bool:
	for result in score.maze_results:
		if float(result.get("progress", 0.0)) >= 1.0:
			return true
	return false


func _load() -> void:
	var config := ConfigFile.new()
	# No file on first run is the normal case, not an error -- a fresh player
	# has earned nothing, which is what an empty set already says.
	if config.load(CONFIG_PATH) != OK:
		return
	if not config.has_section(SECTION):
		return
	for id in config.get_section_keys(SECTION):
		if bool(config.get_value(SECTION, id, false)):
			earned[id] = true


func _save() -> void:
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)   # keep the preference sections
	for id in earned:
		config.set_value(SECTION, String(id), true)
	config.save(CONFIG_PATH)
