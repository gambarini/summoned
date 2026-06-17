extends Node2D

# ── Bright "blade" core geometry ──────────────────────────────────────────────
const INNER_R    := 8.0
const OUTER_R    := 30.0
const HALF_ANGLE := 60.0
const STEPS      := 16

# ── Hit wedge ─────────────────────────────────────────────────────────────────
# A solid pie slice (tiny inner radius = no dead-zone) sized to the visible
# sweep, so "what you see is what you hit". It travels with the node, so it
# sweeps the whole corridor in front of the warrior.
const HIT_INNER_R    := 3.0
const HIT_OUTER_R    := 36.0
const HIT_HALF_ANGLE := 62.0

# ── Travel ────────────────────────────────────────────────────────────────────
const HAND_OFFSET  := 12.0  # px from warrior center to spawn point (at the hand)
const TRAVEL_DIST  := 52.0  # px the arc travels forward
const DURATION     := 0.32  # total lifetime in seconds
const SWEEP_ANGLE  := 8.0   # deg the blade rotates across the cone while travelling

signal hit_target(area: Area2D)

var _dir: Vector2 = Vector2.RIGHT
var _base_rot: float = 0.0
var _hit_areas: Array[Area2D] = []

func _ready() -> void:
	# Self-group so WorldSync mirrors a flat 3D slash for the arc's brief life
	# (Phase 3 hybrid; collision stays 2D via HitArea). Harmless in pure-2D runs.
	add_to_group("attack_arcs")
	var glow_poly  := _build_arc_polygon(INNER_R * 0.3, OUTER_R * 1.45, HALF_ANGLE + 7.0,  STEPS)
	var core_poly  := _build_arc_polygon(INNER_R,       OUTER_R,        HALF_ANGLE,         STEPS)
	var inner_poly := _build_arc_polygon(INNER_R * 1.1, OUTER_R * 0.72, HALF_ANGLE - 20.0,  STEPS)
	var hit_poly   := _build_arc_polygon(HIT_INNER_R,   HIT_OUTER_R,    HIT_HALF_ANGLE,     STEPS)
	$ArcGlow.polygon  = glow_poly
	$ArcCore.polygon  = core_poly
	$ArcInner.polygon = inner_poly
	$HitArea/HitShape.polygon = hit_poly
	$HitArea.area_entered.connect(_on_area_entered)

func set_direction(dir: Vector2) -> void:
	_dir = dir
	_base_rot = dir.angle()
	# Start the blade rotated to one side so the travel reads as a slash sweep.
	rotation = _base_rot - deg_to_rad(SWEEP_ANGLE)
	# Shift spawn point forward to the warrior's hand
	global_position += dir * HAND_OFFSET
	scale = Vector2(0.5, 0.6)
	_animate()

func _animate() -> void:
	var end_gp := global_position + _dir * TRAVEL_DIST
	var fade_at := DURATION * 0.45

	# Drive on the physics clock so the hit area's transform stays in lockstep
	# with collision detection — no overlaps are missed mid-sweep.
	var p := create_tween().set_parallel(true).set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)

	# Travel: fast start, eases to a stop
	p.tween_property(self, "global_position", end_gp, DURATION) \
	 .set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Slash sweep: rotate across the cone as it travels
	p.tween_property(self, "rotation", _base_rot + deg_to_rad(SWEEP_ANGLE), DURATION) \
	 .set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# Scale punch: snap to full size quickly
	p.tween_property(self, "scale", Vector2(1.15, 1.05), 0.11) \
	 .from(Vector2(0.5, 0.6)).set_ease(Tween.EASE_OUT)

	# Glow layer fades throughout the whole travel
	p.tween_property($ArcGlow, "modulate:a", 0.0, DURATION).from(0.6)

	# Core and inner hold bright, then fade in the second half
	p.tween_property($ArcCore,  "modulate:a", 0.0, DURATION * 0.55) \
	 .from(1.0).set_delay(fade_at)
	p.tween_property($ArcInner, "modulate:a", 0.0, DURATION * 0.55) \
	 .from(0.9).set_delay(fade_at)

	p.chain().tween_callback(queue_free)

func _on_area_entered(area: Area2D) -> void:
	if area not in _hit_areas:
		_hit_areas.append(area)
		hit_target.emit(area)

func _build_arc_polygon(inner_r: float, outer_r: float, half_angle_deg: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var half_a := deg_to_rad(half_angle_deg)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var a := lerpf(-half_a, half_a, t)
		pts.append(Vector2(cos(a), sin(a)) * outer_r)
	for i in range(steps + 1):
		var t := float(steps - i) / float(steps)
		var a := lerpf(-half_a, half_a, t)
		pts.append(Vector2(cos(a), sin(a)) * inner_r)
	return pts
