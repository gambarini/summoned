extends "res://scripts/enemy.gd"

const PHASE_INTERVAL := 2.0

var _phase_timer := 0.0

func _ready() -> void:
	super()
	_visual.color = _current_color()

func _current_color() -> Color:
	if _amplified:
		return Color(0.831, 0.502, 0.227, 1)
	return COLORS[frequency]  # always show freq — never neutral grey

func _physics_process(delta: float) -> void:
	super(delta)
	if _state == State.DEAD:
		return
	_phase_timer += delta
	if _phase_timer >= PHASE_INTERVAL:
		_phase_timer = 0.0
		frequency = Freq.HARMONIC if frequency == Freq.DISSONANT else Freq.DISSONANT
		_visual.color = _current_color()
