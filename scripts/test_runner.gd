extends Node

const EnemyScene := preload("res://scenes/enemy.tscn")
const WarriorScene := preload("res://scenes/warrior.tscn")
const EnemyScript = preload("res://scripts/enemy.gd")

var _pass := 0
var _fail := 0

func _ready() -> void:
	print("\n=== SUMMONED TEST SUITE ===")
	_test_game_state()
	_test_enemy_hits()
	_test_enemy_states()
	_test_warrior_coherence()
	_test_warrior_damage()
	_test_song()
	print("\n%d passed  %d failed" % [_pass, _fail])


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


# ── Enemy: receive_hit return values + hp ────────────────────────────────────

func _test_enemy_hits() -> void:
	print("\n[Enemy.receive_hit]")

	var e := _enemy(EnemyScript.Freq.HARMONIC)
	var r := e.receive_hit(EnemyScript.Freq.DISSONANT)
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
	print("\n[Chain 5: The Song]")

	# Setup: warrior + one HARMONIC enemy (DISSONANT hit = CORRECT) + one DISSONANT enemy (= WRONG)
	var w := _warrior(10)
	w.coherence = 6  # will drop to 3 after cost of 3
	var e_harm := _enemy(EnemyScript.Freq.HARMONIC)
	var e_dis  := _enemy(EnemyScript.Freq.DISSONANT)
	# Remove any stale enemies from previous tests that are still alive in the group
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != e_harm and e != e_dis:
			e.remove_from_group("enemies")

	w.chain = 5
	w._do_song()

	_ok("song resets chain to 0",          w.chain == 0)
	_ok("song costs 3 coherence",          w.coherence == 3)
	_ok("HARMONIC enemy takes damage (hp=1)", e_harm.hp == 1)
	_ok("DISSONANT enemy is amplified",    e_dis._amplified)

	e_harm.queue_free()
	e_dis.queue_free()
	w.queue_free()

	# Fatal song: warrior with 2 coherence dies
	var w2 := _warrior(10)
	w2.coherence = 2
	var died := false
	w2.warrior_died.connect(func(): died = true)
	w2.chain = 5
	w2._do_song()
	_ok("song at coherence 2 emits warrior_died", died)
	_ok("coherence floored at 0 after fatal song", w2.coherence == 0)
	w2.queue_free()
