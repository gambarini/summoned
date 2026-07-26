extends Node

const MAX_GRIEF := 10
const MAX_RING := 5
## Highest ring with authored 3D terrain (see main.gd's _make_ring_world). All five
## rings are now built, so this equals MAX_RING and progression is uncapped; it stays
## a separate constant so any future unbuilt ring can re-cap extraction here.
const HIGHEST_BUILT_RING := 5

## Anthe's Clock ceiling. Reaching it is NOT a game over — see `is_last_song()`.
const MAX_CLOCK := 10

## --- Economy tuning (GDD "The Cost Model" / "Anthe's Clock") -------------------
## The clock is "a fixed cost per summoning. Always paid. ... Accumulates across every
## run regardless of outcome." Charged once at every run end.
const CLOCK_COST_PER_RUN := 1
## "Every summoning costs Anthe something. Every successful run buys her time." A clean
## extraction buys back the tick it cost, so the clock only really climbs on deaths and on
## waiting — playing well holds it still. It can only ever refund a tick the run actually
## spent: Anthe's capacity "descends across the game", so a good run slows that descent and
## never reverses it (see `end_run_extract`).
const CLOCK_REFUND_ON_EXTRACT := 1
## The GDD's worst summoning tier is "Grief Reserve exhausted — the tribe has nothing
## left to pour into the ceremony", paid as a "heavy Clock advance ... Anthe ages
## noticeably". Summoning on an empty reserve therefore costs an EXTRA tick on top of the
## run's own. This is the grief-zero consequence: a cost, never a fail state.
const CLOCK_COST_EXHAUSTED_SUMMON := 1
## The reserve "replenishes between runs as the tribe recovers" — passive, every run end.
const GRIEF_RECOVERY_PER_RUN := 1
## A death draws harder than the passive recovery gives back, so dying still nets -1
## overall (matching the behaviour before this economy existed); surviving nets +1.
const GRIEF_COST_ON_DEATH := 2
## Waiting at the base trades one tick of Anthe's Clock for reserve recovery.
const GRIEF_GAIN_ON_WAIT := 2

var run_count: int = 0
var grief_reserve: int = MAX_GRIEF
var extractions: int = 0
var clock_ticks: int = 0
## Which ring the next/current run takes place in (1..MAX_RING). `main.gd` reads
## this to pick the 3D terrain + per-ring enemy spawns. Progression rule is a
## minimal placeholder (extract advances a ring, death resets to 1) pending the
## real run-structure design — see `advance_ring()` / `reset_ring()`.
var current_ring: int = 1

## --- Per-run map seed (roguelike map variety) ---------------------------------
## Each ring world + the enemy layout derives its RNG from `ring_seed(local)`, which
## offsets a per-summon `run_seed` onto every layer's local constant. `run_seed == 0`
## reproduces the original byte-for-byte pinned layouts (the look-reference baseline),
## so the default — and any scene that never calls `roll_run_seed()` (spikes, tests) —
## stays unchanged. `main.gd` rolls a fresh seed at the start of each run.
var run_seed: int = 0
## Debug: when true, `roll_run_seed()` pins `run_seed` to 0 (the stable reference
## layout). Flip on to reproduce the pre-roguelike fixed maps on demand.
var lock_seed: bool = false

## --- Persistence --------------------------------------------------------------
## The between-run economy (reserve, clock, ring, tallies) is the whole point of the meta
## layer, so it survives quitting. Written at explicit call sites ONLY — a run end, a
## base decision — and never on assignment: `test_runner.gd` and `warrior_integ_test.gd`
## poke `grief_reserve` directly to drive their assertions, and a save-on-write would
## overwrite the player's file. Those suites also flip `persist_enabled` off.
const SAVE_PATH := "user://summoned_save.cfg"
const SAVE_SECTION := "meta"
## Set false from a test/spike scene before mutating state, so nothing touches the file.
var persist_enabled: bool = true


func _ready() -> void:
	load_game()


