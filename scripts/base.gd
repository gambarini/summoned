extends Node2D

## The between-runs base, now a low-res 3D iso scene (the Villa) instead of the old
## 2D diorama — same hybrid pattern as `main.gd`: the scene owns an `IsoRig` and
## mounts a 3D terrain builder (`VillaWorld`) into it, with the 2D HUD on top. There
## is no roaming warrior here, so the rig's follow camera stays disabled (the villa
## sits centred at the origin) and the player only orbits with Q/E (`orbit_left` /
## `orbit_right`). Venture Out is on Enter (`venture_out`), NOT E — E is an orbit key
## here, and the old `interact` binding double-booked it into an instant scene change.

const ROT_SPEED := 90.0  # deg/sec free camera orbit (Q/E), pitch stays locked

@onready var _run_label: Label = $HUD/RunLabel
@onready var _grief_bar: HBoxContainer = $HUD/GriefBar
@onready var _summon_label: Label = $HUD/SummonLabel
@onready var _clock_label: Label = $HUD/ClockLabel
@onready var _wait_prompt: Label = $HUD/WaitPrompt

## The wait prompt's colours: available, and greyed when the trade is off the table.
const WAIT_COLOR_READY := Color("#D4C4A8")
const WAIT_COLOR_BLOCKED := Color("#5A4A6A")

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
	_update_wait_prompt()


func _process(delta: float) -> void:
	if not is_instance_valid(_rig):
		return
	var spin := 0.0
	if Input.is_action_pressed("orbit_right"):
		spin += 1.0
	if Input.is_action_pressed("orbit_left"):
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
	var filled := mini(ticks, GameState.MAX_CLOCK)
	var dot_str := ""
	for i in range(GameState.MAX_CLOCK):
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

# Show whether the tick-for-reserve trade is available, and why not when it isn't — the
# prompt used to advertise "[TAB] Wait" unconditionally even when the press did nothing
# (or, at a capped clock, handed out reserve for free).
func _update_wait_prompt() -> void:
	var reason: String = GameState.wait_blocked_reason()
	if reason.is_empty():
		_wait_prompt.text = "[TAB] Wait  +%d GRIEF / +1 TICK" % GameState.GRIEF_GAIN_ON_WAIT
		_wait_prompt.add_theme_color_override("font_color", WAIT_COLOR_READY)
	else:
		_wait_prompt.text = "[TAB] Wait  " + reason
		_wait_prompt.add_theme_color_override("font_color", WAIT_COLOR_BLOCKED)


# The reserve recovers, but the world moves on: waiting spends a tick of Anthe's Clock.
# GameState.wait() owns the trade (and refuses it when the clock can't advance), so a
# refused press must not repaint as if something happened.
func _do_wait() -> void:
	if not GameState.wait():
		_update_wait_prompt()
		return
	_refresh_grief_bar()
	_update_summon_label()
	_update_clock()
	_update_wait_prompt()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("venture_out"):
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	elif event.is_action_pressed("wait"):
		_do_wait()
