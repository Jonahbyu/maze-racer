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
		"grants": "colour:cobalt",
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
	return id == id_for(KIND_SHAPE, Tuning.MARKER_SHAPE_DEFAULT) \
		or id == id_for(KIND_DECAL, Tuning.MARKER_DECAL_DEFAULT) \
		or id == id_for(KIND_COLOUR, Tuning.MARKER_COLOUR_DEFAULT)


# Every cosmetic that CAN be locked -- everything but the three defaults.
static func lockable_ids() -> Array:
	var out: Array = []
	for shape in Tuning.MARKER_SHAPES:
		if String(shape["id"]) != Tuning.MARKER_SHAPE_DEFAULT:
			out.append(id_for(KIND_SHAPE, String(shape["id"])))
	for entry in Tuning.MARKER_COLOURS:
		if String(entry["id"]) != Tuning.MARKER_COLOUR_DEFAULT:
			out.append(id_for(KIND_COLOUR, String(entry["id"])))
	for decal in Tuning.MARKER_DECALS:
		if String(decal["id"]) != Tuning.MARKER_DECAL_DEFAULT:
			out.append(id_for(KIND_DECAL, String(decal["id"])))
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
		"legend": return upgrades.has_legendary()
		"maxed": return _has_a_maxed_line(upgrades)
		"specialist": return upgrades.started_line_count() >= 12
		"the_long_way": return _took_every_gate(score)
	return false


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
