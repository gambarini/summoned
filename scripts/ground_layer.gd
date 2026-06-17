# Paints the Ring 1 ground field at runtime by scattering discrete 48px tiles
# from ground_tiles.tres (PixelLab create_tiles_pro, de-rimmed — see
# docs/RING1_TILES.md). These are distinct material tiles, not corner-blended
# terrain, so we place them cell-by-cell with weighted random selection.
#
# Atlas layout (4x3, see scripts/cleanup_ground_tiles.py LAYOUT):
#   plain     = (0,0) (2,0)           bare grey-blue stone (primary)
#   mottled   = (3,0)                 cloudy lighter stone (subtle variation)
#   pebble    = (0,1) (1,1) (2,1)     grit / gravel accents
#   flagstone = (1,0) (3,1)           brick / cobble paving (opt-in)
#   path      = (0,2) (1,2)           trodden dirt strips (opt-in)
#   sediment  = (2,2)                 wavy sediment (opt-in)
extends TileMapLayer

const PLAIN: Array[Vector2i] = [Vector2i(0, 0), Vector2i(2, 0)]
const MOTTLED: Array[Vector2i] = [Vector2i(3, 0)]
const PEBBLE: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]
const FLAGSTONE: Array[Vector2i] = [Vector2i(1, 0), Vector2i(3, 1)]
const PATH: Array[Vector2i] = [Vector2i(0, 2), Vector2i(1, 2)]
const SEDIMENT: Array[Vector2i] = [Vector2i(2, 2)]

# Bare stone is the locked Pale Reaches direction (docs/RING1_TILES.md): plain
# stone dominant with only rare mottled/pebble accents — STONE_FIELD (default).
# STONE_ONLY is pure plain stone. COURTYARD is the busier opt-in mix that also
# scatters flagstone / path / sediment.
enum Layout { STONE_ONLY, STONE_FIELD, COURTYARD }

# 10x6 @ 48px = 480x288, covering the 480x270 play area.
@export var grid_size: Vector2i = Vector2i(10, 6)
@export var layout: Layout = Layout.STONE_FIELD
# Fixed seed keeps the field stable across runs; set 0 to randomize per run.
@export var field_seed: int = 1337

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if field_seed != 0:
		_rng.seed = field_seed
	else:
		_rng.randomize()
	var source_id := tile_set.get_source_id(0)
	for y in grid_size.y:
		for x in grid_size.x:
			set_cell(Vector2i(x, y), source_id, _pick())


# Weighted material pick. Plain stone dominates; accents stay sparse so the field
# reads as cohesive bare stone rather than a patchwork.
func _pick() -> Vector2i:
	var roll := _rng.randf()
	match layout:
		Layout.STONE_ONLY:
			return _one(PLAIN)
		Layout.COURTYARD:
			if roll < 0.55:
				return _one(PLAIN)
			elif roll < 0.72:
				return _one(MOTTLED + PEBBLE)
			elif roll < 0.90:
				return _one(FLAGSTONE)
			elif roll < 0.96:
				return _one(PATH)
			return _one(SEDIMENT)
		_:  # STONE_FIELD — bare stone with rare accents
			if roll < 0.90:
				return _one(PLAIN)
			elif roll < 0.96:
				return _one(MOTTLED)
			return _one(PEBBLE)


func _one(pool: Array[Vector2i]) -> Vector2i:
	return pool[_rng.randi() % pool.size()]
