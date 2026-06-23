extends Node2D

## The between-runs base, now a low-res 3D iso scene (the Villa) instead of the old
## 2D diorama — same hybrid pattern as `main.gd`: the scene owns an `IsoRig` and
## mounts a 3D terrain builder (`VillaWorld`) into it, with the 2D HUD on top. There
## is no roaming warrior here, so the rig's follow camera stays disabled (the villa
## sits centred at the origin) and the player only orbits with Q/E.

const ROT_SPEED := 90.0  # deg/sec free camera orbit (Q/E), pitch stays locked

@onready var _run_label: Label = $HUD/RunLabel
@onready var _grief_bar: HBoxContainer = $HUD/GriefBar
@onready var _summon_label: Label = $HUD/SummonLabel
@onready var _clock_label: Label = $HUD/ClockLabel

var _rig: IsoRig
var _world: Node3D

func _ready() -> void:
	# --- 3D presentation: build the Villa under the shared rig (per-ring pattern). The
	# old 2D floor grid + 2D Anthe are replaced by the 3D villa, so hide them. ---
	if has_node("FloorGrid"):
		$FloorGrid.visible = false
	if has_node("Anthe"):
		$Anthe.visible = false
	_rig = load("res://scenes/iso_rig.tscn").instantiate()
	_rig.render_size = Vector2i(480, 270)  # match the rings' sharper definition (no base->ring jump)
	_world = VillaWorld.new()
	_world.apply_environment(_rig)
	add_child(_rig)
	_world.build(_rig)
	_rig.add_world_child(_world)

	_run_label.text = "RUN %d  EXT %d" % [GameState.run_count, GameState.extractions]
	_build_grief_bar()
	_update_summon_label()
	_update_clock()


func _process(delta: float) -> void:
	if not is_instance_valid(_rig):
		return
	var spin := 0.0
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_RIGHT):
		spin += 1.0
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_LEFT):
		spin -= 1.0
	if spin != 0.0:
		_rig.orbit(spin * ROT_SPEED * delta)

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
