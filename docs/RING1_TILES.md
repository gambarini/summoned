# Ring 1 — The Pale Reaches: Tilesets

Implementation reference for Ring 1 ground tiles. Design intent lives in the GDD
(`../../idea/Summoned_GDD.html`, Ring 1 / Visual Direction). This file is the
import + wiring reference only.

## Source

Generated with the PixelLab MCP server (reachable from this environment — no
local `fetch_tiles.sh` needed). Two tools, chosen by job:

- **Seamless ground** → `create_topdown_tileset` (corner-based Wang). This is the
  only PixelLab tool that produces *seamless repeating* terrain + peering metadata.
- **Props / set-dressing** → `create_map_object` (transparent-background objects).

`create_tiles_pro` makes **discrete bounded tiles**, not corner-blended Wang
terrain. An early attempt used it for *seamless* ground and was rejected (multi-
material calls baked hard seams inside tiles; segmentation single-material
produced empty tiles). The **v3 ground (current)** instead embraces the discrete
model — a curated, de-rimmed `create_tiles_pro` set scattered by weight — see
*Ground (v3)* below. Props are kept on an isometric ("high top-down") camera to
match the GDD concept art; the warrior reads slightly flatter (accepted).

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

### Ground  (`ground_tiles.png`)  — v3, current

Discrete chunky 48px stone tiles from `create_tiles_pro`, the reworked Ring 1
ground (replaces the v2 Wang set below for the ground; `main.tscn`'s `GroundLayer`
now points at `ground_tiles.tres`).

- PixelLab tiles_pro id: `fbb0aadd-da35-4b68-a890-419b3b036cb7`
  (48×48, `square_topdown`, **`top-down` view (0 depth)**, outline mode, seed 0).
  Reworked from the user's first asset `2c0af574-…` (high top-down + outline),
  which baked a dark ledge band on every tile.
- **The "transparent line" fix.** tiles_pro shades each tile as a discrete *lit
  object*, baking a dark outline/ledge band on its edges; tiled, those bands read
  as dark grout/"transparent" lines between cells (the original `2c0af574` asset
  had a thick ledge from its 15%-depth high-top-down view; even flat `top-down`
  outline mode leaves a ~1–2px rim). Two fixes combined:
  1. Regenerate at **`top-down`** view (no depth ledge).
  2. **De-rim** each tile in `scripts/cleanup_ground_tiles.py` — overwrite a dark
     edge row/col with the pixels just inside it. Verified: residual edge-vs-
     interior luminance Δ within ±17 on all keepers (was −180+).
  A `segmentation`-mode variant (`4f7a1977-…`) was also generated and rejected:
  cleaner vertical seams but a thick checkered ledge band remained on its dirt
  tiles that de-rim can't remove.
- **Curation.** 16 raw tiles → 11 keepers. Tiles 3,4,5,6,7 carry a multi-pixel
  baked border (residual Δ −41…−175) de-rim can't safely strip, and are dropped.
  Raw set is read-only in `docs/gen/ring1_ground_tiles_pro/`.
- **Atlas** `ground_tiles.png` is 4×3 @48px (192×144, 11 tiles + 1 empty cell),
  grouped by material (see `cleanup_ground_tiles.py` `LAYOUT` and
  `ground_layer.gd`): plain stone `(0,0)(2,0)`, mottled `(3,0)`, pebble
  `(0,1)(1,1)(2,1)`, flagstone/cobble `(1,0)(3,1)`, dirt path `(0,2)(1,2)`,
  sediment `(2,2)`.
- **Painting.** `ground_layer.gd` scatters tiles by weight (`Layout` enum, fixed
  `field_seed` for a stable field). Default **`STONE_FIELD`** = bare-stone read
  (≈90% plain, rare mottled/pebble), per the locked "stone-only" direction —
  flagstone/path/sediment tiles ship in the atlas but are only painted by the
  opt-in `COURTYARD` layout. Verified in a live 480×270 render: seamless bare
  stone, no dark/transparent seam lines, palette-cohesive with the props.

### Ground → Path  (`ground_path.png`)  — v2, SUPERSEDED by v3 above (kept for cliff/reference)
- PixelLab tileset id: `e829f3a7-7f22-4ef3-8264-38a4e72ad6c2`
- 16 tiles, 32×32 px, high top-down, selective outline / medium shading / **low detail**
- Corner-based (Wang) autotile: **lower = bare cool grey-blue stone**, **upper = faint worn tan path**
- Verified seamless (3×3 self-tile of the all-stone tile shows no seams).
- Base tile IDs (for chaining future connected sets in PixelLab):
  - stone (lower): `1054154d-a21a-4d77-af07-503032fcb646`
  - path (upper): `8898cf71-0ef4-4b20-a8b1-a6155095f1c9`
- `ground_path.metadata.json` holds the per-tile corner values for terrain/peering setup.
- Replaced the v1 set (`3769b303-…`, "not ideal"). The old `ground_flora.png`
  (`13fd8f44-…`) is **no longer wired** — flora is now props (below). It chained off a
  *different* stone base (`61b9b31b-…`), so it must not be re-added to `ground.tres`
  (two distinct stone images under one `stone` terrain → Godot's corner matcher picks
  between them and the rework silently regresses).

### Props  (`props/*.png`)  — `create_map_object`, transparent bg, high top-down
Discrete set-dressing placed by hand (Y-sorted), not autotiled. Matches the GDD
concept art's Pale Reaches (ruins, standing stones, bunting, pale flora).

