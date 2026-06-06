# Build tool — generates Ring 1 TileSet resources from the fetched PixelLab
# tilesets + their metadata. Run headless:
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
#       --script res://scripts/build_ring1_tilesets.gd
#
# Produces:
#   assets/tiles/ring1/ground.tres  — ground_path + ground_flora as two atlas
#       sources in ONE corner-match terrain set (stone=0, path=1, flora=2).
#   assets/tiles/ring1/cliff.tres   — atlas source + physics layer scaffold.
#       Cliff terrain/Y-sort is deferred to in-editor setup: the upstream
#       metadata's tile placement is unreliable (see docs/RING1_TILES.md).
extends SceneTree

const DIR := "res://assets/tiles/ring1/"
const TILE := Vector2i(32, 32)

# Corner key in metadata -> Godot corner peering bit.
const CORNER_BITS := {
	"NW": TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
	"NE": TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
	"SE": TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
	"SW": TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
}

# Terrain indices in the shared ground terrain set.
const T_STONE := 0
const T_PATH := 1
const T_FLORA := 2


func _init() -> void:
	var ok := true
	ok = _build_ground() and ok
	ok = _build_cliff() and ok
	if ok:
		ok = _verify()
	print("BUILD ", "OK" if ok else "FAILED")
	quit(0 if ok else 1)


func _load_meta(name: String) -> Dictionary:
	var f := FileAccess.open(DIR + name, FileAccess.READ)
	if f == null:
		push_warning("cannot open %s" % name)
		return {}
	return JSON.parse_string(f.get_as_text())


func _add_atlas(ts: TileSet, png: String) -> TileSetAtlasSource:
	var tex: Texture2D = load(DIR + png)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = TILE
	ts.add_source(src)
	return src


# Create every tile listed in the metadata, returning a map of
# atlas-coords -> tile corner dict so the caller can assign terrain.
func _create_tiles(src: TileSetAtlasSource, meta: Dictionary) -> Array:
	var out: Array = []
	for tile in meta["tileset_data"]["tiles"]:
		var bb: Dictionary = tile["bounding_box"]
		var coords := Vector2i(int(bb["x"]) / TILE.x, int(bb["y"]) / TILE.y)
		if not src.has_tile(coords):
			src.create_tile(coords)
		out.append({"coords": coords, "corners": tile["corners"]})
	return out


func _assign_corners(src: TileSetAtlasSource, tiles: Array, terrain_set: int,
		lower_terrain: int, upper_terrain: int) -> void:
	for entry in tiles:
		var td: TileData = src.get_tile_data(entry["coords"], 0)
		td.terrain_set = terrain_set
		var corners: Dictionary = entry["corners"]
		var counts := {lower_terrain: 0, upper_terrain: 0}
		for key in CORNER_BITS:
			var terrain := upper_terrain if corners[key] == "upper" else lower_terrain
			td.set_terrain_peering_bit(CORNER_BITS[key], terrain)
			counts[terrain] += 1
		# Dominant corner terrain as the tile's own terrain (used when painting).
		td.terrain = upper_terrain if counts[upper_terrain] >= counts[lower_terrain] else lower_terrain


func _build_ground() -> bool:
	var path_meta := _load_meta("ground_path.metadata.json")
	var flora_meta := _load_meta("ground_flora.metadata.json")
	if path_meta.is_empty() or flora_meta.is_empty():
		return false

	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_SQUARE
	ts.tile_size = TILE

	ts.add_terrain_set()
	var ts_idx := ts.get_terrain_sets_count() - 1
	ts.set_terrain_set_mode(ts_idx, TileSet.TERRAIN_MODE_MATCH_CORNERS)
	ts.add_terrain(ts_idx)  # 0
	ts.add_terrain(ts_idx)  # 1
	ts.add_terrain(ts_idx)  # 2
	ts.set_terrain_name(ts_idx, T_STONE, "stone")
	ts.set_terrain_name(ts_idx, T_PATH, "path")
	ts.set_terrain_name(ts_idx, T_FLORA, "flora")
	ts.set_terrain_color(ts_idx, T_STONE, Color("#8898a8"))
	ts.set_terrain_color(ts_idx, T_PATH, Color("#b8a890"))
	ts.set_terrain_color(ts_idx, T_FLORA, Color("#d4dce8"))

	var path_src := _add_atlas(ts, "ground_path.png")
	var path_tiles := _create_tiles(path_src, path_meta)
	_assign_corners(path_src, path_tiles, ts_idx, T_STONE, T_PATH)

	var flora_src := _add_atlas(ts, "ground_flora.png")
	var flora_tiles := _create_tiles(flora_src, flora_meta)
	_assign_corners(flora_src, flora_tiles, ts_idx, T_STONE, T_FLORA)

	var err := ResourceSaver.save(ts, DIR + "ground.tres")
	if err != OK:
		push_warning("save ground.tres failed: %d" % err)
		return false
	print("wrote ground.tres (path tiles=%d, flora tiles=%d)" % [path_tiles.size(), flora_tiles.size()])
	return true


