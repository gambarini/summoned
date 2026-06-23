#!/usr/bin/env python3
"""Tiling pixel-art GROUND texture for Ring 1 (The Pale Reaches).

Authored at measured ground values (the IsoRig grey ramp around #7c8591), the same
proven way as stone_pale.png — NOT a neutral multiplier — so the 16-colour post
snap preserves the values. Organic dirt: soil/grit + pebble clusters + worn streaks,
NOT blocky masonry.

Design notes (informed by the concept-vs-current gap):
- The plateau tints this texture WHITE and path/cliff use `_tint_for(t, COL_GROUND)`,
  so the AUTHORED MEAN must stay ≈ COL_GROUND (#7c8591). We widen the value
  EXCURSIONS around that mean, not the mean itself.
- The plateau is flat (normal up everywhere) → cel light() is constant across it, so
  albedo is the ONLY ground variation and must survive the 16-colour snap. The mottle
  is therefore pushed to span 3-4 distinct ramp entries instead of collapsing onto 1-2.
- Bold variation lives on MID frequencies (texture grain), NOT the freq-1 term: at
  GROUND_SCALE 0.4 the 64px tile wraps every 2.5 world units, so a strong freq-1 (full
  tile period) feature would read as an obvious repeating grid. The broad, non-repeating
  earth-patch variation is the scene's worn-patch meshes' job, not the tile's.

Tiles at 64px (sin octaves use integer frequencies so they wrap). No AA, 1px pixels.
"""
import math
import os
import random
from PIL import Image

SIZE = 64
random.seed(11)

# Ground value ramp: deep scuff -> base soil (#7c8591, the authored mean) -> pale worn.
# Centred on BASE so the zero-mean sin mottle keeps the texture mean at COL_GROUND.
# Wider than before on BOTH ends so excursions land on several distinct palette entries.
RAMP = [
    (0x48, 0x54, 0x62),  # 0 deep scuff / pebble shadow
    (0x4c, 0x5a, 0x6d),  # 1
    (0x56, 0x63, 0x75),  # 2
    (0x5a, 0x69, 0x7d),  # 3
    (0x66, 0x73, 0x83),  # 4
    (0x6e, 0x7a, 0x89),  # 5
    (0x7c, 0x85, 0x91),  # 6 base (COL_GROUND) — the authored mean
    (0x8b, 0x95, 0xa0),  # 7
    (0x98, 0xa0, 0xa8),  # 8 pale (COL_PATH)
    (0xa8, 0xb1, 0xba),  # 9 brightest worn fleck
]
BASE = 6


def snap(v):
    i = max(0, min(len(RAMP) - 1, int(round(v))))
    return RAMP[i]


def wrap(x, y, terms, ph=0.0):
    n = 0.0
    for a, b, p in terms:
        n += math.sin(2 * math.pi * (a * x + b * y) / SIZE + p + ph)
    return n / max(1, len(terms))


# COARSE stays freq-1 (full-tile period) and LOW amplitude — it would grid if loud.
COARSE = [(1, 0, 0.4), (0, 1, 2.0)]
# MOTTLE carries the real value range, on mid frequencies (2-4) that read as soil grain
# rather than a repeating block. This is what gives the ground 3-4 palette steps.
MOTTLE = [(2, 1, 0.0), (1, 2, 1.1), (2, 2, 2.3), (3, 1, 0.5), (1, 3, 1.7), (3, 2, 0.9)]
# FINE breaks the mottle edges so steps don't read as smooth contour bands.
FINE = [(3, 4, 0.0), (4, 3, 2.1), (4, 4, 1.3)]

img = Image.new("RGB", (SIZE, SIZE))
px = img.load()

# Pebble clusters: a few seeded centres that drop a tight knot of dark grit, so debris
# reads as scattered stones (concept) instead of uniform noise.
clusters = [(random.randrange(SIZE), random.randrange(SIZE)) for _ in range(7)]

for y in range(SIZE):
    for x in range(SIZE):
        idx = float(BASE)
        idx += wrap(x, y, COARSE) * 0.55          # broad, kept quiet (anti-grid)
        idx += wrap(x, y, MOTTLE, 0.5) * 1.7       # the load-bearing value range
        idx += wrap(x, y, FINE, 0.2) * 0.5         # grain
        # Clustered dark pebbles (toroidal distance so the tile wraps cleanly).
        for cx, cy in clusters:
            dx = min(abs(x - cx), SIZE - abs(x - cx))
            dy = min(abs(y - cy), SIZE - abs(y - cy))
            if dx * dx + dy * dy < 6 and random.random() < 0.7:
                idx -= random.choice([2.0, 3.0])
        r = random.random()
        if r < 0.06:
            idx -= random.choice([1.0, 2.0])       # loose dark grit
        elif r > 0.95:
            idx += random.choice([1.0, 2.0])       # pale worn fleck
        px[x, y] = snap(idx)

os.makedirs("assets/textures", exist_ok=True)
out = "assets/textures/ground_tile.png"
img.save(out)

# Report the authored mean so a drift away from COL_GROUND (#7c8591) is caught early.
data = list(img.getdata())
mr = sum(c[0] for c in data) / len(data)
mg = sum(c[1] for c in data) / len(data)
mb = sum(c[2] for c in data) / len(data)
print(f"wrote {out} ({SIZE}x{SIZE}, {len(set(data))} colours)")
print(f"  authored mean = #{int(mr):02x}{int(mg):02x}{int(mb):02x}  (target COL_GROUND #7c8591)")
