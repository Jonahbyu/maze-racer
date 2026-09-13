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
# The shop wallet changed -- earned at the end of a run, or spent in the shop.
signal coins_changed(total: int)

# Beside the preferences rather than in a file of its own: one place a player
# can clear, and one file to keep in step. Settings owns the same path.
const CONFIG_PATH := "user://settings.cfg"
const SECTION := "unlocks"
const WALLET_SECTION := "wallet"

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

	# --- The six non-blade shapes -----------------------------------------
	#
	# Each sits on an axis no other entry uses, which is the rule the collision
	# sweep enforces: two achievements firing on one condition unlock as a pair
	# and spend two entries to ask one question.
	#
	# Two of them need a helper that did not exist -- total run time and total
	# turn volume -- and both are DERIVED from what Score already records
	# rather than being new fields on it. Growing Score to suit an achievement
	# is the thing section 10 forbids outright.
	"the_full_hour": {
		"label": "THE FULL HOUR",
		"requirement": "Clear all five mazes in under 8 minutes total",
		"grants": "shape:teardrop",
	},
	"ironclad": {
		"label": "IRONCLAD",
		"requirement": "Clear all five mazes crashing no more than twice",
		"grants": "shape:keyhole",
	},
	"groundwork": {
		"label": "GROUNDWORK",
		"requirement": "Take 2,000 turns of any kind in one run",
		"grants": "shape:hammer",
	},
	"terminal_velocity": {
		"label": "TERMINAL VELOCITY",
		"requirement": "Reach the 10x speed cap",
		"grants": "shape:shuttle",
	},
	"three_ways": {
		"label": "THREE WAYS",
		"requirement": "Bank a maze at a x6 time multiplier or better",
		"grants": "shape:trident",
	},
	"landfall": {
		"label": "LANDFALL",
		"requirement": "Clear all five mazes taking every gate in each",
		"grants": "shape:beacon",
	},

	# --- The ten object shapes --------------------------------------------
	#
	# Every entry sits at a threshold no other achievement uses, which the
	# collision sweep enforces by measurement rather than by inspection. Where
	# an axis was already occupied the bound is a genuinely different standard
	# rather than a near-miss -- LOCKSMITH at four fully-gated mazes sits
	# between GATECRASHER's three and LANDFALL's five, and each is a distinct
	# statement about how completely a run was driven.
	#
	# None of them needed a new field on Score. That is the constraint section
	# 10 sets: pick a requirement the existing data supports, rather than
	# growing a rules-layer class to suit a cosmetic.
	"locksmith": {
		"label": "LOCKSMITH",
		"requirement": "Collect every gate in four mazes",
		"grants": "shape:key",
	},
	"holdfast": {
		"label": "HOLDFAST",
		"requirement": "Clear all five mazes without crashing",
		"grants": "shape:anchor",
	},
	"fine_print": {
		"label": "FINE PRINT",
		"requirement": "Clear a maze in under 45 seconds",
		"grants": "shape:nib",
	},
	"furrow": {
		"label": "FURROW",
		"requirement": "Re-cross 1,000 cells in one run",
		"grants": "shape:plough",
	},
	"barbed": {
		"label": "BARBED",
		"requirement": "Escape 200 scrapes in one run",
		"grants": "shape:hook",
	},
	"clean_sweep": {
		"label": "CLEAN SWEEP",
		"requirement": "Clear all five mazes without re-crossing a cell",
		"grants": "shape:comb",
	},
	"live_wire": {
		"label": "LIVE WIRE",
		"requirement": "Bank a maze at a x8 time multiplier or better",
		"grants": "shape:bolt",
	},
	"bulwark": {
		"label": "BULWARK",
		"requirement": "Clear all five mazes without touching a wall",
		"grants": "shape:shield",
	},
	"pinpoint": {
		"label": "PINPOINT",
		"requirement": "Bank 250,000 points in a single maze",
		"grants": "shape:pin",
	},
	"scaffold": {
		"label": "SCAFFOLD",
		"requirement": "Finish a run holding 24 upgrade lines",
		"grants": "shape:bracket",
	},

	# --- The twenty tool, craft and mark shapes ----------------------------
	#
	# Forty more cosmetics need forty more achievements, and the binding
	# constraint is not naming them -- it is that NO TWO MAY FIRE ON THE SAME
	# CONDITION, swept over randomised runs. Sixty-odd thresholds on crashes,
	# scrapes, turns, speed, score and HP were already spoken for, so several of
	# these sit on quantities nothing had read yet: the WORST multiplier banked
	# rather than the best, and the SPREAD between a run's fastest and slowest
	# maze.
	#
	# Both are derived from maze_results, which Score already keeps. Section 10
	# forbids growing Score a field to satisfy an achievement, and forty new
	# entries is exactly the pressure that rule exists to resist.
	"draughtsman": {
		"label": "DRAUGHTSMAN",
		"requirement": "Clear a run with every maze above a x2 multiplier",
		"grants": "shape:compass",
	},
	"hew": {
		"label": "HEW",
		"requirement": "Make 1,500 clean turns in one run",
		"grants": "shape:axe",
	},
	"forge": {
		"label": "FORGE",
		"requirement": "Clear a run scoring 600,000",
		"grants": "shape:anvil",
	},
	"spanner": {
		"label": "SPANNER",
		"requirement": "Take a single upgrade line to rank 7",
		"grants": "shape:wrench",
	},
	"firebrand": {
		"label": "FIREBRAND",
		"requirement": "Reach 9.5x speed",
		"grants": "shape:torch",
	},
	"helm": {
		"label": "HELM",
		"requirement": "Clear a run with no maze over 120 seconds",
		"grants": "shape:rudder",
	},
	"windward": {
		"label": "WINDWARD",
		"requirement": "Clear two mazes in under 75 seconds each",
		"grants": "shape:sail",
	},
	"airborne": {
		"label": "AIRBORNE",
		"requirement": "Clear a run in under 6 minutes of driving",
		"grants": "shape:glider",
	},
	"headway": {
		"label": "HEADWAY",
		"requirement": "Clear two mazes in under 60 seconds each",
		"grants": "shape:prow",
	},
	"sounding": {
		"label": "SOUNDING",
		"requirement": "Clear a run re-crossing 20 cells or fewer",
		"grants": "shape:fin",
	},
	"groundbreaker": {
		"label": "GROUNDBREAKER",
		"requirement": "Re-cross 2,000 cells in one run",
		"grants": "shape:spade",
	},
	"coronation": {
		"label": "CORONATION",
		"requirement": "Clear a run banking 400,000 in one maze",
		"grants": "shape:crown",
	},
	"vigil": {
		"label": "VIGIL",
		"requirement": "Clear a run finishing within 5 HP of full",
		"grants": "shape:lantern",
	},
	"monument": {
		"label": "MONUMENT",
		"requirement": "Score 1,500,000 in one run",
		"grants": "shape:obelisk",
	},
	"libation": {
		"label": "LIBATION",
		"requirement": "Clear a run with every maze banking over 120,000",
		"grants": "shape:chalice",
	},
	"insertion": {
		"label": "INSERTION",
		"requirement": "Bank a maze at a x5 time multiplier",
		"grants": "shape:caret",
	},
	"fastener": {
		"label": "FASTENER",
		"requirement": "Finish a run holding 26 upgrade lines",
		"grants": "shape:rivet",
	},
	"gearwork": {
		"label": "GEARWORK",
		"requirement": "Make 2,000 clean turns in one run",
		"grants": "shape:ratchet",
	},
	"reckoning": {
		"label": "RECKONING",
		"requirement": "Collect every gate in two mazes",
		"grants": "shape:tally",
	},
	"warding": {
		"label": "WARDING",
		"requirement": "Clear a run crashing five times or fewer",
		"grants": "shape:sigil",
	},

	# --- The twenty added patterns -----------------------------------------
	#
	# The decals lean on the SAME axes as the shapes above rather than new ones,
	# at different depths -- 900 clean turns against 1,500, three crashes
	# against six. That is deliberate: a pattern is a smaller reward than a
	# silhouette, so it should sit at a nearer milestone on a road the player is
	# already walking, and it keeps each axis a ladder rather than a scatter.
	"triple_time": {
		"label": "TRIPLE TIME",
		"requirement": "Make 900 clean turns in one run",
		"grants": "decal:triband",
	},
	"hairline": {
		"label": "HAIRLINE",
		"requirement": "Clear a maze in under 40 seconds",
		"grants": "decal:pinstripe",
	},
	"cant": {
		"label": "CANT",
		"requirement": "Reach 6.5x speed",
		"grants": "decal:wedges",
	},
	"rungs": {
		"label": "RUNGS",
		"requirement": "Finish a run holding 10 upgrade lines",
		"grants": "decal:ladder",
	},
	"fluted": {
		"label": "FLUTED",
		"requirement": "Escape 75 scrapes in one run",
		"grants": "decal:scallop",
	},
	"machined": {
		"label": "MACHINED",
		"requirement": "Clear a run crashing three times or fewer",
		"grants": "decal:shoulders",
	},
	"toothed": {
		"label": "TOOTHED",
		"requirement": "Escape 150 scrapes in one run",
		"grants": "decal:serrate",
	},
	"cinched": {
		"label": "CINCHED",
		"requirement": "Clear a run in under 7 minutes of driving",
		"grants": "decal:waist",
	},
	"even_split": {
		"label": "EVEN SPLIT",
		"requirement": "Clear a run with under a minute between your fastest and slowest maze",
		"grants": "decal:quarters",
	},
	"broad_gauge": {
		"label": "BROAD GAUGE",
		"requirement": "Score 300,000 in one run",
		"grants": "decal:rails",
	},
	"sinistral": {
		"label": "SINISTRAL",
		"requirement": "Re-cross 250 cells in one run",
		"grants": "decal:offset",
	},
	"backdraft": {
		"label": "BACKDRAFT",
		"requirement": "Crash six times in one run",
		"grants": "decal:arrows",
	},
	"one_cut": {
		"label": "ONE CUT",
		"requirement": "Bank a maze at a x4.5 time multiplier",
		"grants": "decal:delta_cut",
	},
	"fletched": {
		"label": "FLETCHED",
		"requirement": "Reach 7.5x speed",
		"grants": "decal:nock",
	},
	"beaked": {
		"label": "BEAKED",
		"requirement": "Clear three mazes in under 100 seconds each",
		"grants": "decal:beak",
	},
	"collared": {
		"label": "COLLARED",
		"requirement": "Take a single upgrade line to rank 3",
		"grants": "decal:collar",
	},
	"both_ends": {
		"label": "BOTH ENDS",
		"requirement": "Clear a run finishing within 15 HP of full",
		"grants": "decal:bookend",
	},
	"reticle": {
		"label": "RETICLE",
		"requirement": "Bank 180,000 points in a single maze",
		"grants": "decal:crosshair",
	},
	"lattice": {
		"label": "LATTICE",
		"requirement": "Finish a run holding 14 upgrade lines",
		"grants": "decal:grid",
	},
	"barbwork": {
		"label": "BARBWORK",
		"requirement": "Crash three times in one run",
		"grants": "decal:harpoon",
	},
}


