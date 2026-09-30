extends Node

const EnemyScene := preload("res://scenes/enemy.tscn")
const WarriorScene := preload("res://scenes/warrior.tscn")
const EnemyScript = preload("res://scripts/enemy.gd")
const WarriorScript = preload("res://scripts/warrior.gd")

var _pass := 0
var _fail := 0
var _skip := 0

func _ready() -> void:
	print("\n=== SUMMONED TEST SUITE ===")
	# The specs below assign GameState fields directly to drive their assertions. Saving
	# is off for the whole suite so a test run can never overwrite the player's save;
	# _test_persistence() turns it back on for its own scope and restores the file after.
	GameState.persist_enabled = false
	_test_game_state()
	_test_economy()
	_test_persistence()
	_test_enemy_hits()
	_test_enemy_states()
	_test_warrior_coherence()
	_test_song()
	_test_clear_count()
	_test_creature_roster()
	_test_input_map()
	_test_warrior_damage()
	_test_locomotion()
	_test_enemy_pace()
	_test_strike_poses()
	print("\n%d passed  %d failed  %d skipped" % [_pass, _fail, _skip])


# ── helpers ─────────────────────────────────────────────────────────────────

func _ok(label: String, cond: bool) -> void:
	if cond:
		print("  PASS  " + label)
		_pass += 1
	else:
		print("  FAIL  " + label)
		_fail += 1

func _enemy(freq: EnemyScript.Freq) -> CharacterBody2D:
	var e := EnemyScene.instantiate() as CharacterBody2D
	add_child(e)
	e.frequency = freq
	return e

func _warrior(grief: int) -> CharacterBody2D:
	GameState.grief_reserve = grief
	var w := WarriorScene.instantiate() as CharacterBody2D
	add_child(w)
	return w

const EnemyFleerScene  := preload("res://scenes/enemy_fleer.tscn")
const EnemyPhaserScene := preload("res://scenes/enemy_phaser.tscn")
const EnemyFleerScript = preload("res://scripts/enemy_fleer.gd")
const EnemyPhaserScript = preload("res://scripts/enemy_phaser.gd")


# ── InputMap ─────────────────────────────────────────────────────────────────

# The bindings live in `project.godot`, so these specs are the only thing that proves
# they reached disk — an action created live in the editor works in a live test and is
# missing headless. They also guard the bug that made this suite grow: `interact` was
# bound to E while `base.gd` orbited on raw E, so pressing E to look changed scene.
# Roadmap 4: the per-ring creature roster that replaced main.gd's _spawn_test_* harness.
# Spawns into a throwaway parent, so nothing here needs main.tscn or the 3D rig.
func _test_creature_roster() -> void:
	print("\n[Creature roster: per-ring table]")
	const HOME_SAFE := 260.0  # mirrors main.gd's spawn hygiene
	const MARGIN := 140.0
	var Roster: GDScript = load("res://scripts/creature_roster.gd")
	var saved_ring: int = GameState.current_ring
	var saved_seed: int = GameState.run_seed
	var saved_lock: bool = GameState.lock_seed

	_ok("every rostered creature has a cel-mesh (no billboard fallback)",
			Roster.mesh_gaps().is_empty())

	# --- Ring 1 population comes through the table -----------------------------
	GameState.run_seed = 12345
	var bag: Node = _spawn_roster(Roster, 1, HOME_SAFE, MARGIN)
	var thresholds: Array = _of_class(bag, &"CreatureThreshold")
	var walkers: Array = _of_class(bag, &"CreaturePaleWalker")
	_ok("Ring 1 spawns 3 Thresholds", thresholds.size() == 3)
	_ok("Ring 1 spawns a 7-walker herd", walkers.size() == 7)

	# --- Spawn hygiene: clear of the summon point, inside the inset box --------
	var lo: Vector2 = SimSpace.box_min_px() + Vector2(MARGIN, MARGIN)
	var hi: Vector2 = SimSpace.box_max_px() - Vector2(MARGIN, MARGIN)
	var clear_of_home: bool = true
	var in_box: bool = true
	for c in bag.get_children():
		var p: Vector2 = (c as Node2D).global_position
		if p.distance_to(SimSpace.SIM_ORIGIN) < HOME_SAFE - 0.01:
			clear_of_home = false
		if p.x < lo.x or p.x > hi.x or p.y < lo.y or p.y > hi.y:
			in_box = false
	_ok("nothing spawns inside the home-safe radius", clear_of_home)
	_ok("nothing spawns outside the margin-inset box", in_box)

	# --- The herd is still a collective after roster spawning ------------------
	var web_complete: bool = true
	for w in walkers:
		if w._mates.size() != 7 or not w._mates.has(w):
			web_complete = false
	_ok("every walker holds the whole herd, self included", web_complete)
	var herd_centre: Vector2 = Vector2.ZERO
	for w in walkers:
		herd_centre += (w as Node2D).global_position
	herd_centre /= walkers.size()
	var grouped: bool = true
	for w in walkers:
		if (w as Node2D).global_position.distance_to(herd_centre) > 130.0:
			grouped = false
	_ok("the herd spawns as one group, not scattered", grouped)

	# One member spotting the warrior pings the whole web (_alert_herd is the broadcast
	# side; herd_alert is what each mate receives), so all 7 go Uneasy together.
	walkers[0]._alert_herd(SimSpace.SIM_ORIGIN)
	var all_uneasy: bool = true
	for w in walkers:
		if w.get_state() != CreaturePaleWalker.UNEASY:
			all_uneasy = false
	_ok("one member's alert makes all 7 uneasy", all_uneasy)

	# One member struck -> all 7 fragment (a single hit does not kill: hp is 2).
	walkers[3].receive_hit(EnemyScript.Freq.DISSONANT)
	var all_scattered: bool = true
	for w in walkers:
		if w.get_state() != CreaturePaleWalker.SCATTERED:
			all_scattered = false
	_ok("a strike on one scatters all 7", all_scattered)

	# --- Per-run layout: seeded, varied, and pinnable --------------------------
	var layout_a: Array = _positions(bag)
	GameState.run_seed = 12345
	var bag2: Node = _spawn_roster(Roster, 1, HOME_SAFE, MARGIN)
	_ok("the same run_seed reproduces the layout", _positions(bag2) == layout_a)
	GameState.run_seed = 999
	var bag3: Node = _spawn_roster(Roster, 1, HOME_SAFE, MARGIN)
	_ok("a different run_seed moves the creatures", _positions(bag3) != layout_a)
	GameState.lock_seed = true
	GameState.roll_run_seed()
	var bag4: Node = _spawn_roster(Roster, 1, HOME_SAFE, MARGIN)
	GameState.roll_run_seed()
	var bag5: Node = _spawn_roster(Roster, 1, HOME_SAFE, MARGIN)
	_ok("lock_seed pins the layout across runs", _positions(bag4) == _positions(bag5))
	GameState.lock_seed = false

	# --- A ring gains creatures by editing the table, nothing else -------------
	GameState.run_seed = 4242
	var bag_r2: Node = _spawn_roster(Roster, 2, HOME_SAFE, MARGIN)
	_ok("Ring 2's table entry spawns without touching main.gd",
			_of_class(bag_r2, &"CreatureThreshold").size() == 2)
	var bag_r5: Node = _spawn_roster(Roster, 5, HOME_SAFE, MARGIN)
	_ok("a ring with no table entry spawns nothing", bag_r5.get_child_count() == 0)

	for b in [bag, bag2, bag3, bag4, bag5, bag_r2, bag_r5]:
		b.queue_free()
	GameState.current_ring = saved_ring
	GameState.run_seed = saved_seed
	GameState.lock_seed = saved_lock


func _spawn_roster(roster: GDScript, ring: int, home_safe: float, margin: float) -> Node:
	var bag := Node.new()
	add_child(bag)
	roster.spawn(bag, ring, null, home_safe, margin)
	return bag


func _of_class(bag: Node, cls: StringName) -> Array:
	var out: Array = []
	for c in bag.get_children():
		var s: Script = c.get_script()
		if s != null and s.get_global_name() == cls:
			out.append(c)
	return out


func _positions(bag: Node) -> Array:
	var out: Array = []
	for c in bag.get_children():
		out.append((c as Node2D).global_position)
	return out


func _test_input_map() -> void:
	print("\n[InputMap bindings]")

	for action in ["orbit_left", "orbit_right", "venture_out"]:
		_ok("action %s exists" % action, InputMap.has_action(action))

	_ok("stale E-bound 'interact' action is gone", not InputMap.has_action("interact"))

	# No verb the player can hold to orbit may share a key with a verb that fires once —
	# that is exactly the double-booking this item fixed.
	var orbit_keys := _physical_keys("orbit_left") + _physical_keys("orbit_right")
	for action in ["venture_out", "wait", "dash", "song", "resonance", "extract"]:
		if not InputMap.has_action(action):
			continue
		var clash := false
		for k in _physical_keys(action):
			if orbit_keys.has(k):
				clash = true
		_ok("%s shares no key with orbit" % action, not clash)

	_ok("orbit_left is Q/Left",   _physical_keys("orbit_left").has(KEY_Q) and _physical_keys("orbit_left").has(KEY_LEFT))
	_ok("orbit_right is E/Right", _physical_keys("orbit_right").has(KEY_E) and _physical_keys("orbit_right").has(KEY_RIGHT))
	_ok("venture_out is Enter",   _physical_keys("venture_out").has(KEY_ENTER))

func _physical_keys(action: String) -> Array:
	var keys := []
	for ev in InputMap.action_get_events(action):
		var key_ev := ev as InputEventKey
		if key_ev != null:
			keys.append(key_ev.physical_keycode)
	return keys


# ── GameState ────────────────────────────────────────────────────────────────

func _test_game_state() -> void:
	print("\n[GameState.starting_coherence]")
	var saved := GameState.grief_reserve

	GameState.grief_reserve = 10
	_ok("grief=10 → 10", GameState.starting_coherence() == 10)
	GameState.grief_reserve = 7
	_ok("grief=7  → 10", GameState.starting_coherence() == 10)
	GameState.grief_reserve = 6
	_ok("grief=6  → 7",  GameState.starting_coherence() == 7)
	GameState.grief_reserve = 4
	_ok("grief=4  → 7",  GameState.starting_coherence() == 7)
	GameState.grief_reserve = 3
	_ok("grief=3  → 4",  GameState.starting_coherence() == 4)
	GameState.grief_reserve = 0
	_ok("grief=0  → 4",  GameState.starting_coherence() == 4)

	GameState.grief_reserve = saved


