# Paints a Ring 1 ground field at runtime using the shared stone/path/flora
# terrain set in ground.tres. Exercises real corner-match autotiling rather than
# baking cells, so it doubles as a playtest of the terrain wiring.
#
# Terrains (see docs/RING1_TILES.md): 0 = stone (base), 1 = path, 2 = flora.
# Path and flora are separate 2-terrain Wang sets with no path<->flora transition
# tile, so their painted regions are kept apart by a stone gap.
extends TileMapLayer

const TERRAIN_SET := 0
const T_STONE := 0
const T_PATH := 1
const T_FLORA := 2

# Which overlay terrains to paint over the stone base. PATH and FLORA are kept
# apart by a stone gap in DEMO since the two Wang sets share only stone.
enum Layout { PLAIN_STONE, PATH_ONLY, FLORA_ONLY, DEMO }

# Field size in cells. 15x9 ~= the 480x270 play area at 32px tiles.
@export var grid_size: Vector2i = Vector2i(15, 9)
@export var layout: Layout = Layout.DEMO


func _ready() -> void:
	_fill(T_STONE, _rect_cells(Vector2i.ZERO, grid_size))
	if layout == Layout.PATH_ONLY or layout == Layout.DEMO:
		_fill(T_PATH, _path_cross())
	if layout == Layout.FLORA_ONLY or layout == Layout.DEMO:
		# Top-left patch, held a stone cell clear of the path cross.
		_fill(T_FLORA, _rect_cells(Vector2i(1, 1), Vector2i(3, 3)))


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
