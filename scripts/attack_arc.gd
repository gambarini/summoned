extends Node2D

signal hit_target(area: Area2D)

var _hit_areas: Array[Area2D] = []

func _ready() -> void:
	var polygon := _build_arc_polygon(10.0, 28.0, 60.0, 8)
	$Arc.polygon = polygon
	$HitArea/HitShape.polygon = polygon
	$HitArea.area_entered.connect(_on_area_entered)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.25).from(Vector2(0.6, 0.6))
	tween.tween_property(self, "modulate:a", 0.0, 0.25).from(1.0)
	tween.chain().tween_callback(queue_free)

func set_direction(dir: Vector2) -> void:
	rotation = dir.angle()

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