| File | px | PixelLab object id |
|------|----|--------------------|
| `ruin.png` (domed ruin, hero) | 160×160 | `7ada9220-7202-4f8e-9a49-aa09e2835697` |
| `archway.png` (broken arch) | 112×112 | `bbf89273-cec9-488f-8de3-4adba6211940` |
| `bunting.png` (faded pennants) | 112×80 | `6c93567c-250d-4ef3-bc58-37cbac59395c` |
| `wall.png` (ruined wall) | 96×64 | `f06540c7-8227-4d3c-8c86-2df16046d6c7` |
| `monolith.png` (standing stone) | 48×64 | `eaae4872-7fff-44b8-bde2-695380acf11e` |
| `rubble.png` (broken blocks) | 64×48 | `aa12e9bd-5122-4bd8-a18a-65470ec37985` |
| `flora.png` (pale clump) | 48×48 | `f622478e-1be5-49dc-8a6b-f3cfd756bfe7` |
| `shrub.png` (dead shrub) | 56×72 | `0878a945-a58d-415c-8948-55b6703e69b6` |

`flora.png` was color-clamped after generation (it generated pink) toward the cool
palette. Map objects auto-delete from PixelLab after 8h — the PNGs here are the
source of truth. Wired in `main.tscn` as `Sprite2D`s (`centered=false`,
`offset=(-w/2,-h)` so each sorts by its base).

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

**`ground_tiles.tres`** (v3, current ground) is built by
`scripts/build_ground_tileset.gd` from the cleaned `ground_tiles.png` — a single
48px atlas source, one tile per non-empty cell, **no terrain set** (discrete
scatter). Regenerate after re-fetching:

```
python3 scripts/cleanup_ground_tiles.py            # de-rim + curate + pack PNG
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
    --script res://scripts/build_ground_tileset.gd
```

`scripts/build_ring1_tilesets.gd` still builds the older Wang `ground.tres` +
`cliff.tres` from the fetched PNGs + metadata (cliff path unchanged). Re-run
headless after re-fetching those:

```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
    --script res://scripts/build_ring1_tilesets.gd
```

- **`ground.tres`** — v2, **superseded by `ground_tiles.tres` and no longer wired
  into `main.tscn`** (kept for reference). The v2 `ground_path.png` as a **single**
  atlas source in one corner-match terrain set with two terrains: `stone` (0) and `path` (1)
  (`lower→stone / upper→path`). Single stone image — no competing all-stone tiles.
  Corner mapping is `NW→top-left, NE→top-right, SE→bottom-right, SW→bottom-left`.
  The build script reloads the result and asserts terrain set count = 1, terrains = 2,
  mode = MATCH_CORNERS, and spot-checks the all-stone / all-path tiles' peering bits.
- **`cliff.tres`** — atlas source over the full 4×8 cell grid (32 non-empty tiles) plus
  one empty physics layer (scaffold). **Terrain matching and per-tile collision/Y-sort
  are NOT wired** — the upstream cliff metadata's tile placement is unreliable
  (`bounding_box` values duplicate, `original_position` rows exceed the grid) and it is a
  3-terrain transition set, not a clean tileset15, so fabricating peering bits from it
  would be wrong. Finish cliff terrain + cliff-face collision/Y-sort in the editor.

## Status / next

- [x] **v3 ground — chunky 48px `create_tiles_pro` set** (`fbb0aadd-…`), de-rimmed
  + curated to 11 tiles → `ground_tiles.png` / `ground_tiles.tres`, scattered by
  `ground_layer.gd` (default `STONE_FIELD` bare-stone). Fixed the baked dark/
  "transparent" seam line (top-down regen + de-rim). `main.tscn` repointed.
  **Confirmed in a live 480×270 render:** seamless bare stone, no seam lines.
  Supersedes the v2 Wang ground for the ground layer.
- [x] **Reworked ground** (v2 `e829f3a7-…`, stone→path, muted/low-detail). Verified
  seamless via 3×3 self-tile. Replaced v1 (`3769b303-…`). *(now superseded by v3.)*
- [x] **Props** generated via `create_map_object` (ruin, archway, bunting, wall,
  monolith, rubble, flora, shrub) → `props/`. `flora.png` color-clamped.
- [x] Rebuilt `ground.tres` (single-stone-source stone/path corner-match set) —
  `build_ring1_tilesets.gd` BUILD OK, verify passed (sets=1, terrains=2, peering OK).
- [x] `ground_layer.gd` paints **stone only** (`layout = PLAIN_STONE`). Flora dropped.
- [x] Props wired into `main.tscn` as Y-sorted `Sprite2D`s.
- [x] **Confirmed in a live render** (windowed Godot, captured frame): seamless
  stone, all 8 props correct, cohesive palette, sane occlusion.
- [ ] **No path — stone-only by decision.** The atlas still holds the v2 path tiles
  but they're not painted. `create_topdown_tileset` **cannot** produce the soft,
  borderless, same-level worn trail the GDD wants — three attempts all drew a hard
  bordered edge between terrains (selective-outline → white rim; `transition_size`
  0.5 → raised ledge + drop-shadow; 0.0 + lineless + flat → stone-brick curb with a
  dark outline). The tool is for *distinct* terrains (water↔grass), not subtle
  same-ground trails. **Do not re-run `create_topdown_tileset` for the path.** If a
  path is wanted later, make it **soft `create_map_object` decals** (transparent
  dust-trail segments) placed/scattered over the stone, like the other props.
- [ ] **Cliff unchanged** — `cliff.tres` is still the old v1 scaffold (`30a69993-…`);
  terrain matching + cliff-face collision/Y-sort still unwired (metadata unreliable).
- [ ] Optional: a few stone variation tiles to break the faint single-tile repeat.