# ── GameState: the between-run economy ──────────────────────────────────

func _test_economy() -> void:
	print("\n[GameState economy]")
	var snapshot: Array = [GameState.grief_reserve, GameState.clock_ticks,
		GameState.current_ring, GameState.run_count, GameState.extractions]

	# Waiting trades one tick of Anthe's Clock for reserve recovery.
	GameState.grief_reserve = 4
	GameState.clock_ticks = 2
	_ok("wait() succeeds when both sides have room", GameState.wait())
	_ok("wait() adds reserve", GameState.grief_reserve == 4 + GameState.GRIEF_GAIN_ON_WAIT)
	_ok("wait() costs one tick", GameState.clock_ticks == 3)

	# The regression this closes: at a capped clock, waiting used to be free reserve.
	GameState.grief_reserve = 4
	GameState.clock_ticks = GameState.MAX_CLOCK
	_ok("wait() refused at a capped clock", not GameState.wait())
	_ok("refused wait grants no reserve", GameState.grief_reserve == 4)

	GameState.grief_reserve = GameState.MAX_GRIEF
	GameState.clock_ticks = 2
	_ok("wait() refused on a full reserve", not GameState.wait())
	_ok("refused wait costs no tick", GameState.clock_ticks == 2)

	# advance_clock() must report whether it actually moved.
	GameState.clock_ticks = GameState.MAX_CLOCK - 1
	_ok("advance_clock() true with room", GameState.advance_clock())
	_ok("advance_clock() false at the cap", not GameState.advance_clock())
	_ok("clock never exceeds MAX_CLOCK", GameState.clock_ticks == GameState.MAX_CLOCK)

	# Death draws the reserve down net -1; a clean extraction recovers and buys the tick back.
	GameState.grief_reserve = 6
	GameState.clock_ticks = 4
	GameState.current_ring = 3
	GameState.end_run_death()
	_ok("death nets -1 reserve", GameState.grief_reserve == 5)
	_ok("death spends a tick", GameState.clock_ticks == 5)
	_ok("death returns to Ring 1", GameState.current_ring == 1)

	GameState.grief_reserve = 6
	GameState.clock_ticks = 4
	GameState.current_ring = 3
	GameState.end_run_extract()
	_ok("extraction recovers reserve", GameState.grief_reserve == 7)
	_ok("extraction holds the clock still", GameState.clock_ticks == 4)
	_ok("extraction descends a ring", GameState.current_ring == 4)

	# The clock is a ratchet: at the cap an extraction refunds nothing, because nothing was
	# spent. A good run must never make Anthe younger or undo LAST SONG.
	GameState.clock_ticks = GameState.MAX_CLOCK
	GameState.current_ring = 2
	GameState.end_run_extract()
	_ok("extraction at the cap does not rewind the clock",
		GameState.clock_ticks == GameState.MAX_CLOCK)
	_ok("extraction at the cap leaves LAST SONG standing", GameState.is_last_song())

	# Grief zero is a cost, not a fail state: the ceremony is paid out of Anthe instead.
	GameState.grief_reserve = 0
	GameState.clock_ticks = 3
	GameState.begin_summon()
	_ok("exhausted summon ages the clock",
		GameState.clock_ticks == 3 + GameState.CLOCK_COST_EXHAUSTED_SUMMON)
	GameState.grief_reserve = 5
	GameState.clock_ticks = 3
	GameState.begin_summon()
	_ok("funded summon costs no extra tick", GameState.clock_ticks == 3)
	_ok("is_last_song() false below the cap", not GameState.is_last_song())
	GameState.clock_ticks = GameState.MAX_CLOCK
	_ok("is_last_song() true at the cap", GameState.is_last_song())

	GameState.grief_reserve = snapshot[0]
	GameState.clock_ticks = snapshot[1]
	GameState.current_ring = snapshot[2]
	GameState.run_count = snapshot[3]
	GameState.extractions = snapshot[4]


# ── GameState: save/load round-trip ─────────────────────────────────────