## Write the meta layer to disk. `run_seed` is deliberately NOT saved: reloading should
## deal a fresh map, not replay the last run's layout.
func save_game() -> void:
	if not persist_enabled:
		return
	var cfg := ConfigFile.new()
	cfg.set_value(SAVE_SECTION, "run_count", run_count)
	cfg.set_value(SAVE_SECTION, "grief_reserve", grief_reserve)
	cfg.set_value(SAVE_SECTION, "extractions", extractions)
	cfg.set_value(SAVE_SECTION, "clock_ticks", clock_ticks)
	cfg.set_value(SAVE_SECTION, "current_ring", current_ring)
	var err: int = cfg.save(SAVE_PATH)
	if err != OK:
		push_warning("GameState: could not write %s (error %d)" % [SAVE_PATH, err])


## Restore a previous session; returns true when a save was read. A missing file is the
## normal first-launch path, not a warning. Every value is clamped, so a stale or
## hand-edited file cannot push the run loop out of range.
func load_game() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return false
	run_count = maxi(int(cfg.get_value(SAVE_SECTION, "run_count", run_count)), 0)
	extractions = maxi(int(cfg.get_value(SAVE_SECTION, "extractions", extractions)), 0)
	grief_reserve = clampi(
		int(cfg.get_value(SAVE_SECTION, "grief_reserve", grief_reserve)), 0, MAX_GRIEF)
	clock_ticks = clampi(
		int(cfg.get_value(SAVE_SECTION, "clock_ticks", clock_ticks)), 0, MAX_CLOCK)
	current_ring = clampi(
		int(cfg.get_value(SAVE_SECTION, "current_ring", current_ring)), 1, HIGHEST_BUILT_RING)
	return true


## Wipe the save and restore a first-launch tribe — for a future "new game" entry point,
## and for clearing a bad file by hand.
func reset_save() -> void:
	run_count = 0
	grief_reserve = MAX_GRIEF
	extractions = 0
	clock_ticks = 0
	current_ring = 1
	if persist_enabled:
		DirAccess.remove_absolute(SAVE_PATH)


## Roll the seed that defines this run's map. Call once when a run begins. Locked mode
## pins it to 0; otherwise a fresh random seed, stored so the run stays reproducible
## (a future replay-seed / daily-run hook can assign `run_seed` directly instead).
func roll_run_seed() -> void:
	if lock_seed:
		run_seed = 0
		return
	randomize()
	run_seed = randi()

## Mix this run's seed onto a layer's local constant. Layers keep distinct local seeds
## (so they don't correlate within a run); `run_seed` shifts the whole set per run.
## `run_seed == 0` returns the local seed unchanged, preserving the pinned layouts.
func ring_seed(local_seed: int) -> int:
	return local_seed + run_seed

func starting_coherence() -> int:
	if grief_reserve >= 7:
		return 10
	elif grief_reserve >= 4:
		return 7
	return 4

## How whole vs. raw the warrior reforms this summon, from the tribe's grief reserve
## (0 high/whole .. 3 critical/raw). Mirrors `starting_coherence`'s thresholds and extends
## them to a 4th bucket: a fully-depleted tribe calls back something at its rawest. Read
## by the 3D warrior's coherence spectrum (cape tatter / Hollow size / notation density).
func coherence_tier() -> int:
	if grief_reserve >= 7:
		return 0
	elif grief_reserve >= 4:
		return 1
	elif grief_reserve >= 1:
		return 2
	return 3


## --- Anthe's Clock ------------------------------------------------------------

## Advance the clock one tick. Returns false when it is already at MAX_CLOCK, and any
## caller that *trades* something for a tick (waiting) MUST honour that — otherwise the
## trade becomes free forever the moment the clock caps.
func advance_clock() -> bool:
	if clock_ticks >= MAX_CLOCK:
		return false
	clock_ticks += 1
	return true


## Advance up to `ticks`, returning how many actually landed (fewer at the cap). Callers
## that refund a tick MUST refund no more than this, or the clock runs backwards.
func _advance_clock_by(ticks: int) -> int:
	var spent: int = 0
	for _i in range(ticks):
		if advance_clock():
			spent += 1
	return spent


