extends Node

## CI compile gate: loads every .gd in the project and reports the ones that fail.
##
## Why a scene and not `godot --check-only --script`: `--check-only` compiles a script
## in isolation, without the project's autoloads registered, so every script that
## references `GameState` fails with "Identifier not found" — 16 false positives out of
## 46. Running inside a scene means the SceneTree has installed the autoloads, so the
## compile matches what the game actually does.
##
## Driven by `verify.sh`. Prints a single machine-readable result line, because Godot
## exits 0 whether or not scripts failed to load:
##
##     COMPILE CHECK: N checked, M failed
##
## `addons/` is skipped — third-party code, not ours to gate on.

const SKIP_DIRS: PackedStringArray = ["res://.godot", "res://addons"]


func _ready() -> void:
	var scripts: PackedStringArray = []
	_collect("res://", scripts)
	scripts.sort()

	var failed: PackedStringArray = []
	for path in scripts:
		# A parse/compile failure prints its own SCRIPT ERROR to stderr and yields null.
		var res: Resource = load(path)
		if res == null or not (res is GDScript):
			failed.append(path)

	print("")
	for path in failed:
		print("  FAILED  ", path)
	print("COMPILE CHECK: %d checked, %d failed" % [scripts.size(), failed.size()])
	get_tree().quit()


## Recursively gather .gd paths, skipping the engine cache and third-party addons.
func _collect(dir_path: String, out: PackedStringArray) -> void:
	for skip in SKIP_DIRS:
		if dir_path.begins_with(skip):
			return
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full: String = dir_path.path_join(entry) if dir_path != "res://" else "res://" + entry
		if dir.current_is_dir():
			_collect(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
