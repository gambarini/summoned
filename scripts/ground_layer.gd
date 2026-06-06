# Paints a Ring 1 ground field at runtime using the stone→path Wang terrain set
# in ground.tres. Exercises real corner-match autotiling rather than baking
# cells, so it doubles as a playtest of the terrain wiring.
#
# Terrains (see docs/RING1_TILES.md): 0 = stone (base), 1 = path.
# Flora is no longer a ground terrain — it is placed as map-object props
# (assets/tiles/ring1/props/), so the ground is a single stone→path Wang set.
extends TileMapLayer

const TERRAIN_SET := 0
const T_STONE := 0
const T_PATH := 1

# Which overlay terrain to paint over the stone base.
enum Layout { PLAIN_STONE, PATH_ONLY, DEMO }

# Field size in cells. 15x9 ~= the 480x270 play area at 32px tiles.
@export var grid_size: Vector2i = Vector2i(15, 9)
# Stone-only for now: the path tiles are in the atlas but the generated trail
# read poorly (harsh outline), so we paint plain stone until the path art is
# redone. Switch to PATH_ONLY / DEMO once the path tileset is reworked.
@export var layout: Layout = Layout.PLAIN_STONE


func _ready() -> void:
	_fill(T_STONE, _rect_cells(Vector2i.ZERO, grid_size))
	if layout == Layout.PATH_ONLY or layout == Layout.DEMO:
		_fill(T_PATH, _path_cross())


# Worn footpath: a cross centred on the spawn cell.
func _path_cross() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var mid := grid_size / 2
	for y in grid_size.y:
		cells.append(Vector2i(mid.x, y))
	for x in grid_size.x:
		cells.append(Vector2i(x, mid.y))
	return cells


func _fill(terrain: int, cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		return
	set_cells_terrain_connect(cells, TERRAIN_SET, terrain, false)


func _rect_cells(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			cells.append(origin + Vector2i(x, y))
	return cells
