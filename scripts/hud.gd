extends CanvasLayer

const DOT_ACTIVE := Color(0.941, 0.910, 0.847, 1)   # #F0E8D8 — Hollow centre
const DOT_INACTIVE := Color(0.165, 0.082, 0.282, 1)  # #2A1448 — Body dark
const MAX_COHERENCE := 10

func _ready() -> void:
	for i in range(MAX_COHERENCE):
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(6, 6)
		$CoherenceBar.add_child(dot)
	_update_coherence(MAX_COHERENCE)
	_update_chain(0)

func bind(warrior: CharacterBody2D) -> void:
	warrior.coherence_changed.connect(_update_coherence)
	warrior.chain_changed.connect(_update_chain)

func _update_coherence(value: int) -> void:
	for i in range($CoherenceBar.get_child_count()):
		($CoherenceBar.get_child(i) as ColorRect).color = \
			DOT_ACTIVE if i < value else DOT_INACTIVE

func _update_chain(value: int) -> void:
	$ChainLabel.text = "CHAIN  %d / 5" % value
