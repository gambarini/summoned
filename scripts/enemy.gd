extends CharacterBody2D
class_name Enemy

signal enemy_died

enum Freq { DISSONANT, HARMONIC }
enum HitResult { CORRECT, WRONG }
enum State { IDLE, CHASE, ATTACK, DEAD }

const SPEED := 40.0
# Hit reaction: a CORRECT hit staggers the enemy (no chase/attack) and shoves it away
# from the player, so the warrior's combo visibly interrupts instead of trading hits.
const HITSTUN_DURATION := 0.22
const KNOCKBACK_SPEED := 140.0
const KNOCKBACK_DECAY := 8.0
const NEUTRAL_COLOR := Color(0.533, 0.596, 0.659, 1)
const COLORS := {
	0: Color(0.769, 0.329, 0.478, 1),
	1: Color(0.753, 0.627, 0.941, 1),
}

var frequency: Freq
var hp := 2
var _state := State.IDLE
var _player: CharacterBody2D = null
var _revealed := false
var _reveal_timer := 0.0
var _amplified := false
var _amp_timer := 0.0
var _force_amplified := false
var _pacified := false
var _pacify_timer := 0.0
var _hitstun_timer := 0.0
var _knockback := Vector2.ZERO

@onready var _visual: Polygon2D = $Visual
@onready var _attack_timer: Timer = $AttackTimer

func _ready() -> void:
	add_to_group("enemies")
	frequency = Freq.DISSONANT if randf() < 0.5 else Freq.HARMONIC
	_visual.color = NEUTRAL_COLOR
	$DetectRange.body_entered.connect(_on_detect_entered)
	$DetectRange.body_exited.connect(_on_detect_exited)
	$AttackRange.body_entered.connect(_on_attack_entered)
	$AttackRange.body_exited.connect(_on_attack_exited)
	_attack_timer.timeout.connect(_do_attack)

func _tick_status_timers(delta: float) -> void:
	if _amplified and not _force_amplified:
		_amp_timer -= delta
		if _amp_timer <= 0.0:
			_amplified = false
			if _state != State.DEAD:
				_visual.color = _current_color()
				_visual.scale = Vector2.ONE
	if _revealed:
		_reveal_timer -= delta
		if _reveal_timer <= 0.0:
			_revealed = false
			if _state != State.DEAD:
				_visual.color = _current_color()
	if _pacified:
		_pacify_timer -= delta
		if _pacify_timer <= 0.0:
			_pacified = false

# While staggered the hit reaction owns the frame: the enemy rides the decaying
# knockback shove and cannot chase or attack. Returns true while active. Subclasses
# that replace _physics_process (fleer) must early-out on this too.
func _tick_hit_reaction(delta: float) -> bool:
	if _hitstun_timer <= 0.0:
		return false
	_hitstun_timer -= delta
	velocity = _knockback
	_knockback = _knockback.lerp(Vector2.ZERO, KNOCKBACK_DECAY * delta)
	move_and_slide()
	return true

func _physics_process(delta: float) -> void:
	_tick_status_timers(delta)
	if _tick_hit_reaction(delta):
		return
	if _state == State.CHASE and _player:
		var spd := SPEED * 2.0 if _amplified else SPEED
		var dir := (_player.global_position - global_position).normalized()
		velocity = dir * spd
		move_and_slide()
	else:
		velocity = Vector2.ZERO

func _current_color() -> Color:
	if _amplified:
		return Color(0.831, 0.502, 0.227, 1)
	elif _revealed:
		return COLORS[frequency]
	return NEUTRAL_COLOR

func reveal(duration: float) -> void:
	_revealed = true
	_reveal_timer = duration
	if not _amplified and _state != State.DEAD:
		_visual.color = COLORS[frequency]

## Presentation-layer read (same contract as creature.gd's get_state): the
## current state as a StringName, so the 3D mesh rig never touches _state.
func get_state() -> StringName:
	return [&"idle", &"chase", &"attack", &"dead"][_state]

func _on_detect_entered(body: Node2D) -> void:
	if _pacified:
		return
	if body.has_method("take_damage"):
		_player = body
		if _state == State.IDLE:
			_state = State.CHASE

func _on_detect_exited(body: Node2D) -> void:
	if body == _player and _state == State.CHASE:
		_state = State.IDLE
		_player = null

func _on_attack_entered(body: Node2D) -> void:
	if _pacified:
		return
	if body.has_method("take_damage") and _state != State.DEAD:
		_player = body
		_state = State.ATTACK
		if _attack_timer.is_stopped():
			_attack_timer.start()

func _on_attack_exited(body: Node2D) -> void:
	if body == _player and _state == State.ATTACK:
		_attack_timer.stop()
		_state = State.CHASE

func _do_attack() -> void:
	if _player and _state == State.ATTACK and _hitstun_timer <= 0.0:
		_player.take_damage(1)
		_flash(Color(1, 0.3, 0.3, 1))

func receive_hit(attacker_freq: Freq) -> HitResult:
	if _state == State.DEAD:
		return HitResult.WRONG
	if attacker_freq != frequency:
		_flash(Color.WHITE)
		hp -= 1
		if hp <= 0:
			_die()
		else:
			_stagger()
		return HitResult.CORRECT
	else:
		_amplify()
		return HitResult.WRONG

# Interrupt on a landed hit: brief stun, a shove away from the player (stun-only when
# no player reference is held — e.g. hit from outside detection), and a squash-pop.
func _stagger() -> void:
	_hitstun_timer = HITSTUN_DURATION
	if is_instance_valid(_player):
		_knockback = (global_position - _player.global_position).normalized() * KNOCKBACK_SPEED
	else:
		_knockback = Vector2.ZERO
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector2(1.25, 0.75), 0.05)
	tween.tween_property(_visual, "scale", Vector2.ONE, 0.12)

func _amplify() -> void:
	_amplified = true
	_amp_timer = 2.0
	_visual.color = _current_color()
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector2(1.3, 1.3), 0.08)
	tween.tween_property(_visual, "scale", Vector2(1.0, 1.0), 0.1)

func _flash(flash_color: Color) -> void:
	_visual.color = flash_color
	await get_tree().create_timer(0.08).timeout
	if is_instance_valid(self) and _state != State.DEAD:
		_visual.color = _current_color()

func force_amplify() -> void:
	_force_amplified = true
	_amplified = true
	_visual.color = _current_color()

## Harmonic resolution from the warrior's Chain-5 Song (GDD §784): the enemy is
## calmed — pulled out of chase/attack and barred from re-acquiring the player for
## `duration`. A held flag (`_pacified`, ticked down in _tick_status_timers) the
## Song's harmonic branch sets on every enemy in range; the detect/attack handlers
## ignore the player while it holds. Never applied to the dead.
func pacify(duration: float) -> void:
	if _state == State.DEAD:
		return
	_pacified = true
	_pacify_timer = duration
	_state = State.IDLE
	_player = null
	_attack_timer.stop()
	_visual.color = _current_color()

func _die() -> void:
	_state = State.DEAD
	_attack_timer.stop()
	set_physics_process(false)
	enemy_died.emit()
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ZERO, 0.18)
	tween.tween_callback(queue_free)
