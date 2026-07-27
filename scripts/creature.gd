class_name Creature
extends CharacterBody2D

## F1 — thin shared base for the GDD ring creatures (Pale Herd, Threshold, …).
##
## It joins the existing, playthrough-verified combat loop by honouring the same
## duck-typed contract the warrior uses on everything in group "enemies":
## `receive_hit(freq) -> HitResult`, `reveal(dur)`, `pacify(dur)`, `force_amplify()`,
## the `enemy_died` signal, and the static `Freq` / `HitResult` enums. It does NOT
## extend `enemy.gd` — that base + its fleer/phaser subclasses stay untouched (they
## are placeholders slated for removal); this is the path forward.
##
## The base only provides the scaffold: an emotional state machine, player perception,
## status timers, and the public API. Each creature is a subclass that codes its own
## states / tells / transitions (the GDD creatures are too mechanically diverse for one
## declarative table). Everything is built in code — nodes, collision, placeholder
## visual — so no `.tscn` is needed, matching the warrior's procedural-mesh direction.
## A cel-shaded 3D mesh + `*_sync.gd` is a separate follow-up; for now the body is a
## flat placeholder `Polygon2D`.

signal enemy_died

# Order MUST match enemy.gd: the warrior passes `EnemyScript.Freq.DISSONANT` (int 0) into
# receive_hit and tests results against `EnemyScript.HitResult.CORRECT` (int 0).
enum Freq { DISSONANT, HARMONIC }
enum HitResult { CORRECT, WRONG }

# Collision mirrors enemy.tscn so the warrior's attack arc and the creature's player
# perception line up with the verified loop.
const LAYER_HURT := 2     # HurtBox sits here; the attack arc's HitArea masks this layer
const MASK_PLAYER := 1    # DetectRange / AttackRange see the player body (layer 1)
const BODY_RADIUS := 6.0
const HURT_RADIUS := 8.0

# The unread appearance. A creature hides its emotional-state tell until the
# warrior's Resonance pulse reveals it (`reveal()` → `_revealed`), matching
# enemy.gd's hidden-grey → coloured-on-reveal gate. MUST stay equal to
# world_sync.gd's NEUTRAL_COLOR: WorldSync keys the frequency pip on exactly this
# colour, so any other unread colour would leak the pip with no pulse.
const HIDDEN_COLOR := Color(0.533, 0.596, 0.659, 1)

# Designer knobs (subclasses override in their own _ready/consts as needed).
var detect_radius: float = 64.0
var attack_radius: float = 12.0

var frequency: int = Freq.DISSONANT
var hp: int = 2

var _state: StringName = &""
var _player: CharacterBody2D = null
var _dead: bool = false

# Status primitives the warrior's read / song drive (held flags, ticked each frame).
var _revealed: bool = false
var _reveal_timer: float = 0.0
var _pacified: bool = false
var _pacify_timer: float = 0.0
var _force_amplified: bool = false

var _visual: Polygon2D

func _ready() -> void:
	add_to_group("enemies")
	motion_mode = MOTION_MODE_FLOATING
	_build_nodes()
	_change_state(_initial_state())

func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	if _dead:
		return
	velocity = Vector2.ZERO  # subclasses opt into movement by setting velocity
	if not _pacified:
		_update_state(delta)
	move_and_slide()

# ── Public API (the loop's contract) ─────────────────────────────────────────

func receive_hit(attacker_freq: int) -> int:
	if _dead:
		return HitResult.WRONG
	_on_attacked(attacker_freq)  # creatures may react to being struck (e.g. flee)
	if attacker_freq != frequency:
		hp -= 1
		_flash(Color.WHITE)
		if hp <= 0:
			_die()
		return HitResult.CORRECT
	return HitResult.WRONG

## The warrior's Resonance pulse hits every nearby creature with this. Beyond
## surfacing the tell, projecting a frequency can CHANGE a creature's decision —
## subclasses hook `_on_resonance_projected()` (the GDD's intervention window).
func reveal(duration: float) -> void:
	_revealed = true
	_reveal_timer = duration
	_refresh_visual()
	_on_resonance_projected()

## Chain-5 harmonic Song: calmed, barred from acting for `duration`.
func pacify(duration: float) -> void:
	if _dead:
		return
	_pacified = true
	_pacify_timer = duration
	_player = null
	velocity = Vector2.ZERO

func force_amplify() -> void:
	_force_amplified = true