## LAST SONG is a *mode*, not a game over. Per the GDD the clock crossing "is not an
## ending — it is a transition", and Last Song is "the hardest recovery arc. It is still
## a recovery arc." So this drives amplified enemies (`main.gd`) and the base readout,
## and an extraction can still buy the clock back down out of it.
##
## Seam: the GDD's real trigger is the tribe falling below its floor (Anthe lost with no
## surviving adult). That needs a tribe roster this autoload does not have yet, so the
## clock cap stands in for it — repoint this function when the roster lands.
func is_last_song() -> bool:
	return clock_ticks >= MAX_CLOCK


## --- Run boundaries -----------------------------------------------------------
## `main.gd` owns the scene flow (signals, race guards, scene change); the economy lives
## here so there is one place to read the whole cost model.

## Called as a run begins. Charges the summoning's grief-exhaustion surcharge: an empty
## reserve means the ceremony is paid for out of Anthe instead of out of the tribe.
func begin_summon() -> void:
	if grief_reserve <= 0:
		_advance_clock_by(CLOCK_COST_EXHAUSTED_SUMMON)
	save_game()


## The run ended in death. The tribe draws hard on the reserve to absorb it (net -1 after
## the passive recovery every run gets) and the clock keeps its unrefunded tick.
func end_run_death() -> void:
	run_count += 1
	_advance_clock_by(CLOCK_COST_PER_RUN)
	grief_reserve = clampi(
		grief_reserve - GRIEF_COST_ON_DEATH + GRIEF_RECOVERY_PER_RUN, 0, MAX_GRIEF)
	reset_ring()
	save_game()


## The run ended in a clean extraction. The reserve recovers and the run buys Anthe back
## the tick it cost, so a surviving warrior holds the clock still instead of draining it.
func end_run_extract() -> void:
	run_count += 1
	extractions += 1
	var spent: int = _advance_clock_by(CLOCK_COST_PER_RUN)
	# Refund only what this run actually spent. At the cap nothing was spent, so nothing is
	# refunded — the clock is a ratchet, and reaching LAST SONG is not something a good run
	# undoes. (Recovery from Last Song is the *tribe* rebuilding, not Anthe getting younger.)
	clock_ticks = maxi(clock_ticks - mini(CLOCK_REFUND_ON_EXTRACT, spent), 0)
	grief_reserve = clampi(grief_reserve + GRIEF_RECOVERY_PER_RUN, 0, MAX_GRIEF)
	advance_ring()
	save_game()


## --- Waiting at the base ------------------------------------------------------

## Is the tick-for-reserve trade available at all?
func can_wait() -> bool:
	return clock_ticks < MAX_CLOCK and grief_reserve < MAX_GRIEF


## Why waiting is unavailable, for the base screen to show. Empty when it is available.
func wait_blocked_reason() -> String:
	if grief_reserve >= MAX_GRIEF:
		return "RESERVE FULL"
	if clock_ticks >= MAX_CLOCK:
		return "NO TIME LEFT"
	return ""


## Wait before the next summoning: the reserve recovers, but "waiting is not free — the
## world continues", so it costs a tick of Anthe's Clock. Returns false and changes
## nothing when the trade is unavailable. The clock IS the rate limit here — this used to
## hand out reserve for nothing once the clock capped, so a player could sit at the base
## and refill for free forever.
func wait() -> bool:
	if not can_wait():
		return false
	if not advance_clock():
		return false
	grief_reserve = mini(grief_reserve + GRIEF_GAIN_ON_WAIT, MAX_GRIEF)
	save_game()
	return true


## --- Ring access --------------------------------------------------------------
## Placeholder progression: a successful extraction pushes deeper one ring, capped at
## HIGHEST_BUILT_RING so extraction never lands on an unbuilt ring (which would render
## Ring 1's terrain mislabeled).
##
## Known divergence from the GDD: "Deeper rings open when Anthe's summoning becomes
## strong enough to anchor the warrior there ... The warrior does not earn access. The
## tribe does." Ring access should key off the tribe's phase, not the warrior's
## extraction count. Left as-is deliberately — tribe phases do not exist yet.
func advance_ring() -> void:
	current_ring = mini(current_ring + 1, HIGHEST_BUILT_RING)

## Placeholder progression: dying ends the run, so the next summon starts at Ring 1.
func reset_ring() -> void:
	current_ring = 1
