"""
Composites 4 notation glyph PNGs (32×32 each) into a single 128×32 horizontal
spritesheet at assets/sprites/notation_glyphs.png.

Usage: python3 scripts/build_notation_spritesheet.py
"""

from pathlib import Path
from PIL import Image

FRAME_SIZE = 32
SOURCES = [
    "assets/sprites/notation/note_0.png",
    "assets/sprites/notation/note_1.png",
    "assets/sprites/notation/note_2.png",
    "assets/sprites/notation/note_3.png",
]
OUTPUT = "assets/sprites/notation_glyphs.png"

sheet = Image.new("RGBA", (FRAME_SIZE * len(SOURCES), FRAME_SIZE), (0, 0, 0, 0))

for i, src in enumerate(SOURCES):
    img = Image.open(src).convert("RGBA")
    if img.size != (FRAME_SIZE, FRAME_SIZE):
        img = img.resize((FRAME_SIZE, FRAME_SIZE), Image.NEAREST)
    sheet.paste(img, (i * FRAME_SIZE, 0))

Path(OUTPUT).parent.mkdir(parents=True, exist_ok=True)
sheet.save(OUTPUT)
print(f"Saved {OUTPUT} ({sheet.width}×{sheet.height}px)")