# Earned cosmetic ids. Keyed by the namespaced id, never by achievement -- what
# the picker asks is "may I offer this", and an achievement is only how it got
# there.
# The shop wallet: coins banked across every run ever played.
#
# The one piece of state here that is not a cosmetic, and it is allowed for the
# same reason the cosmetics are: NOTHING IN THE SIMULATION MAY READ IT. A run
# starts at zero coins held whatever the wallet says, so this can never change
# how a run plays -- it buys colours and icons and nothing else. The line
# section 10 draws holds: if a purchase would change a number the racer reads, it
# does not belong here.
#
# Banked per MAZE rather than per run (Racer.bank_coins), so a run that ends in a
# death still keeps what its finished mazes earned.
var coins := 0

# When true, nothing is written to disk.
#
# Set by harnesses and instruments, which construct this script directly rather
# than reaching the autoload. Without it a test that buys a cosmetic writes to
# the PLAYER's settings.cfg -- granting them items and spending coins they never
# earned. That is the rule section 12 records for TouchShot and MarkerPickerShot
# in a third place: a tool must not write the state it is inspecting.
var suppress_save := false

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
		"the_full_hour": return cleared and _total_time(score) < 480.0
		"ironclad": return cleared and score.crashes <= 2
		"groundwork": return score.clean_turns + score.scraped_turns >= 2000
		"terminal_velocity": return score.peak_speed >= Tuning.SPEED_CAP
		"three_ways": return _best_multiplier(score) >= 6.0
		"landfall": return cleared and _mazes_fully_gated(score) >= 5
		"locksmith": return _mazes_fully_gated(score) >= 4
		"holdfast": return cleared and score.crashes == 0
		"fine_print": return _fastest_maze(score) < 45.0
		"furrow": return score.repeat_cells >= 1000
		"barbed": return score.scraped_turns >= 200
		"clean_sweep": return cleared and score.repeat_cells == 0
		"live_wire": return _best_multiplier(score) >= 8.0
		"bulwark": return cleared and score.scraped_turns == 0 and score.crashes == 0
		"pinpoint": return _best_maze_score(score) >= 250000.0
		"scaffold": return drove and upgrades.started_line_count() >= 24
		"draughtsman": return cleared and _worst_multiplier(score) >= 2.0
		"hew": return score.clean_turns >= 1500
		"forge": return cleared and score.banked >= 600000.0
		"spanner": return drove and _deepest_rank(upgrades) >= 7
		"firebrand": return score.peak_speed >= 9.5
		"helm": return cleared and _slowest_maze(score) <= 120.0
		"windward": return _mazes_under(score, 75.0) >= 2
		"airborne": return cleared and _total_time(score) < 360.0
		"headway": return _mazes_under(score, 60.0) >= 2
		"sounding": return cleared and score.repeat_cells <= 20
		"groundbreaker": return score.repeat_cells >= 2000
		"coronation": return cleared and _best_maze_score(score) >= 400000.0
		"vigil": return cleared and hp >= Tuning.MAX_HP - 5
		"monument": return score.banked >= 1500000.0
		"libation": return cleared and _worst_maze_score(score) > 120000.0
		"insertion": return _best_multiplier(score) >= 5.0
		"fastener": return drove and upgrades.started_line_count() >= 26
		"gearwork": return score.clean_turns >= 2000
		"reckoning": return _mazes_fully_gated(score) >= 2
		"warding": return cleared and score.crashes <= 5
		"triple_time": return score.clean_turns >= 900
		"hairline": return _fastest_maze(score) < 40.0
		"cant": return score.peak_speed >= 6.5
		"rungs": return drove and upgrades.started_line_count() >= 10
		"fluted": return score.scraped_turns >= 75
		"machined": return cleared and score.crashes <= 3
		"toothed": return score.scraped_turns >= 150
		"cinched": return cleared and _total_time(score) < 420.0
		"even_split": return cleared and _maze_time_spread(score) <= 60.0
		"broad_gauge": return score.banked >= 300000.0
		"sinistral": return score.repeat_cells >= 250
		"backdraft": return score.crashes >= 6
		"one_cut": return _best_multiplier(score) >= 4.5
		"fletched": return score.peak_speed >= 7.5
		"beaked": return _mazes_under(score, 100.0) >= 3
		"collared": return drove and _deepest_rank(upgrades) >= 3
		"both_ends": return cleared and hp >= Tuning.MAX_HP - 15
		"reticle": return _best_maze_score(score) >= 180000.0
		"lattice": return drove and upgrades.started_line_count() >= 14
		"barbwork": return score.crashes >= 3
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
# The whole run's driving time, summed from the banked mazes.
#
# Derived rather than stored: Score already records each maze's time, and
# section 10 forbids growing Score a field to satisfy an achievement -- pick a
# requirement the existing data supports.
#
# It is a SUM of banked mazes, so a run that ended early cannot satisfy an
# "under N total" test by having driven almost nothing; every requirement using
# it is gated on `cleared` as well, which is what makes the bound meaningful.
func _total_time(score: Score) -> float:
	var total := 0.0
	for result in score.maze_results:
		total += float(result.get("time", 0.0))
	return total


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


