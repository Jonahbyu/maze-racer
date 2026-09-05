# The run score: points earned per maze, multiplied by time left, then banked.
#
# Deliberately node-free and renderer-free, like Racer, so the whole scoring
# rule set stays headlessly testable (CLAUDE.md section 12). Game feeds it
# events; it never reads the world itself.
#
# CLAUDE.md section 8b.
class_name Score
extends RefCounted

# Points earned in the CURRENT maze, before the time multiplier. Banked and
# reset at each maze end.
var maze_subtotal := 0.0

# Sum of every completed maze's multiplied score.
var banked := 0.0

# Seconds spent in the current maze. Drives the time multiplier, and is separate
# from Game.elapsed because that one measures the whole run.
var maze_time := 0.0

# Per-maze history, for the end-of-run breakdown: one entry per completed maze
# with its subtotal, time, multiplier and final score.
var maze_results: Array[Dictionary] = []

# Running tallies, for the HUD and the completion screen.
var clean_turns := 0
var scraped_turns := 0
var crashes := 0

# Distinct cells re-entered this RUN, counted for the summary. Counted once per
# cell, so ten laps of a ten-cell loop is 10, not 100 -- the tally has to agree
# with what was actually charged or the summary contradicts the score.
var repeat_cells := 0

# Whether the racer is currently on ground it has already driven this maze. Set
# by Game on each cell boundary and read by the earning calls below, which pay
# SCORE_EARN_ON_REPEAT (zero) while it holds.
#
# Kept as state here rather than passed to each earn call because travel is fed
# every frame while the cell changes only at a boundary -- a parameter would mean
# Game answering the same question sixty times a second, and the two awards
# could drift apart on it.
var on_repeat_ground := false

# The Score Multiplier upgrade's bonus, as a multiplier on points EARNED.
# Applied at earn time rather than at banking so it compounds with the time
# multiplier rather than replacing it (CLAUDE.md section 7). Game keeps this in
# step with the build; it defaults to 1.0 so Score works standalone in tests.
var earn_multiplier := 1.0


# --- Earning -----------------------------------------------------------------

# Clean travel. Called every frame the racer is actually running -- never while
# parked, which is what stops a crash from paying for the time it costs.
func add_travel(delta: float, speed: float) -> void:
	if delta <= 0.0:
		return
	maze_subtotal += (Tuning.SCORE_PER_SECOND * speed * delta * earn_multiplier
		* _repeat_earn_scale())


# A resolved turn. `scraped` is whether the barrier was draining when it
# resolved -- the player escaped a wall rather than taking the corner clean.
func add_turn(speed: float, scraped: bool) -> void:
	# Still TALLIED on repeat ground, only unpaid: the summary reports what the
	# player did, and a turn taken is a turn taken. Only the points are withheld.
	if scraped:
		scraped_turns += 1
		maze_subtotal += (Tuning.SCORE_TURN_SCRAPED * speed * earn_multiplier
			* _repeat_earn_scale())
	else:
		clean_turns += 1
		maze_subtotal += (Tuning.SCORE_TURN_CLEAN * speed * earn_multiplier
			* _repeat_earn_scale())


# A crash. Flat, not speed-scaled -- see the constant's note.
#
# The subtotal is allowed to go negative here rather than being clamped: a
# clamp would make crashes free once the subtotal hit zero, which is exactly
# when the player is doing worst and least deserves the discount. It is clamped
# once, at maze end, so a maze can never bank a negative score.
func add_crash() -> void:
	crashes += 1
	maze_subtotal -= Tuning.SCORE_CRASH_PENALTY


# The racer entered a cell it has already been in this maze.
#
# Flat, and deliberately NOT scaled by earn_multiplier: that multiplier is a
# bonus on points EARNED, so applying it here would make backtracking more
# expensive the more Score Multiplier the player holds -- an upgrade that
# punishes you for owning it. Same reasoning as the flat crash penalty.
#
# Like a crash, this is allowed to drive the subtotal negative; the single clamp
# at bank time is what stops a wrecked maze eating earlier ones.
func add_repeat() -> void:
	repeat_cells += 1
	maze_subtotal -= Tuning.SCORE_REPEAT_CELL_PENALTY


# What share of an award a cell pays right now. 1.0 on fresh ground, and
# SCORE_EARN_ON_REPEAT on ground already driven this maze -- the rule that makes
# a farming loop unprofitable at source rather than out-pricing it with the
# penalty (see the constant's note).
func _repeat_earn_scale() -> float:
	return Tuning.SCORE_EARN_ON_REPEAT if on_repeat_ground else 1.0


func advance_time(delta: float) -> void:
	maze_time += delta


# --- The time multiplier -----------------------------------------------------

# Asymmetric (CLAUDE.md section 8b): leftover time is rewarded steeply because
# that is the routing skill the score exists to measure, while overtime decays
# gently so two badly-overrun runs stay distinguishable rather than both landing
# on the floor.
func time_multiplier(seconds: float = -1.0) -> float:
	var t := maze_time if seconds < 0.0 else seconds
	if t <= Tuning.SCORE_TIME_BUDGET:
		return 1.0 + (Tuning.SCORE_TIME_BUDGET - t) / Tuning.SCORE_MULT_DIVISOR
	var over := t - Tuning.SCORE_TIME_BUDGET
	return maxf(Tuning.SCORE_MULT_FLOOR,
		1.0 - over / Tuning.SCORE_OVERTIME_DIVISOR)


# Seconds left in the budget. Negative once over, which is what the HUD wants to
# show -- a countdown that stops at zero would hide how far over the player is.
func time_remaining() -> float:
	return Tuning.SCORE_TIME_BUDGET - maze_time


# --- Banking -----------------------------------------------------------------

# Finish a maze and bank it. `progress` is 1.0 for a completed maze; a run that
# ended early passes the fraction of the maze actually reached (gates taken over
# gates available), so a death scores what was achieved rather than nothing.
func bank_maze(index: int, name: String, progress: float = 1.0) -> float:
	var mult := time_multiplier()
	# Clamp here rather than on every crash: a subtotal driven negative by
	# crashes banks zero, but it must not bank a NEGATIVE and eat the scores of
	# mazes already completed.
	var earned := maxf(0.0, maze_subtotal) * clampf(progress, 0.0, 1.0) * mult
	banked += earned

	maze_results.append({
		"index": index,
		"name": name,
		"subtotal": maze_subtotal,
		"time": maze_time,
		"multiplier": mult,
		"progress": progress,
		"score": earned,
	})

	maze_subtotal = 0.0
	maze_time = 0.0
	# A new maze is fresh ground by definition, so the first cell of it must not
	# inherit the last cell of the previous one. Racer clears `visited` per maze
	# for the same reason.
	on_repeat_ground = false
	return earned


# What the run would total if it ended right now, including the maze in
# progress at its current multiplier. This is what the HUD shows, so the number
# on screen is always the score the player actually has.
func projected_total() -> float:
	return banked + maxf(0.0, maze_subtotal) * time_multiplier()


func total() -> float:
	return banked
