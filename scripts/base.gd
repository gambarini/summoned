extends Node2D

@onready var _run_label: Label = $HUD/RunLabel
@onready var _grief_bar: HBoxContainer = $HUD/GriefBar
@onready var _summon_label: Label = $HUD/SummonLabel
@onready var _clock_label: Label = $HUD/ClockLabel

func _ready() -> void:
	_run_label.text = "RUN %d  EXT %d" % [GameState.run_count, GameState.extractions]
	_build_grief_bar()
	_update_summon_label()
	_update_clock()

func _build_grief_bar() -> void:
	for i in range(GameState.MAX_GRIEF):
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(6, 6)
		dot.color = Color("#C4547A") if i < GameState.grief_reserve else Color("#2A1448")
		_grief_bar.add_child(dot)

func _refresh_grief_bar() -> void:
	var children := _grief_bar.get_children()
	for i in range(children.size()):
		(children[i] as ColorRect).color = Color("#C4547A") if i < GameState.grief_reserve else Color("#2A1448")

func _update_summon_label() -> void:
	var g := GameState.grief_reserve
	if g >= 7:
		_summon_label.text = "NORMAL SUMMONING"
		_summon_label.add_theme_color_override("font_color", Color("#7B4EA0"))
	elif g >= 4:
		_summon_label.text = "DEPLETED SUMMONING"
		_summon_label.add_theme_color_override("font_color", Color("#D4803A"))
	else:
		_summon_label.text = "CRITICAL SUMMONING"
		_summon_label.add_theme_color_override("font_color", Color("#C4547A"))

func _update_clock() -> void:
	var ticks := GameState.clock_ticks
	var filled := mini(ticks, 10)
	var dot_str := ""
	for i in range(10):
		dot_str += "●" if i < filled else "○"
	if GameState.is_last_song():
		_clock_label.text = "ANTHE  " + dot_str + "  LAST SONG"
		_clock_label.add_theme_color_override("font_color", Color("#FF4466"))
	elif ticks >= 8:
		_clock_label.text = "ANTHE  " + dot_str + "  WEAKENING"
		_clock_label.add_theme_color_override("font_color", Color("#C4547A"))
	else:
		_clock_label.text = "ANTHE  " + dot_str
		_clock_label.remove_theme_color_override("font_color")

func _do_wait() -> void:
	GameState.grief_reserve = min(GameState.grief_reserve + 2, GameState.MAX_GRIEF)
	GameState.advance_clock()
	_refresh_grief_bar()
	_update_summon_label()
	_update_clock()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_TAB:
		_do_wait()