# The LOWEST multiplier any banked maze earned.
#
# _best_multiplier asks whether a run had one great maze; this asks whether it
# had no bad one, which is a different question about the same data and is the
# only axis left on the multiplier once the best is spoken for at 3, 4, 4.5, 5,
# 6 and 8.
#
# Zero on an empty run, so a "worst above N" test fails rather than passing by
# vacuous truth -- the rule every helper here follows.
func _worst_multiplier(score: Score) -> float:
	if score.maze_results.is_empty():
		return 0.0
	var worst := INF
	for result in score.maze_results:
		worst = minf(worst, float(result.get("multiplier", 0.0)))
	return worst


# The gap between the quickest and slowest banked maze, in seconds.
#
# A CONSISTENCY measure rather than a speed one: a run that solves every maze in
# 70 seconds and one that alternates 40 and 140 can share a total, a fastest and
# a slowest, and are not the same run. Nothing else in the table reads the two
# together.
#
# INF on an empty run so a "spread under N" test cannot pass on no mazes at all.
func _maze_time_spread(score: Score) -> float:
	if score.maze_results.is_empty():
		return INF
	return _slowest_maze(score) - _fastest_maze(score)


# What a cosmetic costs in the shop, by kind.
#
# Priced by how much a kind CHANGES the marker, not by how many exist. A colour
# is a repaint; a shape is a different silhouette and is the half of the marker
# that answers facing (section 12), so it is the dearest. A palette restyles a
# whole maze and sits between them.
#
# A run banks somewhere under 20 coins when driven well, so a shape is several
# good runs and a colour is roughly one. The shop is meant to be a reason to
# come back, not a catalogue cleared in an evening.
const PRICES := {
	KIND_COLOUR: 12,
	KIND_DECAL: 18,
	KIND_PALETTE: 25,
	KIND_SHAPE: 40,
}


