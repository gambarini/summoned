extends CharacterBody2D

signal enemy_died

enum Freq { DISSONANT, HARMONIC }
enum HitResult { CORRECT, WRONG }
enum State { IDLE, CHASE, ATTACK, DEAD }

const SPEED := 40.0
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

func _physics_process(delta: float) -> void:
	_tick_status_timers(delta)
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

func _on_detect_entered(body: Node2D) -> void:
	if body.has_method("take_damage"):
		_player = body
		if _state == State.IDLE:
			_state = State.CHASE

func _on_detect_exited(body: Node2D) -> void:
	if body == _player and _state == State.CHASE:
		_state = State.IDLE
		_player = null

func _on_attack_entered(body: Node2D) -> void:
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
	if _player and _state == State.ATTACK:
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
		return HitResult.CORRECT
	else:
		_amplify()
		return HitResult.WRONG

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

func _die() -> void:
	_state = State.DEAD
	_attack_timer.stop()
	set_physics_process(false)
	enemy_died.emit()
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ZERO, 0.18)
	tween.tween_callback(queue_free)
