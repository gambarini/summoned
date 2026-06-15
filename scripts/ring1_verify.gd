extends Node

## THROWAWAY Phase 1 verification harness — captures the Ring 1 playfield for
## comparison against the spike baselines (`docs/gen/ring1_iso_spike*.png`). The
## IsoRig defaults are a verbatim port of the spike's camera/env, so a faithful
## terrain port should reproduce those frames. Delete once Phase 1 is signed off.
##
## Drops a throwaway billboard at the spike's exact warrior spot so the only
## intended diff (the warrior, which is Phase 2) overlays 1:1 — any *other*
## difference is a real port error. Windowed only (`-- --capture [yaw=NNN]`);
## headless can't render 3D.

const CAPTURE_PATH := "res://docs/gen/ring1_phase1.png"

var _ring1: Ring1


func _ready() -> void:
	_ring1 = load("res://scenes/ring1.tscn").instantiate()
	add_child(_ring1)  # Ring1._ready runs here, so _ring1.rig is live after this

	# Throwaway stand-in for the Phase-2 warrior, at the spike's exact spot.
	var sprite := Sprite3D.new()
	sprite.texture = load("res://assets/sprites/warrior_8dir/south.png")
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	sprite.pixel_size = 0.045
	sprite.position = Vector3(-1.0, 2.0, 1.0)
	_ring1.rig.add_world_child(sprite)

	var args := OS.get_cmdline_user_args()
	if "--capture" in args:
		for a in args:
			if a.begins_with("yaw="):
				_ring1.rig.orbit(float(a.trim_prefix("yaw=")) - _ring1.rig.get_yaw())
		_capture_and_quit()


func _capture_and_quit() -> void:
	get_tree().create_timer(8.0).timeout.connect(func() -> void: get_tree().quit(2))
	for i in range(4):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var img := _ring1.rig.get_post_viewport().get_texture().get_image()
	var path := CAPTURE_PATH
	if _ring1.rig.get_yaw() != _ring1.rig.initial_yaw:
		path = "res://docs/gen/ring1_phase1_yaw%d.png" % int(_ring1.rig.get_yaw())
	var err := img.save_png(path)
	if err != OK:
		push_warning("ring1_verify: capture failed (%d)" % err)
	get_tree().quit(0 if err == OK else 1)