# This is the one spec that needs the disk, so it snapshots the player's save file,
# round-trips through it, and puts the original bytes back.
func _test_persistence() -> void:
	print("\n[GameState save/load]")
	var had_file: bool = FileAccess.file_exists(GameState.SAVE_PATH)
	var backup: PackedByteArray = PackedByteArray()
	if had_file:
		backup = FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
	var snapshot: Array = [GameState.run_count, GameState.grief_reserve,
		GameState.extractions, GameState.clock_ticks, GameState.current_ring]

	GameState.persist_enabled = true
	GameState.run_count = 17
	GameState.grief_reserve = 3
	GameState.extractions = 5
	GameState.clock_ticks = 6
	GameState.current_ring = 4
	GameState.save_game()
	GameState.run_count = 0
	GameState.grief_reserve = GameState.MAX_GRIEF
	GameState.extractions = 0
	GameState.clock_ticks = 0
	GameState.current_ring = 1
	_ok("load_game() reads a written save", GameState.load_game())
	_ok("run_count round-trips", GameState.run_count == 17)
	_ok("grief_reserve round-trips", GameState.grief_reserve == 3)
	_ok("extractions round-trips", GameState.extractions == 5)
	_ok("clock_ticks round-trips", GameState.clock_ticks == 6)
	_ok("current_ring round-trips", GameState.current_ring == 4)

	# A stale or hand-edited file must not push the run loop out of range.
	var cfg := ConfigFile.new()
	cfg.set_value(GameState.SAVE_SECTION, "clock_ticks", 999)
	cfg.set_value(GameState.SAVE_SECTION, "current_ring", 99)
	cfg.set_value(GameState.SAVE_SECTION, "grief_reserve", -5)
	cfg.save(GameState.SAVE_PATH)
	GameState.load_game()
	_ok("out-of-range clock clamps", GameState.clock_ticks == GameState.MAX_CLOCK)
	_ok("out-of-range ring clamps", GameState.current_ring == GameState.HIGHEST_BUILT_RING)
	_ok("negative reserve clamps", GameState.grief_reserve == 0)

	GameState.persist_enabled = false
	GameState.run_count = snapshot[0]
	GameState.grief_reserve = snapshot[1]
	GameState.extractions = snapshot[2]
	GameState.clock_ticks = snapshot[3]
	GameState.current_ring = snapshot[4]
	if had_file:
		var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(backup)
			f.close()
	else:
		DirAccess.remove_absolute(GameState.SAVE_PATH)


# ── Enemy: receive_hit return values + hp ────────────────────────────────────

func _test_enemy_hits() -> void:
	print("\n[Enemy.receive_hit]")

	var e := _enemy(EnemyScript.Freq.HARMONIC)
	var r: int = e.receive_hit(EnemyScript.Freq.DISSONANT)
	_ok("opposite freq → CORRECT",        r == EnemyScript.HitResult.CORRECT)
	_ok("correct hit decrements hp",      e.hp == 1)
	_ok("correct hit does not amplify",   not e._amplified)
	e.queue_free()

	e = _enemy(EnemyScript.Freq.HARMONIC)
	r = e.receive_hit(EnemyScript.Freq.HARMONIC)
	_ok("same freq → WRONG",              r == EnemyScript.HitResult.WRONG)
	_ok("wrong hit amplifies",            e._amplified)
	_ok("wrong hit does not decrement hp", e.hp == 2)
	e.queue_free()

	e = _enemy(EnemyScript.Freq.DISSONANT)
	r = e.receive_hit(EnemyScript.Freq.HARMONIC)
	_ok("DISSONANT enemy: opposite → CORRECT", r == EnemyScript.HitResult.CORRECT)
	e.queue_free()

	# Two correct hits exhaust hp → DEAD
	e = _enemy(EnemyScript.Freq.DISSONANT)
	e.receive_hit(EnemyScript.Freq.HARMONIC)
	e.receive_hit(EnemyScript.Freq.HARMONIC)
	_ok("two correct hits → DEAD state",  e._state == EnemyScript.State.DEAD)
	# tween calls queue_free, do not free manually

	# Hit on already-dead enemy
	e = _enemy(EnemyScript.Freq.DISSONANT)
	e._state = EnemyScript.State.DEAD
	r = e.receive_hit(EnemyScript.Freq.HARMONIC)
	_ok("hit on dead enemy → WRONG",      r == EnemyScript.HitResult.WRONG)
	_ok("dead enemy hp unchanged",        e.hp == 2)
	e.queue_free()


# ── Enemy: reveal + color logic ──────────────────────────────────────────────

func _test_enemy_states() -> void:
	print("\n[Enemy state & color]")

	var e := _enemy(EnemyScript.Freq.HARMONIC)
	_ok("default color is neutral",       e._current_color() == EnemyScript.NEUTRAL_COLOR)

	e.reveal(1.5)
	_ok("reveal sets _revealed",          e._revealed)
	_ok("reveal sets timer to 1.5",       e._reveal_timer == 1.5)
	_ok("revealed color is freq color",   e._current_color() == EnemyScript.COLORS[EnemyScript.Freq.HARMONIC])

	e._amplified = true
	_ok("amplified overrides revealed",   e._current_color() == Color(0.831, 0.502, 0.227, 1))

	e._amplified = false
	e._revealed = false
	_ok("cleared → neutral again",        e._current_color() == EnemyScript.NEUTRAL_COLOR)
	e.queue_free()


# ── Warrior: starting coherence from grief ───────────────────────────────────

func _test_warrior_coherence() -> void:
	print("\n[Warrior starting coherence]")

	var w := _warrior(10)
	_ok("grief=10 → coherence 10", w.coherence == 10)
	w.queue_free()

	w = _warrior(5)
	_ok("grief=5  → coherence 7",  w.coherence == 7)
	w.queue_free()

	w = _warrior(2)
	_ok("grief=2  → coherence 4",  w.coherence == 4)
	w.queue_free()


# ── Warrior: take_damage — the summon grace and the async death ──────────────