# What `id` costs, or 0 if it is not purchasable.
static func price_of(id: String) -> int:
	var parts := id.split(":")
	if parts.size() != 2:
		return 0
	return int(PRICES.get(parts[0], 0))


# Credit the wallet. Called from Game._post_run with what the run's cleared
# mazes banked.
func add_coins(amount: int) -> void:
	if amount <= 0:
		return
	coins += amount
	_save()
	coins_changed.emit(coins)


func can_afford(id: String) -> bool:
	var price := price_of(id)
	return price > 0 and coins >= price


# Buy a cosmetic. Returns whether the purchase happened.
#
# The shop is a SECOND path to a cosmetic, never a replacement for the
# achievement that grants it: achievements still award for free, and buying
# something already earned is refused rather than charged. Both routes write the
# same `earned` set, so nothing downstream -- the pickers, the paired-table
# assertions -- has to know which way an item arrived.
func buy(id: String) -> bool:
	if not cosmetic_exists(id):
		return false
	# Already owned, by either route. Refused rather than charged: taking money
	# for something the player has is the one outcome a shop must never produce.
	if is_unlocked(id):
		return false
	var price := price_of(id)
	if price <= 0 or coins < price:
		return false

	coins -= price
	earned[id] = true
	_save()
	coins_changed.emit(coins)
	unlocked.emit([id])
	return true


func _load() -> void:
	var config := ConfigFile.new()
	# No file on first run is the normal case, not an error -- a fresh player
	# has earned nothing, which is what an empty set already says.
	if config.load(CONFIG_PATH) != OK:
		return
	if not config.has_section(SECTION):
		return
	# The wallet lives in its own section rather than among the earned ids: this
	# section is a set of id -> true, and a number sitting in it would be read
	# back as a cosmetic called "coins" by anything walking the keys.
	coins = int(config.get_value(WALLET_SECTION, "coins", 0))
	for id in config.get_section_keys(SECTION):
		if bool(config.get_value(SECTION, id, false)):
			earned[id] = true


func _save() -> void:
	if suppress_save:
		return
	var config := ConfigFile.new()
	config.load(CONFIG_PATH)   # keep the preference sections
	for id in earned:
		config.set_value(SECTION, String(id), true)
	config.set_value(WALLET_SECTION, "coins", coins)
	config.save(CONFIG_PATH)
