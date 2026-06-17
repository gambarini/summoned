#!/usr/bin/env python3
"""
Ring 1 ground tile cleanup pipeline (PixelLab create_tiles_pro).

Source: PixelLab tiles_pro asset fbb0aadd-da35-4b68-a890-419b3b036cb7
        (48x48, square_topdown, top-down view, outline mode, seed 0) — the
        regenerated "Pale Reaches" ground set. Raw 16 tiles live read-only in
        docs/gen/ring1_ground_tiles_pro/tile_0..15.png.

The fix this script performs ("the transparent line"): tiles_pro shades each
tile as a discrete lit object and bakes a dark outline/ledge band on its edges.
Tiled, those bands read as dark grout lines between cells. We DE-RIM each tile —
overwrite an edge row/col with the pixels just inside it whenever the edge is
markedly darker — so adjacent tiles abut with no dark seam.

Curation: tiles 3,4,5,6,7 carry a multi-pixel baked border that de-rim cannot
safely remove (measured residual edge delta -41..-175) and are dropped. The 11
keepers (residual within +/-16) are repacked into a 4x3 atlas, grouped so the
painter (ground_layer.gd) can pick by material.

No palette quantization (ground art keeps its native cool palette) and no
scaling — generation size already equals game size (48px). Nearest only.

Usage:
  python3 scripts/cleanup_ground_tiles.py
"""

import os
from PIL import Image

TILE = 48

# Keep tiles_pro tiles by ORIGINAL index, in the atlas order we want. Each entry
# is (original_index, group). Layout is 4 columns; rows fill top-to-bottom.
# Groups: "stone" (bare cohesive primary), "pale" (lighter / pebble accents),
# "path" (dirt trodden strips), "feature" (cobble / sediment landmarks).
LAYOUT = [
    (0,  "stone"),
    (9,  "stone"),
    (10, "stone"),
    (2,  "pale"),
    (1,  "pale"),
    (11, "pale"),
    (15, "pale"),
    (13, "feature"),  # rounded cobblestone
    (8,  "path"),
    (12, "path"),
    (14, "feature"),  # wavy sediment
]
COLS = 4

# De-rim tuning. A row/col is overwritten by its inner neighbour when it is more
# than THRESH luminance darker; up to PASSES pixels deep per edge.
DERIM_PASSES = 4
DERIM_THRESH = 22


def lum(p):
    return 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]


def _line_mean(px, fixed, vary_range, horizontal):
    if horizontal:  # fixed = y, vary over x
        return sum(lum(px[x, fixed]) for x in vary_range) / len(vary_range)
    return sum(lum(px[fixed, y]) for y in vary_range) / len(vary_range)


def derim(im):
    """Remove the baked dark edge band by extending interior pixels outward."""
    im = im.convert("RGBA").copy()
    px = im.load()
    w, h = im.size
    xs = range(w)
    ys = range(h)
    for _ in range(DERIM_PASSES):
        # top
        if _line_mean(px, 1, xs, True) - _line_mean(px, 0, xs, True) > DERIM_THRESH:
            for x in xs:
                px[x, 0] = px[x, 1]
        # bottom
        if _line_mean(px, h - 2, xs, True) - _line_mean(px, h - 1, xs, True) > DERIM_THRESH:
            for x in xs:
                px[x, h - 1] = px[x, h - 2]
        # left
        if _line_mean(px, 1, ys, False) - _line_mean(px, 0, ys, False) > DERIM_THRESH:
            for y in ys:
                px[0, y] = px[1, y]
        # right
        if _line_mean(px, w - 2, ys, False) - _line_mean(px, w - 1, ys, False) > DERIM_THRESH:
            for y in ys:
                px[w - 1, y] = px[w - 2, y]
    return im


def residual_edge_delta(im):
    """Lowest edge-line mean minus interior median luminance (0 == seamless)."""
    px = im.load()
    w, h = im.size
    interior = sorted(
        lum(px[x, y]) for y in range(4, h - 4) for x in range(4, w - 4)
    )
    med = interior[len(interior) // 2]
    edges = [
        _line_mean(px, 0, range(w), True),
        _line_mean(px, h - 1, range(w), True),
        _line_mean(px, 0, range(h), False),
        _line_mean(px, w - 1, range(h), False),
    ]
    return min(edges) - med


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.dirname(script_dir)
    src_dir = os.path.join(project_dir, "docs", "gen", "ring1_ground_tiles_pro")
    out_path = os.path.join(project_dir, "assets", "tiles", "ring1", "ground_tiles.png")

    rows = (len(LAYOUT) + COLS - 1) // COLS
    atlas = Image.new("RGBA", (COLS * TILE, rows * TILE), (0, 0, 0, 0))

    print("Cleaning Ring 1 ground tiles (de-rim + curate + pack)...")
    for slot, (orig, group) in enumerate(LAYOUT):
        cell = Image.open(os.path.join(src_dir, f"tile_{orig}.png"))
        clean = derim(cell)
        delta = residual_edge_delta(clean)
        c, r = slot % COLS, slot // COLS
        atlas.paste(clean, (c * TILE, r * TILE))
        flag = "" if delta > -25 else "  <-- WARN residual seam"
        print(f"  slot ({c},{r}) <- tile_{orig:<2} [{group:<7}] residualEdgeDelta={delta:6.1f}{flag}")

    atlas.save(out_path)
    print(f"Wrote {os.path.relpath(out_path, project_dir)} "
          f"({atlas.width}x{atlas.height}, {len(LAYOUT)} tiles, {COLS}x{rows} grid)")


if __name__ == "__main__":
    main()
