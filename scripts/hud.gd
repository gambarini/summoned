extends CanvasLayer

const DOT_ACTIVE := Color(0.941, 0.910, 0.847, 1)   # #F0E8D8 — Hollow centre
const DOT_INACTIVE := Color(0.165, 0.082, 0.282, 1)  # #2A1448 — Body dark
const DOT_ACTIVE_RESONANCE := Color(0.753, 0.627, 0.941, 1)

@onready var _status_label: Label = $StatusLabel
var _status_tween: Tween

func show_status(text: String, color: Color) -> void:
	if _status_tween:
		_status_tween.kill()
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)
	_status_label.modulate.a = 0.0
	_status_tween = create_tween()
	_status_tween.tween_property(_status_label, "modulate:a", 1.0, 0.3)

func bind(warrior: CharacterBody2D) -> void:
	for i in range(warrior.MAX_COHERENCE):
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(6, 6)
		$CoherenceBar.add_child(dot)
	warrior.coherence_changed.connect(_update_coherence)
	warrior.chain_changed.connect(_update_chain)
	warrior.resonance_ready.connect(_update_resonance)
	_update_coherence(warrior.coherence)
	_update_chain(warrior.chain)
	_update_resonance(true)

func _update_coherence(value: int) -> void:
	for i in range($CoherenceBar.get_child_count()):
		($CoherenceBar.get_child(i) as ColorRect).color = \
			DOT_ACTIVE if i < value else DOT_INACTIVE

func _update_chain(value: int) -> void:
	$ChainLabel.text = "CHAIN  %d / 4" % value

func _update_resonance(is_ready: bool) -> void:
	$ResonanceDot.color = DOT_ACTIVE_RESONANCE if is_ready else DOT_INACTIVE
