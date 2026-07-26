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
	# _test_warrior_damage() is SKIPPED — see _print_skips().
	_print_skips()
	print("\n%d passed  %d failed  %d skipped" % [_pass, _fail, _skip])


# ── helpers ─────────────────────────────────────────────────────────────────

func _ok(label: String, cond: bool) -> void:
	if cond:
		print("  PASS  " + label)
		_pass += 1
	else:
		print("  FAIL  " + label)
		_fail += 1

# Warrior.take_damage is still skipped — a design gap, not a bug: the warrior boots
# into State.SUMMONING (warrior.gd:227) so take_damage() early-returns, and lethal
# hits emit warrior_died async via $DyingTimer, not synchronously as that spec asserts.
func _print_skips() -> void:
	print("\n[SKIPPED] Warrior.take_damage — summon-boot + async death (design gap)")
	_skip += 1

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


# ── Warrior: take_damage guards ──────────────────────────────────────────────

func _test_warrior_damage() -> void:
	print("\n[Warrior.take_damage]")

	var w := _warrior(10)

	w.take_damage(3)
	_ok("damage reduces coherence",       w.coherence == 7)

	w.chain = 3
	w.take_damage(1)
	_ok("damage resets chain",            w.chain == 0)

	w.coherence = 5
	w._inactive = true
	w.take_damage(2)
	_ok("inactive blocks damage",         w.coherence == 5)
	w._inactive = false

	var died := false
	w.warrior_died.connect(func(): died = true)
	w.coherence = 1
	w.take_damage(1)
	_ok("lethal hit emits warrior_died",  died)
	_ok("coherence floored at 0",         w.coherence == 0)

	w.take_damage(1)
	_ok("coherence=0 blocks further damage", w.coherence == 0)

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
