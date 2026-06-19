extends Node

## THROWAWAY Phase 5 capture harness — delete after Ring 2 sign-off.
## Renders a ring windowed (headless can't render 3D) with both signal-frequency
## enemies revealed on the ground, so the legibility gate (signal hues vs terrain)
## can be judged. Usage:
##   /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/ring_capture.tscn -- --ring=2
## Captures the ROOT WINDOW (not the SubViewport) to docs/gen/ringN_yaw{45,135}.png.

func _ready() -> void:
	var ring := 2
	var reveal_freq := true   # --noreveal: leave enemies neutral grey (the default-state check)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ring="):
			ring = int(a.split("=")[1])
		elif a == "--noreveal":
			reveal_freq = false
	GameState.current_ring = ring

	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)

	# Let main._ready spawn enemies, then freeze + reveal them. Freezing prevents a
	# combat death (which would change_scene_to_file and free this harness mid-await
	# — the banked watchdog trap) and pins them spread across the ground.
	await get_tree().create_timer(0.3).timeout
	var enemies := get_tree().get_nodes_in_group("enemies")
	for i in range(enemies.size()):
		var e := enemies[i]
		e.set_physics_process(false)
		e.set_process(false)
		e.frequency = 0 if i % 2 == 0 else 1  # 0=DISSONANT (pink), 1=HARMONIC (lavender)
		if reveal_freq:
			e.reveal(9999.0)

	var suffix := "" if reveal_freq else "_neutral"

	# Cold launch compiles the cel/post shaders — give it generous headroom.
	for _n in range(150):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_capture("res://docs/gen/ring%d_yaw45%s.png" % [ring, suffix])

	# Orbit 90 deg and recapture to confirm legibility survives camera rotation.
	main._rig.orbit(90.0)
	for _n in range(30):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_capture("res://docs/gen/ring%d_yaw135%s.png" % [ring, suffix])

	get_tree().quit()


func _capture(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(path))
	print("captured ", path)
