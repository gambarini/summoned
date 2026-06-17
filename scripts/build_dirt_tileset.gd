# Build tool — Ring 1 dirt-ground TileSet (v4, PixelLab create_tiles_pro).
#
# Builds a DISCRETE 48px atlas TileSet from the cleaned/curated cold packed-earth
# tiles in dirt_tiles.png (see scripts/cleanup_dirt_tiles.py and
# docs/RING1_TILES.md). No terrain/Wang matching: distinct material tiles
# scattered by ground_layer.gd. This DIRT set is the new dirt-dominant Ring 1
# default and supersedes the bare-stone v3 ground_tiles.tres for main.tscn.
#
# Run headless:
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
#   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
#       --script res://scripts/build_dirt_tileset.gd
extends SceneTree

const DIR := "res://assets/tiles/ring1/"
const PNG := "dirt_tiles.png"
const OUT := "dirt_tiles.tres"
const TILE := Vector2i(48, 48)
const WANT_TILES := 12


func _init() -> void:
	var ok := _build()
	if ok:
		ok = _verify()
	print("BUILD ", "OK" if ok else "FAILED")
	quit(0 if ok else 1)


func _build() -> bool:
	var tex: Texture2D = load(DIR + PNG)
	if tex == null:
		push_warning("cannot load %s" % PNG)
		return false
	var img := tex.get_image()
	var cols := int(tex.get_width()) / TILE.x
	var rows := int(tex.get_height()) / TILE.y

	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_SQUARE
	ts.tile_size = TILE

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

	var err := ResourceSaver.save(ts, DIR + OUT)
	if err != OK:
		push_warning("save %s failed: %d" % [OUT, err])
		return false
	print("wrote %s (atlas %dx%d cells, %d tiles, %dpx)" % [OUT, cols, rows, made, TILE.x])
	return true


func _region_has_pixels(img: Image, region: Rect2i) -> bool:
	for y in range(region.position.y, region.position.y + region.size.y):
		for x in range(region.position.x, region.position.x + region.size.x):
			if img.get_pixel(x, y).a > 0.0:
				return true
	return false


func _verify() -> bool:
	var ts: TileSet = load(DIR + OUT)
	if ts == null:
		push_warning("verify: %s did not load" % OUT)
		return false
	var ok := true
	if ts.tile_size != TILE:
		push_warning("verify: tile_size %s (want %s)" % [ts.tile_size, TILE])
		ok = false
	var src: TileSetAtlasSource = ts.get_source(ts.get_source_id(0))
	if src.get_tiles_count() != WANT_TILES:
		push_warning("verify: tile count %d (want %d)" % [src.get_tiles_count(), WANT_TILES])
		ok = false
	print("verify: tile_size OK=%s, tiles=%d" % [ts.tile_size == TILE, src.get_tiles_count()])
	return ok
