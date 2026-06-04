#!/usr/bin/env python3
"""
Tailored extractor for warrior_idle_south_x4_v2.png.

Key differences from cleanup_sprites.py:
- No label margins (this sheet has none)
- Float cell boundaries handle 1774px ÷ 4 non-integer cleanly
- Shared union bounding box across all 4 frames → stable idle loop, no jitter
- No palette quantization — preserves particle/fire gradient depth

Input:  docs/gen/warrior_idle_south_x4_v2.png  (1774×887, 4 cols, 1 row)
Output: assets/sprites/warrior_idle_south_v2.png        (128×32 = 4 frames × 32×32)
        docs/gen/previews/warrior_idle_south_v2_4x.png  (4× preview strip for inspection)
"""

import math
import os
from collections import deque

from PIL import Image

COLS = 4
TARGET = 64
BG_THRESHOLD = 8  # max color step between adjacent bg pixels in flood-fill

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
IN_PATH  = os.path.join(PROJECT_DIR, "docs", "gen", "warrior_idle_south_x4_v2.png")
OUT_PATH = os.path.join(PROJECT_DIR, "assets", "sprites", "warrior_idle_south_v2.png")
PREVIEW_DIR  = os.path.join(PROJECT_DIR, "docs", "gen", "previews")
PREVIEW_PATH = os.path.join(PREVIEW_DIR, "warrior_idle_south_v2_4x.png")


def color_dist(a, b):
    return math.sqrt(sum((x - y) ** 2 for x, y in zip(a, b)))


def remove_bg(cell: Image.Image) -> Image.Image:
    """Rolling flood-fill from all four corners; stops at sprite edges."""
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
                if color_dist((r, g, b), ref) <= BG_THRESHOLD:
                    visited[ny][nx] = True
                    q.append((nx, ny, (r, g, b)))
    return rgba


def union_bbox(bboxes):
    """Return the tightest box that contains all given (x0, y0, x1, y1) bboxes."""
    x0 = min(b[0] for b in bboxes)
    y0 = min(b[1] for b in bboxes)
    x1 = max(b[2] for b in bboxes)
    y1 = max(b[3] for b in bboxes)
    return (x0, y0, x1, y1)


def main():
    img = Image.open(IN_PATH).convert("RGBA")
    iw, ih = img.size
    fw = iw / COLS  # 443.5 — use float to avoid dropping pixels

    print(f"Source: {iw}×{ih}  cell width: {fw:.1f}px  cell height: {ih}px")

    # Step 1: crop cells and remove backgrounds
    cells = []
    for c in range(COLS):
        x0 = int(c * fw)
        x1 = int((c + 1) * fw)
        cell = img.crop((x0, 0, x1, ih))
        cells.append(remove_bg(cell))
        print(f"  frame {c}: bg removed", flush=True)

    # Step 2: compute union bounding box across all frames
    bboxes = [cell.getbbox() for cell in cells]
    if any(b is None for b in bboxes):
        print("WARNING: one or more frames is entirely transparent after bg removal")
        bboxes = [b or (0, 0, 1, 1) for b in bboxes]
    ub = union_bbox(bboxes)
    uw, uh = ub[2] - ub[0], ub[3] - ub[1]
    print(f"  union bbox: {ub}  ({uw}×{uh}px)")

    # Step 3: crop all frames to the shared box, pad to square, resize to TARGET
    side = max(uw, uh)
    frames = []
    for c, cell in enumerate(cells):
        cropped = cell.crop(ub)
        square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        square.paste(cropped, ((side - uw) // 2, (side - uh) // 2), cropped)
        resized = square.resize((TARGET, TARGET), Image.LANCZOS)
        frames.append(resized)

    # Step 4: stitch into output sheet
    sheet = Image.new("RGBA", (COLS * TARGET, TARGET), (0, 0, 0, 0))
    for c, frame in enumerate(frames):
        sheet.paste(frame, (c * TARGET, 0), frame)

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    sheet.save(OUT_PATH)
    print(f"Saved: {OUT_PATH}")

    # Step 5: 4× preview strip for inspection
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    preview = Image.new("RGBA", (COLS * TARGET * 4, TARGET * 4), (0x1A, 0x16, 0x2E, 255))
    for c, frame in enumerate(frames):
        big = frame.resize((TARGET * 4, TARGET * 4), Image.NEAREST)
        preview.paste(big, (c * TARGET * 4, 0), big)
    preview.save(PREVIEW_PATH)
    print(f"Preview: {PREVIEW_PATH}")


if __name__ == "__main__":
    main()