# Roadmap 5. This spec carried a permanent skip for two reasons, both now settled as
# design rather than bug:
#   1. The warrior boots into State.SUMMONING and take_damage() early-returns. That is
#      the deliberate summon grace — input is locked through the materialise animation,
#      so the window is invulnerable. It is now named (warrior.gd SUMMON_INVULN_TIME)
#      and asserted here instead of worked around.
#   2. A lethal hit does NOT emit warrior_died synchronously: it enters State.DYING and
#      arms $DyingTimer so the death plays out before main.gd swaps scenes.
# The suite runs synchronously inside _ready() — awaiting real time would outlive the
# harness's --quit-after — so state transitions are driven by emitting the very timeout
# signals _ready() wired up. That asserts the wiring rather than bypassing it: cut the
# DyingTimer connection and "DyingTimer.timeout emits warrior_died" fails.
func _test_warrior_damage() -> void:
	print("\n[Warrior.take_damage]")

	var w := _warrior(10)
	var summoning: Timer = w.get_node("SummoningTimer")
	var hurt: Timer = w.get_node("HurtTimer")
	var dying: Timer = w.get_node("DyingTimer")

	# --- the summon grace ---------------------------------------------------
	# No assert on summoning.wait_time: _ready() assigns it from SUMMON_INVULN_TIME, so
	# comparing the two could never fail. What is worth pinning is the behaviour — the
	# grace is armed at boot, ignores damage, and ends by dropping to IDLE.
	_ok("boots into SUMMONING",           w._state == WarriorScript.State.SUMMONING)
	_ok("the grace is armed at boot",     not summoning.is_stopped())
	w.take_damage(3)
	_ok("SUMMONING ignores damage",       w.coherence == 10)

	summoning.stop()
	summoning.timeout.emit()
	_ok("summon timeout drops to IDLE",   w._state == WarriorScript.State.IDLE)

	# --- a live warrior takes hits ------------------------------------------
	w.take_damage(3)
	_ok("damage reduces coherence",       w.coherence == 7)
	_ok("non-lethal hit enters HURT",     w._state == WarriorScript.State.HURT)

	w.take_damage(3)
	_ok("HURT blocks further damage",     w.coherence == 7)
	hurt.stop()
	hurt.timeout.emit()
	_ok("hurt timeout returns to IDLE",   w._state == WarriorScript.State.IDLE)

	w.chain = 3
	w.take_damage(1)
	_ok("damage resets chain",            w.chain == 0)
	_ok("coherence 7 → 6",                w.coherence == 6)
	hurt.stop()
	hurt.timeout.emit()

	# --- the lethal hit: state now, signal later ----------------------------
	var died: Array = [0]
	w.warrior_died.connect(func(): died[0] += 1)
	w.coherence = 1
	w.take_damage(1)
	_ok("coherence floored at 0",         w.coherence == 0)
	_ok("lethal hit enters DYING",        w._state == WarriorScript.State.DYING)
	_ok("warrior_died is NOT synchronous", died[0] == 0)
	_ok("death arms DyingTimer",          not dying.is_stopped())
	# DyingTimer's length stays scene-owned (warrior.tscn) — it is an animation duration,
	# not a gameplay rule. Asserted against the literal on purpose: retuning the death
	# beat must update this spec deliberately rather than slip through unnoticed.
	_ok("DyingTimer holds the death beat (2.5s)", is_equal_approx(dying.wait_time, 2.5))
	dying.stop()
	dying.timeout.emit()
	_ok("DyingTimer.timeout emits warrior_died", died[0] == 1)

	w.take_damage(1)
	_ok("DYING blocks further damage",    w.coherence == 0 and died[0] == 1)

	w.queue_free()


# ── Chain 5: The Song ────────────────────────────────────────────────────────

func _test_song() -> void:
	print("\n[Chain 5: The Song — Dissonant]")

	# Dissonant Song: a non-deep-harmonic warrior (tier 3) pays Coherence and looses a
	# DISSONANT pulse on every enemy. One HARMONIC enemy (DISSONANT hit = CORRECT, takes
	# damage) + one DISSONANT enemy (= WRONG, amplified).
	var w := _warrior(10)
	w.tribe_coherence_tier = 3        # raw/dissonant summon → Dissonant Song
	w.coherence = 6                   # drops to 3 after the cost of 3
	var e_harm := _enemy(EnemyScript.Freq.HARMONIC)
	var e_dis  := _enemy(EnemyScript.Freq.DISSONANT)
	# Remove any stale enemies from previous tests still alive in the group
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != e_harm and e != e_dis:
			e.remove_from_group("enemies")

	w.chain = 5
	w._do_song()

	_ok("song resets chain to 0",             w.chain == 0)
	_ok("dissonant song costs 3 coherence",   w.coherence == 3)
	_ok("HARMONIC enemy takes damage (hp=1)", e_harm.hp == 1)
	_ok("DISSONANT enemy is amplified",       e_dis._amplified)

	e_harm.queue_free()
	e_dis.queue_free()
	w.queue_free()

	# Fatal Song: a dissonant warrior with 2 Coherence cannot afford the cost. Death
	# routes through State.DYING (the dying animation plays before main.gd swaps
	# scenes), so warrior_died fires async via $DyingTimer — assert the state change
	# synchronously rather than awaiting a timer the headless run quits before.
	var w2 := _warrior(10)
	w2.tribe_coherence_tier = 3
	w2.coherence = 2
	w2.chain = 5
	w2._do_song()
	_ok("coherence floored at 0 after fatal song", w2.coherence == 0)
	_ok("fatal song enters DYING state",           w2._state == WarriorScript.State.DYING)
	w2.queue_free()

	print("\n[Chain 5: The Song — Harmonic]")

	# Harmonic Song: a deep-harmonic warrior (tier 0) resolves the song instead — every
	# enemy in range is pacified and Coherence is fully restored, at no cost.
	var w3 := _warrior(10)
	w3.tribe_coherence_tier = 0       # whole/harmonic summon → Harmonic Song
	w3.coherence = 4
	var e_h := _enemy(EnemyScript.Freq.HARMONIC)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != e_h:
			e.remove_from_group("enemies")

	# Put the enemy in active chase so pacify has something to pull it out of.
	e_h._state = EnemyScript.State.CHASE
	e_h._player = w3

	w3.chain = 5
	w3._do_song()

	_ok("harmonic song resets chain to 0",         w3.chain == 0)
	_ok("harmonic song restores coherence to max", w3.coherence == WarriorScript.MAX_COHERENCE)
	_ok("harmonic song pacifies enemy",            e_h._pacified)
	_ok("harmonic song pulls enemy out of chase", e_h._state == EnemyScript.State.IDLE)

	e_h.queue_free()
	w3.queue_free()


