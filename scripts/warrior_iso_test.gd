extends Node

## THROWAWAY Phase 2 verification harness. Owns the rig (the Phase-4 `main`
## arrangement), injects it into Ring1, mounts the warrior's 2D body + WarriorSync.
## Delete after Phase 2 sign-off.
##
## Discriminator (proves input is camera-relative, not world-fixed): hold a FIXED
## raw "up" and capture at yaw 45 and 135. Correct => billboard moves toward
## screen-top AND shows the away/"north" sheet in BOTH, while the warrior's *sim*
## (x,y) differs between the two (the raw input was rotated by yaw). Windowed only
## (`-- --capture [yaw=NNN] [drive=up]`); headless can't render 3D.

const CAPTURE_DIR := "res://docs/gen/"

var _rig: IsoRig
var _ring1: Ring1
var _warrior: CharacterBody2D
var _sync: WarriorSync


func _ready() -> void:
	_rig = load("res://scenes/iso_rig.tscn").instantiate()
	add_child(_rig)

	_ring1 = load("res://scenes/ring1.tscn").instantiate()
	_ring1.rig = _rig  # inject before it enters the tree
	add_child(_ring1)

	_warrior = load("res://scenes/warrior.tscn").instantiate()
	_warrior.position = Vector2(240.0, 135.0)  # sim centre -> world origin
	add_child(_warrior)

	_sync = WarriorSync.new()
	add_child(_sync)
	_sync.setup(_rig, _warrior)

	var args := OS.get_cmdline_user_args()
	if "--capture" in args:
		_run_capture(args)


func _process(delta: float) -> void:
	# Live orbit for interactive inspection (Ring1 also orbits; harmless overlap).
	var spin := 0.0
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_RIGHT):
		spin += 1.0
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_LEFT):
		spin -= 1.0
	if spin != 0.0:
		_rig.orbit(spin * 90.0 * delta)


func _run_capture(args: PackedStringArray) -> void:
	get_tree().create_timer(14.0).timeout.connect(func() -> void: get_tree().quit(2))
	var yaw := 45.0
	var drive := Vector2.INF  # idle unless drive=up
	for a in args:
		if a.begins_with("yaw="):
			yaw = float(a.trim_prefix("yaw="))
		elif a == "drive=up":
			drive = Vector2(0.0, -1.0)
	_rig.orbit(yaw - _rig.get_yaw())

	# The warrior spawns in SUMMONING (2.5s) and ignores input until IDLE — wait
	# it out, then apply the fixed drive and let the body translate + face.
	await get_tree().create_timer(2.8).timeout
	_sync.raw_input_override = drive
	await get_tree().create_timer(1.0).timeout

	for i in range(4):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

	var tag := "idle" if drive == Vector2.INF else "up"
	var path := "%swarrior_phase2_%s_yaw%d.png" % [CAPTURE_DIR, tag, int(_rig.get_yaw())]
	var err := _rig.get_post_viewport().get_texture().get_image().save_png(path)
	# Surface the sim position — the discriminator compares this across yaws.
	push_warning("warrior_iso_test: drive=%s yaw=%d sim_pos=%s world_pos=%s facing=%s saved=%s (err %d)" % [
		tag, int(_rig.get_yaw()), _warrior.global_position, _sync.get_billboard_position(),
		_sync.get_facing(), path, err])
	get_tree().quit(0 if err == OK else 1)
