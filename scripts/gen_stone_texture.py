#!/usr/bin/env python3
"""Generate a seamless tiling pixel-art stone texture for the look-match spike.

V2 — density pass. Authored *in the IsoRig's own grey ramp* so the 16-colour post
snap is near-lossless (the texture's values land on real palette bins instead of
collapsing). Layered weathering breaks the tidy-brick read into weathered ruin
stone: coarse staggered blocks + per-stone base variation + a low-freq stain
field + sun-bleached / damp patches + irregular cracks. Tiles at 64px (stone 16,
half-offset 8 — both divide 64) so it wraps under triplanar. No AA, 1px pixels.
"""
import math
import os
import random
from PIL import Image

SIZE = 64
random.seed(7)

# Subset of the IsoRig grey ramp (dark recess -> bright sun-catch). Authoring in
# these exact values means the post palette-snap preserves them 1:1.
RAMP = [
    (0x3a, 0x44, 0x52),  # deep recess / crack (just below palette 485462)
    (0x48, 0x54, 0x62),  # mortar
    (0x4c, 0x5a, 0x6d),  # shadow
    (0x56, 0x63, 0x75),  # low mid
    (0x5a, 0x69, 0x7d),  # mid
    (0x66, 0x73, 0x83),  # base (concept dome)
    (0x6e, 0x7a, 0x89),  # high mid
    (0x7c, 0x85, 0x91),  # highlight
    (0x8b, 0x95, 0xa0),  # bright
    (0xa8, 0xb1, 0xba),  # sun-catch
]
BASE = 5  # index of the concept dome value

STONE_W = 16
STONE_H = 16
MORTAR = 1


def snap(v):
    i = max(0, min(len(RAMP) - 1, int(round(v))))
    return RAMP[i]


def wrap_noise(x, y, fx_terms, seed=0.0):
    """Perfectly-wrapping low-freq value noise in ~[-1, 1] for a given octave set."""
    n = 0.0
    for (a, b, ph) in fx_terms:
        n += math.sin(2 * math.pi * (a * x + b * y) / SIZE + ph + seed)
    return n / max(1, len(fx_terms))


# Low-frequency stain field (water streaks / damp) — independent of the grid.
STAIN = [(1, 0, 0.0), (0, 1, 1.3), (1, 1, 2.1), (2, 1, 0.7)]
# Even lower freq large bleach/damp patches.
PATCH = [(1, 0, 0.4), (0, 1, 2.7)]

img = Image.new("RGB", (SIZE, SIZE))
px = img.load()

stone_base = {}   # per-stone base value offset
stone_kind = {}   # 0 normal, +1 sun-bleached, -1 damp/moss


def stone_id(x, y):
    row = (y // STONE_H) % (SIZE // STONE_H)
    stagger = (STONE_W // 2) if (row % 2 == 1) else 0
    col = ((x + stagger) // STONE_W) % (SIZE // STONE_W)
    return row, col, stagger


# Sparse irregular cracks: random walks across the tile (wrapped).
crack = set()
for _ in range(3):
    cx = random.randint(0, SIZE - 1)
    cy = random.randint(0, SIZE - 1)
    for _ in range(random.randint(14, 26)):
        crack.add((cx % SIZE, cy % SIZE))
        if random.random() < 0.5:
            cx += random.choice([-1, 1])
        else:
            cy += 1  # cracks tend to run downward

for y in range(SIZE):
    for x in range(SIZE):
        row, col, stagger = stone_id(x, y)
        key = (row, col)
        if key not in stone_base:
            stone_base[key] = random.uniform(-1.3, 1.3)
            r = random.random()
            stone_kind[key] = 1 if r < 0.12 else (-1 if r > 0.88 else 0)

        local_x = (x + stagger) % STONE_W
        local_y = y % STONE_H

        idx = float(BASE) + stone_base[key]
        idx += stone_kind[key] * 1.6                 # sun-bleached up / damp down
        idx += wrap_noise(x, y, STAIN) * 0.7         # streaky stain
        idx += wrap_noise(x, y, PATCH, 0.5) * 0.9    # broad damp/bleach patches

        is_mortar = (local_x < MORTAR) or (local_y < MORTAR)
        if is_mortar:
            idx -= 4.0                                # recessed mortar lines
        else:
            if local_y < MORTAR + 2:
                idx += 1.6                            # top edge catches light
            elif local_y > STONE_H - 3:
                idx -= 1.4                            # bottom edge falls to shadow
            idx -= local_x * 0.04                     # faint left-light gradient
            if random.random() < 0.10:
                idx -= random.choice([1.0, 2.0, 3.0]) # weather speckle

        if (x, y) in crack:
            idx -= 3.0                                # dark hairline crack

        px[x, y] = snap(idx)

os.makedirs("assets/textures", exist_ok=True)
out = "assets/textures/stone_pale.png"
img.save(out)
print(f"wrote {out} ({SIZE}x{SIZE}, {len(set(img.getdata()))} colours)")
