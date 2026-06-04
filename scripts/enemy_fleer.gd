extends "res://scripts/enemy.gd"

const FLEE_SPEED := 90.0

var _cornered_timer := 0.0

func _ready() -> void:
	super()
	frequency = Freq.HARMONIC

func _physics_process(delta: float) -> void:
	_tick_status_timers(delta)
	if _state == State.CHASE and _player:
		var spd := FLEE_SPEED * 1.5 if _amplified else FLEE_SPEED
		var dir := (global_position - _player.global_position).normalized()
		velocity = dir * spd
		move_and_slide()
		if velocity.length() < 5.0:
			_cornered_timer += delta
			if _cornered_timer >= 2.0:
				_explode()
		else:
			_cornered_timer = 0.0
	else:
		velocity = Vector2.ZERO
		_cornered_timer = 0.0

func _do_attack() -> void:
	pass  # Fleers don't attack — only explode when cornered

func _explode() -> void:
	if _state == State.DEAD:
		return
	_state = State.DEAD
	if _player and global_position.distance_to(_player.global_position) <= 35.0:
		_player.take_damage(2)
	var ring := Polygon2D.new()
	ring.color = Color(0.831, 0.502, 0.227, 0.8)
	ring.polygon = _circle(35.0, 16)
	get_parent().add_child(ring)
	ring.global_position = global_position
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector2(1.3, 1.3), 0.25).from(Vector2(0.1, 0.1))
	tween.tween_property(ring, "modulate:a", 0.0, 0.25).from(1.0)
	tween.chain().tween_callback(ring.queue_free)
	_die()

func _circle(r: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps):
		var a := (float(i) / steps) * TAU
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts
