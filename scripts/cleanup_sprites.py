#!/usr/bin/env python3
"""
Warrior sprite sheet cleanup pipeline.
Input:  docs/gen/warrior_*_v1.png  (raw AI-generated, labeled, colored background)
Output: assets/sprites/warrior_*_v1.png  (32x32/frame, transparent bg, 8-color palette)

Usage:
  python3 scripts/cleanup_sprites.py          # process all sheets
  python3 scripts/cleanup_sprites.py --preview # save grid-overlay previews to inspect margins
"""

import os
import sys
import math
from collections import deque
from PIL import Image, ImageDraw

# --- 8-color palette ---------------------------------------------------------

PALETTE = [
    (0x0D, 0x0A, 0x1E),  # Void
    (0x2A, 0x14, 0x48),  # Body dark
    (0x7B, 0x4E, 0xA0),  # Cold glow
    (0xC0, 0xA0, 0xF0),  # Lavender highlight
    (0xC4, 0x54, 0x7A),  # Warm bleed
    (0xD4, 0x80, 0x3A),  # Amber bleed
    (0xF0, 0xE8, 0xD8),  # Hollow center
    (0xA0, 0x80, 0xE0),  # Notation particles
]

# --- Per-sheet configuration --------------------------------------------------
# mt = top margin (label row), ml = left margin (label column), both in pixels.
# Adjust and re-run if cells are mis-cropped (use --preview to check).

SHEETS = {
    "warrior_idle_5x4_v1":      {"rows": 5, "cols": 4, "mt": 80, "ml": 60, "out": "warrior_idle_v1"},
    "warrior_move_5x2_v1":      {"rows": 5, "cols": 2, "mt": 80, "ml": 60, "out": "warrior_move_v1"},
    "warrior_attack_5x6_v1":    {"rows": 5, "cols": 6, "mt": 70, "ml": 50, "out": "warrior_attack_v1"},
    "warrior_hurt_1x2_v1":      {"rows": 1, "cols": 2, "mt": 0,  "ml": 0,  "out": "warrior_hurt_v1"},
    "warrior_dying_1x6_v1":     {"rows": 1, "cols": 6, "mt": 60, "ml": 0,  "out": "warrior_dying_v1"},
    "warrior_summoning_1x6_v1": {"rows": 1, "cols": 6, "mt": 50, "ml": 0,  "out": "warrior_summoning_v1"},
}

TARGET = 32   # output frame size in pixels
BG_DIST_THRESHOLD = 8    # max step between adjacent background pixels (rolling flood-fill)
                         # dying bg max step = 4.7; warrior edge transitions start at ~20+
PALETTE_DIST_THRESHOLD = 110  # max distance to nearest palette color before → transparent

# --- Helpers -----------------------------------------------------------------

def color_dist(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))

def sample_bg(cell: Image.Image) -> tuple:
    """Estimate background color by averaging corner + mid-edge samples."""
    w, h = cell.size
    px = cell.convert("RGB").load()
    samples = [
        px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1],
        px[w // 2, 0], px[0, h // 2], px[w - 1, h // 2], px[w // 2, h - 1],
    ]
    return tuple(int(sum(s[i] for s in samples) / len(samples)) for i in range(3))

def remove_bg(cell: Image.Image, bg_threshold: int = BG_DIST_THRESHOLD) -> Image.Image:
    """Remove background using rolling flood-fill from corners.
    Each pixel is compared to its immediate predecessor (not the corner seed), so
    the fill follows smooth gradients while stopping at sharp sprite edges.
    bg_threshold is the max color step between adjacent background pixels."""
    rgba = cell.convert("RGBA")
    px = rgba.load()
    w, h = rgba.size
    visited = [[False] * w for _ in range(h)]
    q = deque()

    for sx, sy in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        if not visited[sy][sx]:
            r, g, b, _ = px[sx, sy]
            visited[sy][sx] = True
            q.append((sx, sy, (r, g, b)))

    while q:
        x, y, ref = q.popleft()
        px[x, y] = (0, 0, 0, 0)
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not visited[ny][nx]:
                r, g, b, _ = px[nx, ny]
                if color_dist((r, g, b), ref) <= bg_threshold:
                    visited[ny][nx] = True
                    q.append((nx, ny, (r, g, b)))

    return rgba

def quantize(frame: Image.Image) -> Image.Image:
    """Map each non-transparent pixel to nearest palette color, or transparent."""
    result = frame.convert("RGBA").copy()
    pixels = result.load()
    w, h = result.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = pixels[x, y]
            if a < 10:
                pixels[x, y] = (0, 0, 0, 0)
                continue
            best_dist = float("inf")
            best = None
            for p in PALETTE:
                d = color_dist((r, g, b), p)
                if d < best_dist:
                    best_dist = d
                    best = p
            if best_dist > PALETTE_DIST_THRESHOLD:
                pixels[x, y] = (0, 0, 0, 0)
            else:
                pixels[x, y] = (best[0], best[1], best[2], 255)
    return result

def clean_cell(cell: Image.Image) -> Image.Image:
    """Full cleanup pipeline for one frame cell: bg remove → crop → pad → resize → quantize."""
    cleaned = remove_bg(cell)

    # Tight bounding box of non-transparent pixels
    bbox = cleaned.getbbox()
    if bbox is None:
        return Image.new("RGBA", (TARGET, TARGET), (0, 0, 0, 0))

    cropped = cleaned.crop(bbox)
    cw, ch = cropped.size

    # Pad to square around content center
    size = max(cw, ch)
    square = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    square.paste(cropped, ((size - cw) // 2, (size - ch) // 2), cropped)

    resized = square.resize((TARGET, TARGET), Image.LANCZOS)
    return quantize(resized)

# --- Main processing ---------------------------------------------------------

def process_sheet(in_path, out_path, rows, cols, mt, ml):
    print(f"  {os.path.basename(in_path)}", end="  ", flush=True)
    img = Image.open(in_path).convert("RGBA")
    iw, ih = img.size

    content = img.crop((ml, mt, iw, ih))
    cw, ch = content.size
    fw = cw // cols
    fh = ch // rows

    out = Image.new("RGBA", (cols * TARGET, rows * TARGET), (0, 0, 0, 0))

    for r in range(rows):
        for c in range(cols):
            cell = content.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh))
            frame = clean_cell(cell)
            out.paste(frame, (c * TARGET, r * TARGET), frame)
        print(".", end="", flush=True)

    out.save(out_path)
    ow, oh = out.size
    print(f"  → {os.path.basename(out_path)} ({ow}×{oh})")

def save_preview(in_path, preview_path, rows, cols, mt, ml):
    """Save the cropped content area with grid lines drawn — use to verify margins."""
    img = Image.open(in_path).convert("RGBA")
    iw, ih = img.size
    content = img.crop((ml, mt, iw, ih))
    cw, ch = content.size
    fw = cw // cols
    fh = ch // rows

    preview = content.copy().convert("RGB")
    draw = ImageDraw.Draw(preview)
    for r in range(rows + 1):
        draw.line([(0, r * fh), (cw, r * fh)], fill=(255, 0, 0), width=2)
    for c in range(cols + 1):
        draw.line([(c * fw, 0), (c * fw, ch)], fill=(255, 0, 0), width=2)

    preview.save(preview_path)
    print(f"  Preview → {os.path.basename(preview_path)}")

# --- Entry point -------------------------------------------------------------

if __name__ == "__main__":
    preview_mode = "--preview" in sys.argv

    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.dirname(script_dir)
    gen_dir = os.path.join(project_dir, "docs", "gen")
    sprites_dir = os.path.join(project_dir, "assets", "sprites")
    preview_dir = os.path.join(project_dir, "docs", "gen", "previews")

    if preview_mode:
        os.makedirs(preview_dir, exist_ok=True)
        print("Preview mode — saving grid overlays to docs/gen/previews/")
    else:
        print("Processing sprite sheets...")

    for name, cfg in SHEETS.items():
        in_path = os.path.join(gen_dir, f"{name}.png")
        if not os.path.exists(in_path):
            print(f"  SKIP (not found): {name}.png")
            continue
        if preview_mode:
            out_path = os.path.join(preview_dir, f"{name}_preview.png")
            save_preview(in_path, out_path, cfg["rows"], cfg["cols"], cfg["mt"], cfg["ml"])
        else:
            out_path = os.path.join(sprites_dir, f"{cfg['out']}.png")
            process_sheet(in_path, out_path, cfg["rows"], cfg["cols"], cfg["mt"], cfg["ml"])

    print("Done.")