func get_state() -> StringName:
	return _state

func get_tell() -> Color:
	return _tell_color()

## Can this creature damage the warrior? Part of the "enemies" contract: the run's
## clear-count (see clear_tracker.gd) counts only hostiles, so peaceful ring life is
## never something the player has to kill. Defaults to true — a new creature that
## forgets to answer is counted rather than silently excused from the count.
func is_hostile() -> bool:
	return true

# ── State machine scaffold ───────────────────────────────────────────────────

func _change_state(next: StringName) -> void:
	if next == _state:
		return
	_state = next
	_enter_state(next)
	_refresh_visual()

# Virtuals — subclasses override.
func _initial_state() -> StringName:
	return &"idle"

func _enter_state(_next: StringName) -> void:
	pass

func _update_state(_delta: float) -> void:
	pass

func _tell_color() -> Color:
	return Color(0.533, 0.596, 0.659)  # neutral grey

# Reaction hooks — subclasses override.
func _on_player_event(_event: StringName) -> void:
	pass

func _on_resonance_projected() -> void:
	pass

func _on_attacked(_attacker_freq: int) -> void:
	pass

# ── Internals ────────────────────────────────────────────────────────────────

func _tick_timers(delta: float) -> void:
	if _revealed:
		_reveal_timer -= delta
		if _reveal_timer <= 0.0:
			_revealed = false
			_refresh_visual()  # tell fades back to the hidden grey when the read lapses
	if _pacified:
		_pacify_timer -= delta
		if _pacify_timer <= 0.0:
			_pacified = false

func _refresh_visual() -> void:
	# The tell only surfaces while revealed by a Resonance pulse; otherwise the
	# body reads as the ambiguous hidden grey (and WorldSync draws no frequency pip).
	if is_instance_valid(_visual) and not _dead:
		_visual.color = _tell_color() if _revealed else HIDDEN_COLOR

func _flash(flash_color: Color) -> void:
	if not is_instance_valid(_visual):
		return
	_visual.color = flash_color
	await get_tree().create_timer(0.08).timeout
	if is_instance_valid(self) and not _dead:
		_refresh_visual()

func _die() -> void:
	if _dead:
		return
	_dead = true
	velocity = Vector2.ZERO
	enemy_died.emit()
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ZERO, 0.18)
	tween.tween_callback(queue_free)

func _build_nodes() -> void:
	# Body collision.
	var body_shape := CollisionShape2D.new()
	var bsc := CircleShape2D.new()
	bsc.radius = BODY_RADIUS
	body_shape.shape = bsc
	add_child(body_shape)

	# Placeholder visual — a small octagon, recoloured per state's tell.
	_visual = Polygon2D.new()
	_visual.name = "Visual"  # WorldSync looks up a child named "Visual" to mirror the 3D billboard
	_visual.polygon = PackedVector2Array([
		Vector2(8, 0), Vector2(6, 6), Vector2(0, 8), Vector2(-6, 6),
		Vector2(-8, 0), Vector2(-6, -6), Vector2(0, -8), Vector2(6, -6),
	])
	_visual.color = HIDDEN_COLOR  # unread until a Resonance pulse reveals the tell
	add_child(_visual)

	# HurtBox — what the warrior's attack arc overlaps (parent = self has receive_hit).
	var hurt := Area2D.new()
	hurt.collision_layer = LAYER_HURT
	hurt.collision_mask = 0
	var hurt_shape := CollisionShape2D.new()
	var hsc := CircleShape2D.new()
	hsc.radius = HURT_RADIUS
	hurt_shape.shape = hsc
	hurt.add_child(hurt_shape)
	add_child(hurt)

	# DetectRange / AttackRange — perceive the player body (layer 1).
	_add_sense("detect", detect_radius, &"detected", &"lost")
	_add_sense("attack", attack_radius, &"in_attack", &"out_attack")

func _add_sense(area_name: String, radius: float, on_enter: StringName, on_exit: StringName) -> void:
	var area := Area2D.new()
	area.name = area_name
	area.collision_layer = 0
	area.collision_mask = MASK_PLAYER
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	area.add_child(shape)
	add_child(area)
	area.body_entered.connect(func(body: Node2D) -> void:
		if _pacified or _dead:
			return
		if body.has_method("take_damage"):
			_player = body
			_on_player_event(on_enter))
	area.body_exited.connect(func(body: Node2D) -> void:
		if body == _player:
			_on_player_event(on_exit))