func _build_cliff() -> bool:
	# Cliff metadata placement is unreliable, so build only what's safe:
	# one atlas source over every non-empty 32x32 cell + a physics layer.
	# Terrain matching and per-tile collision/Y-sort are left for the editor.
	var tex: Texture2D = load(DIR + "cliff.png")
	if tex == null:
		push_warning("cannot load cliff.png")
		return false
	var img := tex.get_image()
	var cols := int(tex.get_width()) / TILE.x
	var rows := int(tex.get_height()) / TILE.y

	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_SQUARE
	ts.tile_size = TILE
	ts.add_physics_layer()  # scaffold for cliff-face collision

	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = TILE
	ts.add_source(src)

	var made := 0
	for ty in rows:
		for tx in cols:
			var region := Rect2i(tx * TILE.x, ty * TILE.y, TILE.x, TILE.y)
			if _region_has_pixels(img, region):
				src.create_tile(Vector2i(tx, ty))
				made += 1

	var err := ResourceSaver.save(ts, DIR + "cliff.tres")
	if err != OK:
		push_warning("save cliff.tres failed: %d" % err)
		return false
	print("wrote cliff.tres (atlas %dx%d cells, %d non-empty tiles, 1 physics layer)" % [cols, rows, made])
	return true


func _region_has_pixels(img: Image, region: Rect2i) -> bool:
	for y in range(region.position.y, region.position.y + region.size.y):
		for x in range(region.position.x, region.position.x + region.size.x):
			if img.get_pixel(x, y).a > 0.0:
				return true
	return false


func _verify() -> bool:
	var ts: TileSet = load(DIR + "ground.tres")
	if ts == null:
		push_warning("verify: ground.tres did not load")
		return false
	var ok := true
	if ts.get_terrain_sets_count() != 1:
		push_warning("verify: terrain set count = %d (want 1)" % ts.get_terrain_sets_count())
		ok = false
	if ts.get_terrains_count(0) != 3:
		push_warning("verify: terrain count = %d (want 3)" % ts.get_terrains_count(0))
		ok = false
	if ts.get_terrain_set_mode(0) != TileSet.TERRAIN_MODE_MATCH_CORNERS:
		push_warning("verify: terrain mode not MATCH_CORNERS")
		ok = false
	# Spot-check: ground_path wang_0 (all lower) and wang_15 (all upper).
	var meta := _load_meta("ground_path.metadata.json")
	var src: TileSetAtlasSource = ts.get_source(ts.get_source_id(0))
	var checked := 0
	for tile in meta["tileset_data"]["tiles"]:
		var bb: Dictionary = tile["bounding_box"]
		var coords := Vector2i(int(bb["x"]) / TILE.x, int(bb["y"]) / TILE.y)
		var corners: Dictionary = tile["corners"]
		var all_lower := corners.values().all(func(v): return v == "lower")
		var all_upper := corners.values().all(func(v): return v == "upper")
		if all_lower or all_upper:
			var td: TileData = src.get_tile_data(coords, 0)
			var want := T_PATH if all_upper else T_STONE
			for key in CORNER_BITS:
				var got := td.get_terrain_peering_bit(CORNER_BITS[key])
				if got != want:
					push_warning("verify: tile %s corner %s = %d (want %d)" % [tile["name"], key, got, want])
					ok = false
			checked += 1
	print("verify: checked %d all-corner tiles, terrain sets/terrains/mode OK=%s" % [checked, ok])
	return ok
