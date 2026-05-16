extends Node2D

const CELL := 16
const COLS := 60
const ROWS := 40
const FILL := Color(0.055, 0.031, 0.102, 1)  # just below clear color
const LINE := Color(0.106, 0.067, 0.188, 1)  # subtle grid lines

func _draw() -> void:
	var w := float(CELL * COLS)
	var h := float(CELL * ROWS)
	draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h), FILL)
	for x in range(COLS + 1):
		var px := -w * 0.5 + x * CELL
		draw_line(Vector2(px, -h * 0.5), Vector2(px, h * 0.5), LINE)
	for y in range(ROWS + 1):
		var py := -h * 0.5 + y * CELL
		draw_line(Vector2(-w * 0.5, py), Vector2(w * 0.5, py), LINE)