# ── The clear-count: hostiles only ────────────────────────────────────────

# The clear banner used to fire off a counter that only tracked _spawn_enemies(), so
# Ring 1 announced itself clear with 3 Thresholds and a 7-strong herd still walking
# around. clear_tracker.gd now asks each spawn is_hostile(). These specs pin BOTH sides
# of the decision: a Threshold blocks the clear, a Pale Walker never does — alive or
# dead. Registration is explicit (never a group scan): the suite runs synchronously in
# _ready(), so every queue_free() above is still pending and the "enemies" group is
# full of stale bodies from earlier specs.
func _test_clear_count() -> void:
	print("\n[Clear count: hostiles only]")
	var tracker: RefCounted = load("res://scripts/clear_tracker.gd").new()
	var fired: Array = [0]
	tracker.cleared.connect(func() -> void: fired[0] += 1)

	# Ring 1's real mix: a pocket husk, a hostile Threshold, a peaceful grazer.
	var husk := _enemy(EnemyScript.Freq.HARMONIC)
	var threshold: CharacterBody2D = load("res://scripts/creature_threshold.gd").new()
	add_child(threshold)
	var walker: CharacterBody2D = load("res://scripts/creature_pale_walker.gd").new()
	add_child(walker)

	_ok("husk is hostile", husk.is_hostile())
	_ok("Threshold is hostile (it lunges for 2 Coherence)", threshold.is_hostile())
	_ok("Pale Walker is not hostile (no aggressive state)", not walker.is_hostile())

	_ok("husk joins the count", bool(tracker.register(husk)))
	_ok("Threshold joins the count", bool(tracker.register(threshold)))
	_ok("Pale Walker is turned away", not bool(tracker.register(walker)))
	_ok("count is hostiles only", tracker.hostiles_alive() == 2)

	# Killing a grazer must move nothing: the ring is not more cleared for it.
	walker.receive_hit(EnemyScript.Freq.DISSONANT)
	walker.receive_hit(EnemyScript.Freq.DISSONANT)
	_ok("grazer dies from two correct hits", walker._dead)
	_ok("killing a grazer leaves the count alone", tracker.hostiles_alive() == 2)
	_ok("killing a grazer does not clear the ring", fired[0] == 0)

	# One hostile down is not a clear.
	husk.receive_hit(EnemyScript.Freq.DISSONANT)
	husk.receive_hit(EnemyScript.Freq.DISSONANT)
	_ok("a dead hostile drops the count", tracker.hostiles_alive() == 1)
	_ok("banner stays silent while a Threshold lives", fired[0] == 0)

	# The last hostile clears it — exactly once.
	threshold.receive_hit(EnemyScript.Freq.HARMONIC)
	threshold.receive_hit(EnemyScript.Freq.HARMONIC)
	_ok("the last hostile empties the count", tracker.hostiles_alive() == 0)
	_ok("cleared fires exactly once", fired[0] == 1)

	# A ring holding nothing but peaceful life never announces itself clear: the signal
	# fires on a decrement that reaches zero, not on a count that started there.
	var quiet: RefCounted = load("res://scripts/clear_tracker.gd").new()
	var quiet_fired: Array = [0]
	quiet.cleared.connect(func() -> void: quiet_fired[0] += 1)
	var lone: CharacterBody2D = load("res://scripts/creature_pale_walker.gd").new()
	add_child(lone)
	quiet.register(lone)
	_ok("a herd-only ring counts zero hostiles", quiet.hostiles_alive() == 0)
	lone.receive_hit(EnemyScript.Freq.DISSONANT)
	lone.receive_hit(EnemyScript.Freq.DISSONANT)
	_ok("a herd-only ring never fires the banner", quiet_fired[0] == 0)


# ── Locomotion: the fast-paced pass ──────────────────────────────────────────────

