extends Node

## THROWAWAY dev launcher — play any ring directly with full live input.
## Presets GameState.current_ring from the command line, then hands off to the
## real main.tscn (a fully playable run: WASD move, mouse aim + click attack,
## R resonance, F extract, Q/E + arrows orbit). Delete with the capture harness
## once rings 4–5 are signed off.
##
## Usage (windowed — headless can't render 3D):
##   /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/play_ring.tscn -- --ring=2
## Omit --ring to default to Ring 2.

func _ready() -> void:
	var ring := 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ring="):
			ring = int(a.split("=")[1])
	# Dev harness: never write the player's save (this scene forces GameState fields).
	GameState.persist_enabled = false
	GameState.current_ring = clampi(ring, 1, GameState.HIGHEST_BUILT_RING)
	# Defer one frame: change_scene_to_file in _ready fires while the tree is still
	# busy adding this launcher node (remove_child can't run then).
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/main.tscn")
