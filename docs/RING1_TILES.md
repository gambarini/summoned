# Ring 1 — The Pale Reaches: Tilesets

Implementation reference for Ring 1 ground tiles. Design intent lives in the GDD
(`../../idea/Summoned_GDD.html`, Ring 1 / Visual Direction). This file is the
import + wiring reference only.

## Source

Tiles generated with PixelLab (top-down Wang / corner-based autotiling).
The Cowork sandbox can't reach `api.pixellab.ai`, so assets are fetched locally.

```
cd assets/tiles/ring1 && bash fetch_tiles.sh
```

## Palette (locked — The Pale Reaches)

| Hex | Role |
|-----|------|
| `#B8C8D8` | ground mist |
| `#8898A8` | stone & shadow |
| `#5A6472` | deep ground |
| `#D4DCE8` | pale flora |
| `#9090A8` | fog & distance |

Cool, muted, low-saturation. Ruins/architecture use the same palette at slightly
higher saturation than natural terrain (built when the world had more warmth).

## Tilesets

### Ground → Path  (`ground_path.png`)
- PixelLab tileset id: `3769b303-59b4-4f70-945d-bfb58ea8a74c`
- 16 tiles, 32×32 px, high top-down, selective outline / medium shading / medium detail
- Corner-based (Wang) autotile: **lower = pale grey-blue stone**, **upper = faint tan path**
- Base tile IDs (for chaining future connected sets in PixelLab):
  - ground (lower): `61b9b31b-62ed-481d-ba6b-9d044f2a604c`  ← chain flora off this
  - path (upper): `581d9b25-7696-40f2-aaf8-7c10b520486b`
- `ground_path.metadata.json` holds the per-tile corner values for terrain/peering setup.

### Ground → Flora  (`ground_flora.png`)
- PixelLab tileset id: `13fd8f44-82bd-4952-a431-d2ab0cabc728`
- 16 tiles, 32×32 px, high top-down, selective outline / medium shading / medium detail
- **Chained off the same ground base** (`61b9b31b-…`) as Ground→Path, so the stone
  edges are identical — the two sets share a ground terrain and tile together cleanly.
- Corner-based (Wang) autotile: **lower = pale grey-blue stone**, **upper = pale translucent flora cluster** (`#D4DCE8`)
- Base tile IDs:
  - ground (lower): `61b9b31b-62ed-481d-ba6b-9d044f2a604c`
  - flora (upper): `9336976c-25ef-4e20-8ecc-950a4b0ee857`
- In one Godot Terrain Set, make "stone" the shared base terrain, then add "path" and
  "flora" as two more terrains painting over it — both share the same ground edge.

### Plateau / Cliff edges  (`cliff.png`)
- PixelLab tileset id: `30a69993-5a78-49ec-952f-3ffc3ae35a92`
- 25 tiles, 32×32 px, high top-down, full-height transition (`transition_size = 1.0`)
- **Plateau top reuses the ground base** (`61b9b31b-…` as upper), so plateau surfaces
  match the stone of the other sets; lower = deep shadow ground at the cliff base.
- Base tile IDs:
  - shadow base (lower): `1c189f28-2d71-4247-89a7-e56a4b417949`
  - plateau top (upper): `61b9b31b-62ed-481d-ba6b-9d044f2a604c`
- This is an **elevation** set (full-tile cliff face), so keep it on its own terrain /
  layer for height, separate from the flat stone/path/flora terrain matching. Add
  collision/Y-sort on the cliff face tiles so the warrior reads as above/below the edge.

## Godot import settings

- Texture filter: **Nearest** (project standard — no bilinear/bicubic, no anti-aliasing).
  Inherited from `project.godot` `default_texture_filter=0`; no per-tile override needed.
- Create a `TileSet` resource, add the PNG as an atlas source, tile size **32×32**.
- Use a **Terrain Set** with **corner-based** matching (mode: Corners) to match the
  Wang layout. Map each of the 16 tiles to its corner signature using
  `ground_path.metadata.json` (lower=ground, upper=path at each corner).

## Built TileSet resources

`scripts/build_ring1_tilesets.gd` generates the `.tres` from the fetched PNGs +
metadata. Re-run headless after re-fetching:

```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
    --script res://scripts/build_ring1_tilesets.gd
```

- **`ground.tres`** — both ground PNGs as two atlas sources in **one corner-match
  terrain set** with three terrains: `stone` (0, shared base), `path` (1), `flora` (2).
  Path tiles map `lower→stone / upper→path`; flora tiles map `lower→stone / upper→flora`,
  so the two sets share the stone edge and tile together. Corner mapping is
  `NW→top-left, NE→top-right, SE→bottom-right, SW→bottom-left`. The build script
  reloads the result and asserts the terrain set/count/mode and spot-checks the
  all-stone / all-path tiles' peering bits.
- **`cliff.tres`** — atlas source over the full 4×8 cell grid (32 non-empty tiles) plus
  one empty physics layer (scaffold). **Terrain matching and per-tile collision/Y-sort
  are NOT wired** — the upstream cliff metadata's tile placement is unreliable
  (`bounding_box` values duplicate, `original_position` rows exceed the grid) and it is a
  3-terrain transition set, not a clean tileset15, so fabricating peering bits from it
  would be wrong. Finish cliff terrain + cliff-face collision/Y-sort in the editor.

## Status / next

- [x] Ground → Path (muted v2) generated. First attempt `281d78b1-…` discarded (too saturated).
- [x] Ground → Flora generated, chained off ground base `61b9b31b-…` (pale translucent clusters, `#D4DCE8`).
- [x] Plateau / cliff edges generated (full-height transition, plateau top reuses ground base).
- [x] Fetched tiles + built `ground.tres` (stone/path/flora corner-match terrain set, verified).
- [x] Built `cliff.tres` atlas + physics-layer scaffold.
- [x] Playtest wiring: `scenes/tile_test.tscn` (standalone) and `main.tscn` paint `ground.tres`
  via `scripts/ground_layer.gd` (runtime `set_cells_terrain_connect`, demo path cross + flora
  patch). Verified headless: 135/135 cells autotile, no missing-tile errors.
- [ ] Wire cliff terrain matching + cliff-face collision / Y-sort in the editor (metadata unusable).