# Roadmap 43. Steps the warrior's _physics_process by hand at 60 Hz with an injected
# input_provider and reads velocity only (the suite runs synchronously in _ready, before
# any physics frame, so move_and_slide does not travel — distances integrate velocity).
# The thresholds are the feel targets the pass was tuned to: a retune that loosens them
# should update these deliberately. Before the pass: 0.22s to speed, 0.20s to stop,
# 0.28s to reverse, and a ~26px ice-slide out of every dash.
const _DT := 1.0 / 60.0

func _test_locomotion() -> void:
	print("\n[Locomotion]")
	var speed: float = WarriorScript.SPEED

	# --- the pace knob keeps every designed speed relation -----------------------------
	_ok("warrior pace derives from SimSpace.PACE", is_equal_approx(speed, 100.0 * SimSpace.PACE))
	_ok("herd scatter still outruns the warrior", CreaturePaleWalker.SCATTER_SPEED > speed)
	_ok("Threshold lunge still outpaces the warrior", CreatureThreshold.COMMIT_SPEED > speed)
	_ok("fleer still sits just below the warrior", EnemyFleerScript.FLEE_SPEED < speed \
			and EnemyFleerScript.FLEE_SPEED > 0.8 * speed)
	_ok("husk chase stays well below the warrior", EnemyScript.SPEED < 0.5 * speed)
	_ok("the dash is a burst (>= 3.5x the pace)", WarriorScript.DASH_SPEED >= 3.5 * speed)

	var dir: Array = [Vector2.ZERO]
	var w := _live_warrior(dir)

	# --- steering ------------------------------------------------------------------------
	dir[0] = Vector2.RIGHT
	var f := _frames_until(w, func() -> bool: return w.velocity.x >= 0.9 * speed)
	_ok("reaches 90%% speed within 0.1s (%d frames)" % f, f > 0 and f * _DT <= 0.1)
	_frames_until(w, func() -> bool: return false, 30)
	_ok("holds exactly the base pace", is_equal_approx(w.velocity.x, speed))

	dir[0] = Vector2.ZERO
	var slide: Array = [0.0]
	f = _frames_until(w, func() -> bool:
		slide[0] += w.velocity.x * _DT
		return w.velocity.length() < 1.0)
	_ok("stops within 0.1s (%d frames)" % f, f > 0 and f * _DT <= 0.1)
	_ok("stop slide under 8px (%.1f)" % slide[0], slide[0] < 8.0)

	dir[0] = Vector2.RIGHT
	_frames_until(w, func() -> bool: return false, 30)
	dir[0] = Vector2.LEFT
	f = _frames_until(w, func() -> bool: return w.velocity.x <= -0.9 * speed)
	_ok("full reversal within 0.15s (%d frames)" % f, f > 0 and f * _DT <= 0.15)
	w.queue_free()

	# --- dash ------------------------------------------------------------------------------
	w = _live_warrior(dir)
	dir[0] = Vector2.RIGHT
	_frames_until(w, func() -> bool: return false, 30)
	w._start_dash()
	var dash_dist: Array = [0.0]
	_frames_until(w, func() -> bool:
		dash_dist[0] += w.velocity.x * _DT
		return w._state != WarriorScript.State.DASH)
	_ok("dash covers 120-160px (%.0f)" % dash_dist[0], dash_dist[0] > 120.0 and dash_dist[0] < 160.0)
	_ok("dash exits at move speed, not DASH_SPEED", w.velocity.length() <= speed + 0.01)
	dir[0] = Vector2.ZERO
	slide[0] = 0.0
	_frames_until(w, func() -> bool:
		slide[0] += w.velocity.x * _DT
		return w.velocity.length() < 1.0)
	_ok("no ice-slide after a dash (%.1fpx)" % slide[0], slide[0] < 8.0)
	w.queue_free()

	# The exit clamp must not eat the dash-attack lunge: an attack cancelling the dash
	# keeps the burst's momentum into the swing.
	w = _live_warrior(dir)
	dir[0] = Vector2.RIGHT
	w._start_dash()
	w._attack_buffer = WarriorScript.INPUT_BUFFER
	_frames_until(w, func() -> bool: return w._state != WarriorScript.State.DASH)
	_ok("a buffered attack cancels the dash", w._state == WarriorScript.State.ATTACK_STARTUP)
	_ok("dash-attack keeps its lunge momentum", w.velocity.length() > speed)
	w.queue_free()


# ── Husks keep pace ─────────────────────────────────────────────────────────────

