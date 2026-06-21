#!/usr/bin/env python3
"""Tiling pixel-art GROUND texture for Ring 1 (The Pale Reaches).

Authored at measured ground values (the IsoRig grey ramp around #7c8591), the same
proven way as stone_pale.png — NOT a neutral multiplier — so the 16-colour post
snap preserves the values. Organic soil/grit (broad low-freq mottle + fine
speckle), NOT blocky masonry. Low contrast to keep the soft concept read. Tiles at
64px (sin octaves use integer frequencies so they wrap). No AA, 1px pixels.
"""
import math
import os
import random
from PIL import Image

SIZE = 64
random.seed(11)

# Ground value ramp: dark scuff -> base soil -> pale worn (subset of the rig ramp).
RAMP = [
    (0x56, 0x63, 0x75),
    (0x5a, 0x69, 0x7d),
    (0x66, 0x73, 0x83),
    (0x6e, 0x7a, 0x89),
    (0x7c, 0x85, 0x91),  # base (COL_GROUND)
    (0x8b, 0x95, 0xa0),
    (0x98, 0xa0, 0xa8),  # pale (COL_PATH)
]
BASE = 4


def snap(v):
    i = max(0, min(len(RAMP) - 1, int(round(v))))
    return RAMP[i]


def wrap(x, y, terms, ph=0.0):
    n = 0.0
    for a, b, p in terms:
        n += math.sin(2 * math.pi * (a * x + b * y) / SIZE + p + ph)
    return n / max(1, len(terms))


COARSE = [(1, 0, 0.4), (0, 1, 2.0)]                              # broad soil patches
MOTTLE = [(1, 0, 0.0), (0, 1, 1.1), (1, 1, 2.3), (2, 1, 0.5), (1, 2, 1.7)]  # finer mottle

img = Image.new("RGB", (SIZE, SIZE))
px = img.load()

for y in range(SIZE):
    for x in range(SIZE):
        idx = float(BASE)
        idx += wrap(x, y, COARSE) * 1.2
        idx += wrap(x, y, MOTTLE, 0.5) * 0.7
        r = random.random()
        if r < 0.07:
            idx -= random.choice([1.0, 2.0])  # dark grit / pebble shadow
        elif r > 0.95:
            idx += 1.0                          # pale fleck
        px[x, y] = snap(idx)

os.makedirs("assets/textures", exist_ok=True)
out = "assets/textures/ground_tile.png"
img.save(out)
print(f"wrote {out} ({SIZE}x{SIZE}, {len(set(img.getdata()))} colours)")
