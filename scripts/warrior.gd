extends CharacterBody2D

const SPEED := 100.0
const MAX_COHERENCE := 10
const CHAIN_TIMEOUT := 3.0
const AttackArcScene := preload("res://scenes/attack_arc.tscn")

signal coherence_changed(value: int)
signal chain_changed(value: int)

var coherence := MAX_COHERENCE
var chain := 0

var _attack_ready := true
var _chain_timer := 0.0

func _ready() -> void:
	$AttackCooldown.timeout.connect(_clear_attack_cooldown)

func _physics_process(delta: float) -> void:
	_handle_movement()
	_tick_chain_timer(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("attack") and _attack_ready:
		_do_attack()

func _handle_movement() -> void:
	var direction := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	).normalized()
	velocity = direction * SPEED
	move_and_slide()

func _do_attack() -> void:
	_attack_ready = false
	$AttackCooldown.start()
	var arc := AttackArcScene.instantiate()
	get_parent().add_child(arc)
	arc.global_position = global_position
	var aim_dir := (get_global_mouse_position() - global_position).normalized()
	if aim_dir == Vector2.ZERO:
		aim_dir = Vector2.RIGHT
	arc.set_direction(aim_dir)
	arc.hit_target.connect(_on_hit)

func _on_hit(_area: Area2D) -> void:
	chain = min(chain + 1, 5)
	chain_changed.emit(chain)
	_chain_timer = CHAIN_TIMEOUT

func _tick_chain_timer(delta: float) -> void:
	if chain > 0:
		_chain_timer -= delta
		if _chain_timer <= 0.0:
			chain = 0
			chain_changed.emit(chain)

func take_damage(amount: int) -> void:
	coherence = max(coherence - amount, 0)
	coherence_changed.emit(coherence)
	chain = 0
	chain_changed.emit(chain)

func _clear_attack_cooldown() -> void:
	_attack_ready = true