# Roadmap 44. Husk/fleer velocity used to snap between 0 and full speed; it now ramps
# (enemy.gd _steer). Same hand-stepped 60 Hz method as the locomotion specs. The detect
# radius is script-owned and must never reach a pocket from the summon point.
func _test_enemy_pace() -> void:
	print("\n[Enemy pace]")
	var main_consts: Dictionary = load("res://scripts/main.gd").get_script_constant_map()
	var nearest_spawn: float = main_consts["HOME_SAFE_RADIUS"] - main_consts["POCKET_RADIUS"]
	_ok("a fresh summon can't wake a pocket (detect %.0f < %.0f)" % [EnemyScript.DETECT_RADIUS, nearest_spawn],
			EnemyScript.DETECT_RADIUS < nearest_spawn)

	for scene in [EnemyScene, EnemyFleerScene, EnemyPhaserScene]:
		var inst := (scene as PackedScene).instantiate() as CharacterBody2D
		add_child(inst)
		var r: float = (inst.get_node("DetectRange/DetectShape").shape as CircleShape2D).radius
		_ok("%s detects at DETECT_RADIUS" % inst.name, is_equal_approx(r, EnemyScript.DETECT_RADIUS))
		inst.queue_free()

	# A stand-in player 200 px to the right; the chase state is forced, not detected. Both
	# sit far from the origin, where every earlier spec's bodies still overlap (queue_free
	# is pending until the synchronous suite ends) and would clip move_and_slide.
	var clear := Vector2(-5000.0, -5000.0)
	var target := CharacterBody2D.new()
	add_child(target)
	target.position = clear + Vector2(200.0, 0.0)

	var husk := _enemy(EnemyScript.Freq.HARMONIC)
	husk.position = clear
	husk._player = target
	husk._state = EnemyScript.State.CHASE
	husk._physics_process(_DT)
	_ok("husk ramps into the chase (no snap to full speed)",
			husk.velocity.x > 0.0 and husk.velocity.x < 0.5 * EnemyScript.SPEED)
	var f := _steps_until(husk, func() -> bool: return husk.velocity.x >= EnemyScript.SPEED - 0.01)
	_ok("husk reaches chase speed within ~0.15s (%d frames, v=%.1f)" % [f, husk.velocity.x], f > 0 and f <= 10)
	husk._state = EnemyScript.State.IDLE
	husk._physics_process(_DT)
	_ok("husk settles rather than stopping dead", husk.velocity.x > 0.0)
	f = _steps_until(husk, func() -> bool: return husk.velocity == Vector2.ZERO)
	_ok("husk is at rest within ~0.12s (%d frames)" % f, f > 0 and f <= 8)
	husk.queue_free()

	var fleer := EnemyFleerScene.instantiate() as CharacterBody2D
	add_child(fleer)
	fleer.position = clear + Vector2(0.0, 400.0)
	target.position = fleer.position + Vector2(200.0, 0.0)
	fleer._player = target
	fleer._state = EnemyScript.State.CHASE
	fleer._physics_process(_DT)
	_ok("fleer ramps away from the player",
			fleer.velocity.x < 0.0 and fleer.velocity.x > -0.5 * EnemyFleerScript.FLEE_SPEED)
	f = _steps_until(fleer, func() -> bool: return fleer.velocity.x <= -EnemyFleerScript.FLEE_SPEED + 0.01)
	_ok("fleer reaches flee speed within ~0.15s (%d frames)" % f, f > 0 and f <= 10)
	fleer.queue_free()
	target.queue_free()


# Step any body's _physics_process at 60 Hz until `cond` holds; frame count or -1.
func _steps_until(body: Node, cond: Callable, cap: int = 60) -> int:
	for i in cap:
		body._physics_process(_DT)
		if cond.call():
			return i + 1
	return -1


# A warrior out of the summon grace, steered by `dir[0]` and aiming right.
func _live_warrior(dir: Array) -> CharacterBody2D:
	var w := _warrior(10)
	w.input_provider = func() -> Vector2: return dir[0]
	w.attack_dir_provider = func() -> Vector2: return Vector2.RIGHT
	var summoning: Timer = w.get_node("SummoningTimer")
	summoning.stop()
	summoning.timeout.emit()
	return w


# Step `w` one 60 Hz physics tick at a time until `cond` holds; returns the frame count,
# or -1 if `cap` frames pass first.
func _frames_until(w: CharacterBody2D, cond: Callable, cap: int = 120) -> int:
	for i in cap:
		w._physics_process(_DT)
		if cond.call():
			return i + 1
	return -1


# Strike readability (roadmap 45): the swing keyframes must send the blade THROUGH the aim
# and land it in front. The old tables parked the forehand's landing ~153 deg off the aim
# (behind the body) and held it through recovery, so a cut read as aimed somewhere else.
# Pure data: the blade's ground heading is ~ arm_yaw + torso_twist off body-forward.
func _test_strike_poses() -> void:
	print("\n[Strike poses]")
	var ends: Array = WarriorMesh.STRIKE_ENDS
	var winds: Array = WarriorMesh.SWING_WINDUPS
	_ok("one windup + one landing per combo step",
			ends.size() == WarriorScript.COMBO_LEN and winds.size() == WarriorScript.COMBO_LEN)
	var heading := func(p: Array) -> float: return p[1] + p[3]
	var front := true
	for p in ends:
		front = front and absf(heading.call(p)) < 1.4
	_ok("every swing lands in front of the body (|heading| < 80 deg)", front)
	for step in [0, 1]:
		var w: float = heading.call(winds[step])
		var e: float = heading.call(ends[step])
		_ok("cut %d sweeps across the aim (windup and landing on opposite sides)" % step,
				signf(w) != signf(e) and absf(w) > 1.0 and absf(e) > 1.0)
	for step in [2, 3]:
		_ok("swing %d drives down the aim line (|heading| < 20 deg)" % step,
				absf(heading.call(ends[step])) < 0.35)
	var guard := WarriorMesh.IDLE_ARM_YAW + WarriorMesh.IDLE_TORSO_TWIST + WarriorSync.STANCE_YAW
	_ok("the idle guard holds the blade along the facing (|heading| < 30 deg)", absf(guard) < 0.5)

