#!/usr/bin/env python3
"""Ground-detail SPRITES for the dusty-rock ground spike (`ground_spike.tscn`).

These are the scattered-sprite layer of the t3ssel8r / David-Holland technique:
small textured quads laid over the base tiling ground. Per the look-match finding,
only HARD-STRUCTURED detail survives the 16-colour palette snap (distinct stones,
cracks) — soft gradients collapse — so every sprite here is hard-edged, authored on
the same Pale Reaches ground ramp as `ground_tile.png`, on a TRANSPARENT background
(alpha-cut at render). Flat decals (pebbles/gravel/crack) lie on the ground; the
weed is the one upright billboard (panel D, the grass case).

Throwaway test art: procedural, deliberately honest about being a stand-in for
PixelLab-authored sprites. Tests the APPROACH (scatter + blend + orbit-stability),
not the final asset.
"""
import math
import os
import random
from PIL import Image

SIZE = 64

# Same ground ramp as gen_ground_texture.py (dark scuff -> base #7c8591 -> pale worn).
RAMP = [
    (0x48, 0x54, 0x62),  # 0 deep shadow / stone underside
    (0x4c, 0x5a, 0x6d),  # 1 dark rim
    (0x56, 0x63, 0x75),  # 2
    (0x5a, 0x69, 0x7d),  # 3 shadow side
    (0x66, 0x73, 0x83),  # 4
    (0x6e, 0x7a, 0x89),  # 5 base body
    (0x7c, 0x85, 0x91),  # 6 (COL_GROUND)
    (0x8b, 0x95, 0xa0),  # 7 lit
    (0x98, 0xa0, 0xa8),  # 8 lit top
    (0xa8, 0xb1, 0xba),  # 9 brightest fleck
]
TRANSPARENT = (0, 0, 0, 0)


def ramp(i):
    i = max(0, min(len(RAMP) - 1, int(round(i))))
    return RAMP[i] + (255,)


def blank():
    img = Image.new("RGBA", (SIZE, SIZE), TRANSPARENT)
    return img, img.load()


def save(img, name):
    os.makedirs("assets/textures", exist_ok=True)
    out = f"assets/textures/{name}.png"
    img.save(out)
    print(f"wrote {out}")


# --- detail_pebbles: a cluster of distinct hard stones (top-left lit) ----------
def gen_pebbles():
    random.seed(21)
    img, px = blank()
    # A few stones of varied size, spaced so they read as separate stones.
    stones = []
    attempts = 0
    while len(stones) < 7 and attempts < 200:
        attempts += 1
        r = random.uniform(3.5, 8.0)
        cx = random.uniform(r + 2, SIZE - r - 2)
        cy = random.uniform(r + 2, SIZE - r - 2)
        if all((cx - sx) ** 2 + (cy - sy) ** 2 > (r + sr) ** 2 * 0.55 for sx, sy, sr in stones):
            stones.append((cx, cy, r))
    for cx, cy, r in stones:
        ry = r * random.uniform(0.7, 0.95)  # slightly squashed
        for y in range(int(cy - r) - 1, int(cy + r) + 2):
            for x in range(int(cx - r) - 1, int(cx + r) + 2):
                if not (0 <= x < SIZE and 0 <= y < SIZE):
                    continue
                dx, dy = (x - cx) / r, (y - cy) / ry
                d = math.hypot(dx, dy)
                if d > 1.0:
                    continue
                # Lit toward top-left; hard dark rim at the silhouette.
                nl = (-dx - dy) / 1.42
                shade = 5.5 + nl * 2.6
                if d > 0.82:
                    shade = 1.0  # crisp dark rim so stones stay distinct
                px[x, y] = ramp(shade)
    save(img, "detail_pebbles")


# --- detail_crack: a dark branching hairline with a faint pale lip --------------
def gen_crack():
    random.seed(7)
    img, px = blank()

    def plot(x, y, i):
        if 0 <= x < SIZE and 0 <= y < SIZE:
            px[x, y] = ramp(i)

    def walk(x, y, ang, length, depth):
        for _ in range(length):
            ang += random.uniform(-0.5, 0.5)
            x += math.cos(ang)
            y += math.sin(ang)
            ix, iy = int(round(x)), int(round(y))
            plot(ix, iy, 0)  # crack core (darkest)
            if random.random() < 0.4:  # faint pale lip beside it
                plot(ix + 1, iy, 8)
            if depth > 0 and random.random() < 0.12:  # branch
                walk(x, y, ang + random.choice([-1.0, 1.0]), length // 2, depth - 1)

    walk(6, SIZE * 0.5, random.uniform(-0.4, 0.4), 64, 2)
    save(img, "detail_crack")


# --- detail_gravel: sparse scatter of tiny hard specks --------------------------
def gen_gravel():
    random.seed(33)
    img, px = blank()
    for _ in range(46):
        x, y = random.randrange(SIZE), random.randrange(SIZE)
        i = random.choice([1, 2, 2, 8, 9])  # mostly dark grit, a few pale flecks
        px[x, y] = ramp(i)
        if random.random() < 0.5:  # some 2px specks
            for ox, oy in [(1, 0), (0, 1)]:
                if 0 <= x + ox < SIZE and 0 <= y + oy < SIZE and random.random() < 0.6:
                    px[x + ox, y + oy] = ramp(i)
    save(img, "detail_gravel")


# --- detail_weed: a small dry upright tuft (the one billboard, panel D) ----------
def gen_weed():
    random.seed(13)
    img, px = blank()
    base_x, base_y = SIZE // 2, SIZE - 2
    blades = random.randint(5, 7)
    for _ in range(blades):
        x = base_x + random.uniform(-6, 6)
        y = base_y
        ang = -math.pi / 2 + random.uniform(-0.5, 0.5)
        h = random.randint(24, 42)
        col = random.choice([6, 7, 8])
        curve = random.uniform(-0.03, 0.03)
        for _ in range(h):
            ang += curve
            x += math.cos(ang)
            y += math.sin(ang)
            ix, iy = int(round(x)), int(round(y))
            if 0 <= ix < SIZE and 0 <= iy < SIZE:
                px[ix, iy] = ramp(col)
    save(img, "detail_weed")


if __name__ == "__main__":
    gen_pebbles()
    gen_crack()
    gen_gravel()
    gen_weed()
    print("done")
