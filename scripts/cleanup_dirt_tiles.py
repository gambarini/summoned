#!/usr/bin/env python3
"""
Ring 1 dirt-ground tile cleanup pipeline (PixelLab create_tiles_pro, v4).

Source: PixelLab tiles_pro asset 26ee7e27-a59a-4aff-bef5-989ac1566a77
        (48x48, square_topdown, top-down view, outline mode, seed 0) — the
        cold packed-earth "Pale Reaches" dirt set that makes Ring 1's ground
        DIRT-DOMINANT (supersedes the bare-stone v3 default). Raw tiles live
        read-only in docs/gen/ring1_dirt_tiles_pro/tile_*.png.

Same de-rim fix as cleanup_ground_tiles.py: tiles_pro bakes a dark outline band
on each tile's edges; tiled, those read as dark grout lines. We DE-RIM each tile
(overwrite an edge row/col with the pixels just inside it when the edge is
markedly darker) so adjacent tiles abut seamlessly.

Curation: drop tiles whose residual edge delta de-rim cannot bring within ~+/-20
(a multi-pixel baked border), plus any tile with directional features (a dirt set
must be non-directional to scatter as field fill). Keepers are repacked into an
atlas grouped so ground_layer.gd can pick by material:
  "dirt"   = primary packed-earth fill (dominant)
  "grit"   = grittier / pebbly dirt accents
  "feature"= cracked / dusty landmark variations (sparse)

No palette quantization, no scaling (48px == game size). Nearest only.

Usage:
  python3 scripts/cleanup_dirt_tiles.py
"""

import os
from PIL import Image

TILE = 48

# Keep tiles by ORIGINAL index, in atlas order. (original_index, group).
# 4 columns; rows fill top-to-bottom. Curated from the 16 raw tiles (self-tile
# + residual review): dropped tile_8 (directional scratch streaks), tile_9
# (diagonal scuff), tile_11/tile_12 (redundant blobby dust). Groups:
#   "dirt"    primary smooth packed earth (dominant fill)
#   "grit"    light specks / fine gravel accents
#   "pebble"  embedded stone / bedrock poking through (the stone accent)
#   "crack"   dry cracked earth features (rare)
#   "dusty"   pale powdery patch (rare)
LAYOUT = [
    (0,  "dirt"),
    (1,  "dirt"),
    (2,  "dirt"),
    (3,  "grit"),
    (15, "grit"),
    (6,  "grit"),
    (7,  "pebble"),
    (13, "pebble"),
    (4,  "crack"),
    (5,  "crack"),
    (14, "crack"),
    (10, "dusty"),
]
COLS = 4

# De-rim tuning. Unlike the stone set's single-pixel black outline, this set
# bakes a 1px black outline PLUS a multi-pixel dark drop-shadow band along the
# bottom (and sometimes other) edges. A row is "dark" if its mean luminance is
# more than DERIM_THRESH below the interior median; we scan up to DERIM_MAXDEPTH
# rows/cols inward from each edge and overwrite the whole dark band with the
# first clean line found, so adjacent tiles abut seamlessly.
DERIM_MAXDEPTH = 7
DERIM_THRESH = 20


def lum(p):
    return 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]


def _line_mean(px, fixed, vary_range, horizontal):
    if horizontal:  # fixed = y, vary over x
        return sum(lum(px[x, fixed]) for x in vary_range) / len(vary_range)
    return sum(lum(px[fixed, y]) for y in vary_range) / len(vary_range)


def _interior_median(px, w, h):
    interior = sorted(
        lum(px[x, y]) for y in range(8, h - 8) for x in range(8, w - 8)
    )
    return interior[len(interior) // 2]


def _fill_edge(px, w, h, side, med):
    """Overwrite a dark band on one edge with the first clean inner line."""
    xs, ys = range(w), range(h)
    # idx() maps a depth d (0 = outermost) to the line's fixed coordinate; the
    # corresponding _line_mean call iterates the perpendicular axis.
    if side == "top":
        idxs = list(range(DERIM_MAXDEPTH)); horiz = True; vary = xs
    elif side == "bottom":
        idxs = [h - 1 - d for d in range(DERIM_MAXDEPTH)]; horiz = True; vary = xs
    elif side == "left":
        idxs = list(range(DERIM_MAXDEPTH)); horiz = False; vary = ys
    else:  # right
        idxs = [w - 1 - d for d in range(DERIM_MAXDEPTH)]; horiz = False; vary = ys

    clean = None
    for f in idxs:
        if _line_mean(px, f, vary, horiz) >= med - DERIM_THRESH:
            clean = f
            break
    if clean is None:
        return
    for f in idxs:
        if f == clean:
            break
        if horiz:
            for x in vary:
                px[x, f] = px[x, clean]
        else:
            for y in vary:
                px[f, y] = px[clean, y]


def derim(im):
    """Remove the baked dark edge band by filling each edge's dark band with
    the first interior-bright line scanned inward from that edge."""
    im = im.convert("RGBA").copy()
    px = im.load()
    w, h = im.size
    med = _interior_median(px, w, h)
    for side in ("top", "bottom", "left", "right"):
        _fill_edge(px, w, h, side, med)
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
    src_dir = os.path.join(project_dir, "docs", "gen", "ring1_dirt_tiles_pro")
    out_path = os.path.join(project_dir, "assets", "tiles", "ring1", "dirt_tiles.png")

    if not LAYOUT:
        raise SystemExit("LAYOUT is empty — inspect docs/gen/ring1_dirt_tiles_pro/ and fill it in first.")

    rows = (len(LAYOUT) + COLS - 1) // COLS
    atlas = Image.new("RGBA", (COLS * TILE, rows * TILE), (0, 0, 0, 0))

    print("Cleaning Ring 1 dirt tiles (de-rim + curate + pack)...")
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
